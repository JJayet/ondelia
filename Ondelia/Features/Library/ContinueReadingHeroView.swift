import SwiftUI

/// The one book in evidence on the wide shelf (design 7a): big cover, "Resume" eyebrow, the
/// volume's title, where it belongs and what is left, a progress hairline and a play target.
struct ContinueReadingHeroView: View {
    let entry: ContinueReadingEntry
    let onTap: () -> Void

    private var book: AudiobookModel { entry.book }

    private var group: CollectionGroup? {
        if case .collection(let group, _) = entry { return group }
        return nil
    }

    /// The collection when the book belongs to one, as the phone card and the small rows do;
    /// the book's own title otherwise.
    private var title: String {
        group?.name ?? book.title ?? AudiobookModel.unknownTitle
    }

    /// "Iron Gold (1 of 2) · 55 h 03 left" under a collection, "Pierce Brown · 11 h left" under a book.
    private var context: String {
        let remaining = String(
            format: NSLocalizedString("%@ left", comment: "Remaining listening time"),
            (group?.remaining ?? max(book.duration - book.currentPosition, 0)).hoursMinutesFormatted
        )
        let lead = group == nil ? book.author : book.title
        guard let lead else { return remaining }
        return "\(lead) · \(remaining)"
    }

    private var progress: Double {
        if let group { return group.progressFraction }
        return book.progressFraction
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 18) {
                CoverArtView(audiobook: book, size: 112, cornerRadius: 13)
                    .shadow(color: .black.opacity(0.45), radius: 13, y: 12)

                VStack(alignment: .leading, spacing: 0) {
                    Text(NSLocalizedString("Resume", comment: "Wide shelf: eyebrow over the book to pick up").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.tint)

                    HStack(spacing: 8) {
                        if group?.isSeries == true {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                        Text(title)
                            .font(.system(size: 23, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.top, 6)

                    Text(context)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 5)

                    Spacer(minLength: 10)

                    ProgressLine(value: progress, height: 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .offset(x: 2)
                    .frame(width: 56, height: 56)
                    .background(.tint, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            }
            .padding(16)
            .frame(height: 144)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(context)
    }
}
