import SwiftUI

// Empty-state row suitable for inside List
struct EmptyRowView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.secondaryText)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
        .background(Color.clear)
    }
}
