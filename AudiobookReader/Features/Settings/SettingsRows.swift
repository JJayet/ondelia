import SwiftUI

/// One grouped card of settings rows. The design draws each section as a single glass panel
/// with hairline-separated rows inside, rather than the inset-grouped `List` rows the screen
/// used to be built from.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .glassCard()
    }
}

/// The hairline between two rows, inset past the row's leading padding.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 0.5)
            .padding(.leading, 18)
    }
}

/// A settings row: title on the left, whatever the row is controlled by on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    /// Optional leading tile — the design only gives one to integrations.
    var icon: String?
    var iconTint: Color = .accentColor
    var titleColor: Color = .primary
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 28, height: 28)
                    .background(iconTint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(titleColor)

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, icon: String? = nil, iconTint: Color = .accentColor, titleColor: Color = .primary) {
        self.init(title: title, icon: icon, iconTint: iconTint, titleColor: titleColor) { EmptyView() }
    }
}

/// The right-hand value of a row that opens something rather than holding a control.
struct SettingsValue: View {
    let text: String
    var chevron = true

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// What the Hardcover integration is currently doing, under its row: green check and the last
/// sync when it is linked, an invitation when it is not.
struct HardcoverStatusLine: View {
    private let service = HardcoverService.shared

    var body: some View {
        HStack(spacing: 5) {
            if service.isLinked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var text: String {
        guard service.isLinked else {
            return NSLocalizedString("Not connected", comment: "Hardcover status: no token")
        }
        guard let date = service.lastSyncedAt else {
            return NSLocalizedString("Connected", comment: "Hardcover status: linked, never synced")
        }
        return String(
            format: NSLocalizedString("Synced %@", comment: "Hardcover status: relative last sync"),
            date.formatted(.relative(presentation: .named))
        )
    }
}

/// Section label + its card, so every section is written the same way.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title).padding(.horizontal, 8)
            SettingsCard { content }
        }
    }
}
