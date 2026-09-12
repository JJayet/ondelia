import SwiftUI

/// The first-launch welcome: four pages whose one job is to get a book into the library.
/// Deeper features are left to the in-context tips (`AppTips`), where they are remembered.
struct OnboardingView: View {
    static let completedKey = "onboarding.completed"

    /// UI tests and screenshots start on the library, never on this.
    static var suppressed: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    let onFinish: () -> Void

    @State private var page = 0
    @State private var showingImporter = false
    @State private var importedCount = 0
    private let pageCount = 4

    var body: some View {
        ZStack {
            TintedBackground(intensity: 0.9).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Skip", comment: "Onboarding: skip button")) {
                        withHapticFeedback { onFinish() }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(page == pageCount - 1 ? 0 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                TabView(selection: $page) {
                    OnboardingWelcomePage().tag(0)
                    OnboardingImportPage(importedCount: importedCount) { showingImporter = true }.tag(1)
                    OnboardingConnectPage().tag(2)
                    OnboardingReadyPage().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    withHapticFeedback {
                        if page < pageCount - 1 {
                            withAnimation { page += 1 }
                        } else {
                            onFinish()
                        }
                    }
                } label: {
                    Text(page == pageCount - 1
                        ? NSLocalizedString("Get Started", comment: "Onboarding: last page button")
                        : NSLocalizedString("Continue", comment: "Onboarding: next page button"))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingImporter) {
            DocumentPickerView { urls in
                showingImporter = false
                guard !urls.isEmpty else { return }
                importedCount += urls.count
                AudiobookManager.shared.handleImportRequest(urls: urls)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Shared page pieces

/// A big symbol, a title and a line of body, the shape every page starts from.
struct OnboardingHeader: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
                .frame(height: 80)

            Text(title)
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)

            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
    }
}

/// One feature line: symbol, bold name, one sentence.
struct OnboardingFeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Onboarding") {
    OnboardingView {}
}
