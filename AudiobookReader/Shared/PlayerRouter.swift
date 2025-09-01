import Foundation
import SwiftUI

@MainActor
final class PlayerRouter: ObservableObject {
    struct PlayerPresentation: Identifiable, Equatable {
        let id: UUID
    }

    // Present by stable ID to avoid SwiftUI sheet re-present loops when the model mutates
    @Published var presented: PlayerPresentation?
    
    func present(_ audiobook: AudiobookModel) {
        presented = PlayerPresentation(id: audiobook.id)
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
