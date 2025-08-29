import SwiftUI

struct TranscriptionLoader: View {
    @State private var currentPhraseIndex = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var thinking: Bool = false
    
    let phrases = [
        "Transcribing             ",
        "Enjoying your book       ",
        "Almost done...           ",
        "You're in for a good time",
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles.inverse")
                .font(.title)
                .foregroundStyle(EllipticalGradient(colors:[.accentColor, .secondary], center: .center, startRadiusFraction: 0.0, endRadiusFraction: 0.5))
                .phaseAnimator([false , true]) { ai, thinking in
                    ai
                        .symbolEffect(.wiggle.byLayer, value: thinking)
                        .symbolEffect(.bounce.byLayer, value: thinking)
                        .symbolEffect(.breathe.byLayer, value: thinking)
                }
            
            HStack(spacing: 0) {
                ForEach(Array(phrases[currentPhraseIndex].enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .foregroundStyle(.blue)
                        .hueRotation(.degrees(thinking ? 220 : 0))
                        .opacity(thinking ? 0 : 1)
                        .scaleEffect(thinking ? 1.5 : 1, anchor: .bottom)
                        .animation(.easeInOut(duration: 0.5).delay(1).repeatForever(autoreverses: false).delay(Double(index) / 20), value: thinking)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            thinking = true
        }
        .onReceive(timer) { _ in
            withAnimation {
                currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            }
        }
    }
}


#Preview {
    TranscriptionLoader()
        .preferredColorScheme(.dark)
}
