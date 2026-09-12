import StoreKit
import SwiftUI

/// Three consumable tips, nothing unlocked in return. Hidden until the App Store has answered,
/// so an offline launch or an unapproved product never shows an empty card.
struct TipJarSection: View {
    static let productIDs = ["io.jayet.Isora.tip.small", "io.jayet.Isora.tip.medium", "io.jayet.Isora.tip.large"]

    @Environment(\.purchase) private var purchase
    @State private var products: [Product] = []
    @State private var thanked = false

    var body: some View {
        if !products.isEmpty {
            SettingsSection(title: String(localized: "Tip Jar", comment: "Settings section title")) {
                ForEach(products) { product in
                    Button { Task { await tip(product) } } label: {
                        SettingsRow(title: product.displayName) {
                            SettingsValue(text: product.displayPrice, chevron: false)
                        }
                    }
                    .buttonStyle(.plain)
                    if product.id != products.last?.id { SettingsDivider() }
                }
                if thanked {
                    SettingsDivider()
                    SettingsRow(title: String(localized: "Thank you for your support!", comment: "Tip jar: shown after a tip"), icon: "heart.fill", iconTint: .pink)
                }
            }
        }
        Color.clear.frame(height: 0).task { await load() }
    }

    private func load() async {
        products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price }
        // A tip interrupted before finish() would otherwise be redelivered forever.
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { await transaction.finish() }
        }
    }

    private func tip(_ product: Product) async {
        guard case .success(.verified(let transaction)) = try? await purchase(product) else { return }
        await transaction.finish()
        withHapticFeedback(.medium) { thanked = true }
    }
}
