import SwiftUI

private struct MiniPlayerNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var miniPlayerNamespace: Namespace.ID? {
        get { self[MiniPlayerNamespaceKey.self] }
        set { self[MiniPlayerNamespaceKey.self] = newValue }
    }
}

