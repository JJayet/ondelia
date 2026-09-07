import SwiftUI

struct EmptyLibraryView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundStyle(Color.secondaryText)

            VStack(spacing: 8) {
                Text(
                    NSLocalizedString(
                        "Your library is empty",
                        comment: "Empty library title"
                    )
                )
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.primaryText)

                Text(
                    NSLocalizedString(
                        "Import your first audiobook to get started",
                        comment: "Empty library instructions"
                    )
                )
                .font(.body)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
            }

            Button(NSLocalizedString("Import Audiobook", comment: "Import button title"), systemImage: "plus.circle") {
                withHapticFeedback { onImport() }
            }
            .buttonStyle(.glassProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Empty Library View") {
    EmptyLibraryView {}
}
