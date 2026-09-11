import SwiftUI

struct TranscriptionLoader: View {
    /// Share of the window recognised so far, 0 to 1. Hidden until the first result lands.
    var progress: Double = 0
    var isDownloadingModel = false

    @State private var currentPhraseIndex = 0
    @State private var thinking: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // Padded to equal length so the animated HStack keeps a stable width.
    let phrases: [String] = {
        let raw = [
            NSLocalizedString("Transcribing", comment: "Transcription loader phrase"),
            NSLocalizedString("Enjoying your book", comment: "Transcription loader phrase"),
            NSLocalizedString("Almost done...", comment: "Transcription loader phrase"),
            NSLocalizedString("You're in for a good time", comment: "Transcription loader phrase"),
        ]
        let width = raw.map(\.count).max() ?? 0
        return raw.map { $0.padding(toLength: width, withPad: " ", startingAt: 0) }
    }()
    
    var body: some View {
        VStack(spacing: 16) {
            phraseRow
            if isDownloadingModel {
                Text(NSLocalizedString("Downloading language model…", comment: "Transcription loader: the speech model is being fetched"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            }
        }
    }

    private var phraseRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles.inverse")
                .font(.title)
                .foregroundStyle(EllipticalGradient(colors:[.accentColor, .secondary], center: .center, startRadiusFraction: 0.0, endRadiusFraction: 0.5))
                .phaseAnimator([false, true]) { ai, thinking in
                    ai
                        .symbolEffect(.wiggle.byLayer, value: thinking && !reduceMotion)
                        .symbolEffect(.bounce.byLayer, value: thinking && !reduceMotion)
                        .symbolEffect(.breathe.byLayer, value: thinking && !reduceMotion)
                }
            
            HStack(spacing: 0) {
                ForEach(Array(phrases[currentPhraseIndex].enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .foregroundStyle(.tint)
                        .hueRotation(.degrees(thinking ? 220 : 0))
                        .opacity(thinking ? 0 : 1)
                        .scaleEffect(thinking ? 1.5 : 1, anchor: .bottom)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).delay(1).repeatForever(autoreverses: false).delay(Double(index) / 20), value: thinking)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            // Reduce Motion keeps the phrase legible instead of dissolving it letter by letter.
            thinking = !reduceMotion
        }
        .task {
            // Cancelled with the view, so the rotation stops when the loader goes away.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(reduceMotion ? nil : Animation.default) {
                    currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
                }
            }
        }
    }
}


#Preview {
    TranscriptionLoader()
        .preferredColorScheme(.dark)
}
