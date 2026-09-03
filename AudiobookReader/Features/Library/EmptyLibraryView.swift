import SwiftUI

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
        .frame(maxWidth: .infinity)
    }
}

#Preview("Empty Library View") {
    EmptyLibraryView()
}
