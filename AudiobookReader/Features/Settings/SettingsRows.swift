import SwiftUI

struct SettingsRowCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

struct StatisticRowView: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
