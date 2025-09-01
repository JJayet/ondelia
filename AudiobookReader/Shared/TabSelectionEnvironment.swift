import SwiftUI

private struct TabSelectionSetterKey: EnvironmentKey {
    static let defaultValue: ((Int) -> Void)? = nil
}

extension EnvironmentValues {
    var setTabSelection: ((Int) -> Void)? {
        get { self[TabSelectionSetterKey.self] }
        set { self[TabSelectionSetterKey.self] = newValue }
    }
}

