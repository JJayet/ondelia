import Foundation
import SwiftUI

@MainActor
@Observable
final class PlayerRouter {
    struct PlayerPresentation: Identifiable, Equatable {
        let id: UUID
    }

    // Present by stable ID to avoid SwiftUI sheet re-present loops when the model mutates
    var presented: PlayerPresentation?
    
    func present(_ audiobook: AudiobookModel) {
        presented = PlayerPresentation(id: audiobook.id)
    }
}

extension EnvironmentValues {
    @Entry var playerRouter: PlayerRouter?
}
