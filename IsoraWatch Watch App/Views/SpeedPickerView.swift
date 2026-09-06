import SwiftUI

struct SpeedPickerView: View {
    @Environment(\.dismiss) private var dismiss

    private var audio: WatchAudioManager { .shared }

    var body: some View {
        List(WatchAudioManager.speeds, id: \.self) { speed in
            Button {
                audio.setRate(speed)
                dismiss()
            } label: {
                HStack {
                    Text("\(speed.formatted(.number.precision(.fractionLength(0...1))))×")
                    Spacer(minLength: 0)
                    if speed == audio.player.playbackRate {
                        Image(systemName: "checkmark").font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(Text(String(localized: "Speed")))
    }
}

#Preview {
    SpeedPickerView()
}
