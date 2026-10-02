import SwiftUI
import UIKit

struct SearchResultRow: View {
    /// A Library book, or a server audiobook that has not joined (ADR 0002).
    let entry: LibraryEntry
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                if !entry.title.isEmpty {
                    Text(highlighted(entry.title, query: query))
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                } else {
                    Text(AudiobookModel.unknownTitle)
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                }

                if !entry.author.isEmpty {
                    Text(highlighted(entry.author, query: query))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(AudiobookModel.unknownAuthor)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer()
            if let audiobook = entry.book {
                Text(percentageString(audiobook))
                    .font(.subheadline) // a little bigger than caption
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.secondaryText)
                    .monospacedDigit()
                    .accessibilityLabel(accessibilityProgress(audiobook))
            } else {
                Image(systemName: "icloud")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.secondaryText)
                    .accessibilityLabel(NSLocalizedString("On the server", comment: "Server audiobook not in the Library"))
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var cover: some View {
        switch entry {
        case .server(let item):
            AudiobookShelfCover(item: item.id, title: item.title, size: 60, cornerRadius: 8)
        case .book(let audiobook):
            bookCover(audiobook)
        }
    }

    private func bookCover(_ audiobook: AudiobookModel) -> some View {
        Group {
            if let image = CoverImageCache.image(for: audiobook) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondaryBackground)
                    Image(systemName: "book.closed")
                        .foregroundStyle(Color.secondaryText)
                }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func percent(_ audiobook: AudiobookModel) -> Double {
        guard audiobook.duration > 0 else { return 0 }
        return min(max(audiobook.currentPosition / audiobook.duration, 0), 1)
    }

    private func percentageString(_ audiobook: AudiobookModel) -> String {
        "\(Int(percent(audiobook) * 100))%"
    }

    private func accessibilityProgress(_ audiobook: AudiobookModel) -> String {
        let elapsed = audiobook.currentPosition
        let total = audiobook.duration
        func fmt(_ t: TimeInterval) -> String {
            let h = Int(t) / 3600
            let m = (Int(t) % 3600) / 60
            if h > 0 { return "\(h)h \(m)m" } else { return "\(m)m" }
        }
        return String(
            format: NSLocalizedString("%@, %@ of %@", comment: "Accessibility progress: percent, elapsed time of total time"),
            percentageString(audiobook), fmt(elapsed), fmt(total)
        )
    }

    private func highlighted(_ text: String, query: String) -> AttributedString {
        var attr = AttributedString(text)
        let normText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normQuery.isEmpty,
              let r = normText.range(of: normQuery) else { return attr }

        // Map normalized range back to original string by character offsets
        let lowerOffset = normText.distance(from: normText.startIndex, to: r.lowerBound)
        let upperOffset = normText.distance(from: normText.startIndex, to: r.upperBound)
        let origLower = text.index(text.startIndex, offsetBy: lowerOffset)
        let origUpper = text.index(text.startIndex, offsetBy: upperOffset)

        if let lower = AttributedString.Index(origLower, within: attr),
           let upper = AttributedString.Index(origUpper, within: attr) {
            attr[lower..<upper].foregroundColor = .accentColor
            attr[lower..<upper].font = .headline.bold()
        }
        return attr
    }
}
