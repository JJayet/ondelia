import SwiftUI

struct LibraryHeaderView: View {
    @Binding var viewMode: LibraryView.ViewMode
    @Binding var sortOption: LibraryView.SortOption
    @Binding var filterOption: LibraryView.FilterOption

    var body: some View {
        HStack(spacing: 16) {
            // Filter Options
            Menu {
                ForEach(LibraryView.FilterOption.allCases, id: \.rawValue) {
                    option in
                    Button(option.displayName) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterOption = option
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(filterOption.displayName)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.caption)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }

            // Sort Options
            Menu {
                ForEach(LibraryView.SortOption.allCases, id: \.rawValue) {
                    option in
                    Button(option.displayName) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sortOption = option
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.displayName)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.caption)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()

            // View Mode Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewMode = viewMode == .list ? .grid : .list
                }
            } label: {
                Image(systemName: viewMode.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
        }
    }
}

struct LibraryContentView: View {
    let audiobooks: [AudiobookModel]
    let viewMode: LibraryView.ViewMode
    let isImporting: Bool
    let onSelect: (AudiobookModel) -> Void
    let onDelete: (AudiobookModel) -> Void

    var body: some View {
        if viewMode == .list {
            List {
                if isImporting {
                    ImportingIndicatorView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(audiobooks, id: \.id) { audiobook in
                    EnhancedAudiobookRowView(audiobook: audiobook) {
                        onSelect(audiobook)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(
                            NSLocalizedString(
                                "Delete",
                                comment: "Delete audiobook button"
                            )
                        ) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                onDelete(audiobook)
                            }
                        }
                        .tint(.red)
                    }
                }
            }
            .listStyle(PlainListStyle())
            .background(Color.clear)
        } else {
            LazyVStack(spacing: 16) {
                if isImporting {
                    ImportingIndicatorView()
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ],
                    spacing: 16
                ) {
                    ForEach(audiobooks, id: \.id) { audiobook in
                        AudiobookGridItemView(audiobook: audiobook) {
                            onSelect(audiobook)
                        }
                        .contextMenu {
                            Button(
                                NSLocalizedString(
                                    "Delete",
                                    comment: "Delete audiobook button"
                                ),
                                role: .destructive
                            ) {
                                onDelete(audiobook)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EnhancedAudiobookRowView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundColor(.secondaryText)
                    }
                }
                .frame(width: 70, height: 70)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .clipped()
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                // Book Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        audiobook.title
                            ?? NSLocalizedString(
                                "Unknown Title",
                                comment: "Default audiobook title"
                            )
                    )
                    .font(.headline)
                    .foregroundColor(.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                    Text(
                        audiobook.author
                            ?? NSLocalizedString(
                                "Unknown Author",
                                comment: "Default audiobook author"
                            )
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)

                    // Progress Section
                    HStack {
                        if audiobook.isFinished {
                            Label(
                                NSLocalizedString(
                                    "Completed",
                                    comment: "Audiobook completed status"
                                ),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundColor(.green)
                        } else if audiobook.currentPosition > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: progressPercentage)
                                    .progressViewStyle(
                                        LinearProgressViewStyle(
                                            tint: .accentColor
                                        )
                                    )
                                    .frame(height: 3)

                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "%d%% complete",
                                            comment: "Progress percentage"
                                        ),
                                        Int(progressPercentage * 100)
                                    )
                                )
                                .font(.caption2)
                                .foregroundColor(.secondaryText)
                            }
                        } else {
                            Text(
                                NSLocalizedString(
                                    "Not Started",
                                    comment: "Audiobook not started status"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                        }

                        Spacer()

                        Text(formatDuration(audiobook.duration))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
            .padding(16)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct AudiobookGridItemView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundColor(.secondaryText)
                    }
                }
                .frame(width: 120, height: 120)
                .background(Color.secondaryBackground)
                .cornerRadius(16)
                .clipped()
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Color.accentColor.opacity(
                                audiobook.currentPosition > 0 ? 0.3 : 0
                            ),
                            lineWidth: 2
                        )
                )

                // Book Info
                VStack(spacing: 4) {
                    Text(
                        audiobook.title
                            ?? NSLocalizedString(
                                "Unknown Title",
                                comment: "Default audiobook title"
                            )
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                    Text(
                        audiobook.author
                            ?? NSLocalizedString(
                                "Unknown Author",
                                comment: "Default audiobook author"
                            )
                    )
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)

                    // Progress Indicator
                    if audiobook.isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if audiobook.currentPosition > 0 {
                        ProgressView(value: progressPercentage)
                            .progressViewStyle(
                                LinearProgressViewStyle(tint: .accentColor)
                            )
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(Color.cardBackground)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ContinueReadingCardView: View {
    let audiobook: AudiobookModel
    let onTap: () -> Void

    private var coverImage: UIImage? {
        guard let data = audiobook.coverImageData else { return nil }
        return UIImage(data: data)
    }

    private var progressPercentage: Double {
        guard audiobook.duration > 0 else { return 0 }
        return audiobook.currentPosition / audiobook.duration
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Cover Art
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30))
                            .foregroundColor(.secondaryText)
                    }
                }
                .frame(width: 140, height: 100)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        audiobook.title
                            ?? NSLocalizedString(
                                "Unknown Title",
                                comment: "Default audiobook title"
                            )
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)
                    .lineLimit(2)

                    ProgressView(value: progressPercentage)
                        .progressViewStyle(
                            LinearProgressViewStyle(tint: .accentColor)
                        )
                        .frame(height: 3)

                    Text("\(Int(progressPercentage * 100))% complete")
                        .font(.caption2)
                        .foregroundColor(.secondaryText)
                }
            }
            .frame(width: 140)
            .padding(12)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ImportingIndicatorView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text(
                NSLocalizedString(
                    "Importing...",
                    comment: "Importing audiobook status"
                )
            )
            .font(.subheadline)
            .foregroundColor(.secondaryText)

            Spacer()
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundColor(.secondaryText)

            VStack(spacing: 8) {
                Text(
                    NSLocalizedString(
                        "Your library is empty",
                        comment: "Empty library title"
                    )
                )
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primaryText)

                Text(
                    NSLocalizedString(
                        "Import your first audiobook to get started",
                        comment: "Empty library instructions"
                    )
                )
                .font(.body)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

#Preview("Library Header View") {
    LibraryHeaderView(
        viewMode: .constant(.list),
        sortOption: .constant(.lastPlayed),
        filterOption: .constant(.all)
    )
}

#Preview("Empty Library View") {
    EmptyLibraryView()
}
