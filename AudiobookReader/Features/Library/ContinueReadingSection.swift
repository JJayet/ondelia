import SwiftUI

/// "Continue Reading" header + horizontal card strip, shared by list and grid modes.
struct ContinueReadingSection: View {
    let books: [AudiobookModel]
    /// Horizontal padding applied to the header row (`nil` = system default).
    let headerPadding: CGFloat?
    /// Horizontal padding applied to the scrolling card row (`nil` = system default).
    let rowPadding: CGFloat?
    let onSelect: (AudiobookModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(NSLocalizedString("Continue Reading", comment: "Section title for books in progress"))
                .padding(.horizontal, headerPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(books, id: \.id) { (audiobook: AudiobookModel) in
                        ContinueReadingCardView(audiobook: audiobook) { onSelect(audiobook) }
                    }
                }
                .padding(.horizontal, rowPadding)
            }
        }
    }
}
