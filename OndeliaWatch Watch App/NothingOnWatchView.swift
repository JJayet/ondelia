import SwiftUI

/// Shown while the watch holds no book. The button is injected because what it asks for
/// depends on what the phone last reported, which this view knows nothing about.
struct NothingOnWatchView: View {
    var requestTitle: String?
    var onRequest: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            icon
            Text(String(localized: "Nothing on the watch"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(String(localized: "Books are sent from the iPhone: open a book, then “Send to Apple Watch”."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            if let requestTitle, let onRequest {
                Button(requestTitle, action: onRequest)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview("Empty") {
    NothingOnWatchView()
}

#Preview("With request") {
    NothingOnWatchView(requestTitle: "Ask for ch. 3", onRequest: {})
}
