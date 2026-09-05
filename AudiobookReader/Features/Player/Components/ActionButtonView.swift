import SwiftUI

/// Sets an identifier only when there is one. `.accessibilityIdentifier("")` is not a no-op:
/// it labels the element with the empty string, which every unlabelled element then matches.
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct PlayerActionButton: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var accessibilityIdentifier: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                    
                    if let count = count, count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 12, y: -12)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.primaryText)
            }
        }
        .buttonStyle(.plain)
        .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
    }
}
