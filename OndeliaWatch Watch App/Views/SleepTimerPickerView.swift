import SwiftUI

struct SleepTimerPickerView: View {
    @Environment(\.dismiss) private var dismiss

    private var audio: WatchAudioManager { .shared }

    var body: some View {
        List(SleepTimerOption.all) { option in
            Button {
                audio.setSleepTimer(option)
                dismiss()
            } label: {
                HStack {
                    Text(option.label)
                    Spacer(minLength: 0)
                    if option == audio.sleepTimer {
                        Image(systemName: "checkmark").font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(Text(String(localized: "Sleep timer")))
    }
}

#Preview {
    SleepTimerPickerView()
}
