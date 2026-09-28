import SwiftUI

/// The books of one AudiobookShelf library, paged by title, with server-side search.
struct AudiobookShelfLibraryView: View {
    private let service = AudiobookShelfService.shared

    @State private var libraries: [AudiobookShelfAPI.Library] = []
    @State private var library: String?
    @State private var items: [AudiobookShelfAPI.Item] = []
    @State private var total = 0
    @State private var page = 0
    @State private var isLoading = false
    @State private var error: String?
    @State private var query = ""
    @State private var results: [AudiobookShelfAPI.Item]?

    private var shown: [AudiobookShelfAPI.Item] { results ?? items }

    var body: some View {
        // Once per body rather than once per row: it walks the whole library.
        let inLibrary = service.itemsInLibrary
        List {
            ForEach(shown) { item in
                AudiobookShelfItemRow(item: item, inLibrary: inLibrary.contains(item.id))
                    .onAppear {
                        if results == nil, item.id == items.last?.id { Task { await loadPage() } }
                    }
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .overlay { emptyState }
        .navigationTitle(libraries.first { $0.id == library }?.name ?? "AudiobookShelf")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(TintedBackground(intensity: 0.6))
        .searchable(text: $query, prompt: NSLocalizedString("Search", comment: "AudiobookShelf search field"))
        .task(id: query) { await search() }
        .toolbar {
            if libraries.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker(
                        NSLocalizedString("Library", comment: "AudiobookShelf library picker"),
                        selection: $library
                    ) {
                        ForEach(libraries) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .task { await loadLibraries() }
        .onChange(of: library) {
            service.selectedLibrary = library
            items = []
            total = 0
            page = 0
            Task { await loadPage() }
        }
        .alert(
            NSLocalizedString("Download Failed", comment: "AudiobookShelf download error title"),
            isPresented: Binding(get: { service.downloadError != nil }, set: { _ in service.downloadError = nil })
        ) {
            Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {}
        } message: {
            Text(service.downloadError ?? "")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let error, shown.isEmpty {
            ContentUnavailableView(
                NSLocalizedString("Couldn't Load Library", comment: "AudiobookShelf load failure title"),
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if results?.isEmpty == true {
            ContentUnavailableView.search(text: query)
        } else if !isLoading, page > 0, items.isEmpty {
            ContentUnavailableView(
                NSLocalizedString("No Books", comment: "AudiobookShelf empty library title"),
                systemImage: "books.vertical"
            )
        } else if !isLoading, libraries.isEmpty, error == nil, library == nil {
            ContentUnavailableView(
                NSLocalizedString("No Book Libraries", comment: "AudiobookShelf: server has no book library"),
                systemImage: "books.vertical"
            )
        }
    }

    private func loadLibraries() async {
        guard libraries.isEmpty, let server = service.server, let token = service.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            libraries = try await AudiobookShelfAPI.libraries(server: server, token: token)
            let saved = service.selectedLibrary
            library = libraries.contains { $0.id == saved } ? saved : libraries.first?.id
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPage() async {
        guard !isLoading, let library, let server = service.server, let token = service.token,
              page == 0 || items.count < total
        else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await AudiobookShelfAPI.items(server: server, token: token, library: library, page: page)
            // The library changed while this page was loading: its items belong to the old one.
            guard library == self.library else { return }
            items += response.items
            total = response.total
            page += 1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            results = nil
            return
        }
        // Debounce: `.task(id:)` cancels this sleep when the next keystroke arrives.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, let library, let server = service.server, let token = service.token else { return }
        do {
            results = try await AudiobookShelfAPI.search(server: server, token: token, library: library, query: text)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AudiobookShelfItemRow: View {
    let item: AudiobookShelfAPI.Item
    let inLibrary: Bool
    private let service = AudiobookShelfService.shared

    var body: some View {
        HStack(spacing: 12) {
            AudiobookShelfCover(item: item.id)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                if let author = item.author {
                    Text(author)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let duration = item.media.duration, duration > 0 {
                    Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            downloadButton
        }
    }

    @ViewBuilder private var downloadButton: some View {
        if let progress = service.downloads[item.id] {
            Button {
                withHapticFeedback { service.cancelDownload(id: item.id) }
            } label: {
                AudiobookShelfDownloadProgress(progress: progress)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(NSLocalizedString("Cancel Download", comment: "AudiobookShelf: cancel download button"))
        } else if service.downloaded.contains(item.id) || inLibrary {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(NSLocalizedString("Downloaded", comment: "AudiobookShelf: item downloaded"))
        } else {
            Button {
                withHapticFeedback { service.download(item) }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(NSLocalizedString("Download", comment: "AudiobookShelf: download item button"))
        }
    }
}

/// A ring filling up when the size is known; otherwise a spinner over the megabytes so far.
private struct AudiobookShelfDownloadProgress: View {
    let progress: AudiobookShelfService.DownloadProgress

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let fraction = progress.fraction {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: fraction)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tint)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 24, height: 24)

            Text(progress.fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) }
                ?? progress.received.formatted(.byteCount(style: .file)))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minWidth: 44)
        .accessibilityValue(Text(progress.fraction.map { $0.formatted(.percent) }
            ?? progress.received.formatted(.byteCount(style: .file))))
    }
}

/// A cover fetched with the bearer header. `AsyncImage` cannot set headers.
private struct AudiobookShelfCover: View {
    let item: String
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "book.closed").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .task(id: item) {
                let service = AudiobookShelfService.shared
                guard let server = service.server, let token = service.token else { return }
                let request = AudiobookShelfAPI.coverRequest(server: server, token: token, item: item)
                guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
                image = UIImage(data: data)
            }
    }
}
