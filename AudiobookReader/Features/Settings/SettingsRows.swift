import SwiftUI

struct SettingsRowCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

