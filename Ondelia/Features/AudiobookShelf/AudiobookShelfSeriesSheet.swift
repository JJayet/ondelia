import SwiftUI

/// The order a server series' books are shown in: the server's own (series order, or the
/// collection's), or by title, author or length.
enum AudiobookShelfSeriesOrder: CaseIterable {
    case title, author, duration

    var title: String {
        switch self {
        case .title: NSLocalizedString("Title", comment: "Sort option: by title")
        case .author: NSLocalizedString("Author", comment: "Sort option: by author")
        case .duration: NSLocalizedString("Duration", comment: "Sort option: by duration")
        }
    }

    func sorted(_ items: [AudiobookShelfAPI.Item]) -> [AudiobookShelfAPI.Item] {
        switch self {
        case .title: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: items.sorted { ($0.author ?? "").localizedStandardCompare($1.author ?? "") == .orderedAscending }
        case .duration: items.sorted { ($0.media.duration ?? 0) < ($1.media.duration ?? 0) }
        }
    }
}

/// iPhone Duo's left half beside a server series (design 11b): what the grid alone does not
/// say — on the server, nothing here yet, what it weighs — and how to start listening.
struct AudiobookShelfSeriesSheet: View {
    let series: AudiobookShelfAPI.Series
    let books: [AudiobookShelfAPI.Item]
    let library: String
    /// nil: the server's order.
    @Binding var order: AudiobookShelfSeriesOrder?

    @Environment(\.audiobookShelfPlay) private var play

    private var service: AudiobookShelfService { .shared }

    private var onDevice: Int {
        books.filter { item in service.libraryBooks[item.id].map(AudiobookManager.shared.hasFile) ?? false }.count
    }

    /// "52 books · 14h 06m · Not on this device".
    private var facts: String {
        var parts = [String(format: NSLocalizedString("%d books", comment: "AudiobookShelf: number of books in a series or by an author"), books.count)]
        let duration = books.compactMap(\.media.duration).reduce(0, +)
        if duration > 0 { parts.append(duration.hoursMinutesFormatted) }
        if onDevice == 0, !books.isEmpty {
            parts.append(NSLocalizedString("Not on this device", comment: "Missing audio badge"))
        }
        return parts.joined(separator: " · ")
    }

    private var size: String? {
        let bytes = books.compactMap(\.size).reduce(0, +)
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Label(
                    (series.isServerCollection
                        ? NSLocalizedString("Collection · server", comment: "Collections screen row: a server collection")
                        : NSLocalizedString("Series · server", comment: "Collections screen row: a server series")).uppercased(),
                    systemImage: "icloud"
                )
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

                Text(series.name)
                    .font(.system(size: 30, weight: .bold))
                    .padding(.top, 8)

                Text(facts)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)

                actions.padding(.top, 22)

                if let size {
                    Text(String(
                        format: NSLocalizedString("%@. The books stay on the server until you download them.", comment: "Server series: total download size, and what downloading means"),
                        size
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                }

                orderChips.padding(.top, 26)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let first = (order?.sorted(books) ?? books).first {
                Button {
                    withHapticFeedback(.medium) {
                        service.play(first, local: service.libraryBooks[first.id], with: play?.run)
                    }
                } label: {
                    Label(NSLocalizedString("Play the First", comment: "Server series: play its first book"), systemImage: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button {
                withHapticFeedback(.medium) {}
                Task { await service.downloadAll(.series(series), library: library) }
            } label: {
                Label(NSLocalizedString("Download All", comment: "AudiobookShelf: download every book of a series or author"), systemImage: "arrow.down.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(onDevice == books.count)
        }
    }

    /// One chip per order; the lit one again goes back to the server's order.
    private var orderChips: some View {
        HStack(spacing: 8) {
            ForEach(AudiobookShelfSeriesOrder.allCases, id: \.self) { choice in
                Button {
                    withHapticFeedback { order = order == choice ? nil : choice }
                } label: {
                    Text(choice.title)
                        .glassPill(height: 34, tinted: order == choice)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(order == choice ? .isSelected : [])
            }
        }
    }
}
