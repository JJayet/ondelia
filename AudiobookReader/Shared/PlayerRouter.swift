import Foundation
import SwiftUI

@MainActor
final class PlayerRouter: ObservableObject {
    struct PlayerPresentation: Identifiable, Equatable {
        let id: UUID
    }

    // Present by stable ID to avoid SwiftUI sheet re-present loops when the model mutates
    @Published var presented: PlayerPresentation?
    @Published var selectedDetent: PresentationDetent = .large
    @Published private(set) var isDismissing = false
    
    func present(_ audiobook: AudiobookModel) {
        // Prevent immediate re-present during active dismissal animation
        guard !isDismissing else { return }
        presented = PlayerPresentation(id: audiobook.id)
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
        presented = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            isDismissing = false
            // Keep last detent; no need to reset
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
