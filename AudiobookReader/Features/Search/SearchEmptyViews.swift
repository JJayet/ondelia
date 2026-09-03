import SwiftUI

// Empty-state row suitable for inside List
struct EmptyRowView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondaryText)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
        .background(Color.clear)
    }
}
