import SwiftUI
import UIKit

struct SearchResultRow: View {
    let audiobook: AudiobookModel
    let query: String

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                if let title = audiobook.title, !title.isEmpty {
                    Text(highlighted(title, query: query))
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                } else {
                    Text(AudiobookModel.unknownTitle)
                        .font(.headline)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                }

                if let author = audiobook.author, !author.isEmpty {
                    Text(highlighted(author, query: query))
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
            Text(percentageString)
                .font(.subheadline) // a little bigger than caption
                .fontWeight(.semibold)
                .foregroundStyle(Color.secondaryText)
                .monospacedDigit()
                .accessibilityLabel(accessibilityProgress)
        }
        .padding(.vertical, 6)
    }

    private var cover: some View {
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

    private var percent: Double {
        guard audiobook.duration > 0 else { return 0 }
        return min(max(audiobook.currentPosition / audiobook.duration, 0), 1)
    }

    private var percentageString: String {
        "\(Int(percent * 100))%"
    }

    private var accessibilityProgress: String {
        let elapsed = audiobook.currentPosition
        let total = audiobook.duration
        func fmt(_ t: TimeInterval) -> String {
            let h = Int(t) / 3600
            let m = (Int(t) % 3600) / 60
            if h > 0 { return "\(h)h \(m)m" } else { return "\(m)m" }
        }
        return String(
            format: NSLocalizedString("%@, %@ of %@", comment: "Accessibility progress: percent, elapsed time of total time"),
            percentageString, fmt(elapsed), fmt(total)
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
