import Foundation
import SwiftUI

@MainActor
final class PlayerRouter: ObservableObject {
    @Published var presentedAudiobook: AudiobookModel?
    @Published var selectedDetent: PresentationDetent? = nil
    @Published private(set) var isDismissing = false
    
    func present(_ audiobook: AudiobookModel) {
        // Prevent immediate re-present during active dismissal animation
        guard !isDismissing else { return }
        presentedAudiobook = audiobook
    }
    
    func presentFull(_ audiobook: AudiobookModel) {
        selectedDetent = .large
        present(audiobook)
    }
    
    func presentMini(_ audiobook: AudiobookModel) {
        selectedDetent = .height(92)
        present(audiobook)
    }
    
    func dismiss() {
        // Debounce dismissal to avoid AttributeGraph cycles / re-present loops
        isDismissing = true
        presentedAudiobook = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            isDismissing = false
            selectedDetent = nil
        }
    }
}



private struct PlayerRouterKey: EnvironmentKey {
    static var defaultValue: PlayerRouter? = nil
}

extension EnvironmentValues {
    var playerRouter: PlayerRouter? {
        get { self[PlayerRouterKey.self] }
        set { self[PlayerRouterKey.self] = newValue }
    }
}
