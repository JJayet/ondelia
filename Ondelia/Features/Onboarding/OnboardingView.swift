import SwiftUI

/// The first-launch welcome: six pages that get a book into the library and set the options
/// worth choosing before the first listen.
/// Deeper features are left to the in-context tips (`AppTips`), where they are remembered.
struct OnboardingView: View {
    static let completedKey = "onboarding.completed"

    /// UI tests and screenshots start on the library, never on this.
    static var suppressed: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    let onFinish: () -> Void

    @State var page = 0
    @State private var showingImporter = false
    @State private var importedCount = 0
    @State private var insets = EdgeInsets()
    let pageCount = 6

    var body: some View {
        ZStack {
            TintedBackground(intensity: 0.9).ignoresSafeArea()

            FoldSplit(showsMiniPlayer: false) {
                foldSteps
            } secondary: {
                VStack(spacing: 16) {
                    pages.environment(\.onboardingLeading, true)
                    continueButton
                        .padding(.leading, 18)
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 16)
            } fallback: {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(NSLocalizedString("Skip", comment: "Onboarding: skip button")) {
                            withHapticFeedback { onFinish() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .buttonStyle(.glass)
                        .foregroundStyle(.primary)
                        .opacity(page == pageCount - 1 ? 0 : 1)
                    }
                    .padding(.horizontal, 20)
                    // iPhone Duo's outer display keeps its status bar in a column beside the
                    // content, leaving almost no top inset: Skip lines up with its clock instead.
                    .padding(.top, insets.trailing - insets.leading > 40 ? max(8, 74 - insets.top) : 8)
                    .frame(maxWidth: 620)

                    pages

                    OnboardingPageControl(page: $page, count: pageCount)
                        .frame(height: 32)
                        .padding(.vertical, 4)

                    continueButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 620)
                }
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
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

    private var pages: some View {
        TabView(selection: $page) {
            OnboardingPage { OnboardingWelcomePage() }.tag(0)
            OnboardingPage {
                OnboardingImportPage(importedCount: importedCount) { showingImporter = true }
            }.tag(1)
            OnboardingPage { OnboardingLookPage() }.tag(2)
            OnboardingPage { OnboardingPlaybackPage() }.tag(3)
            OnboardingPage { OnboardingConnectPage() }.tag(4)
            OnboardingPage { OnboardingReadyPage() }.tag(5)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var continueButton: some View {
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
                .frame(minHeight: 52)
        }
        .buttonStyle(.glassProminent)
    }
}

// MARK: - Shared page pieces

/// A big symbol, a title and a line of body, the shape every page starts from.
struct OnboardingHeader: View {
    @Environment(\.onboardingCompactHeader) private var compactHeader
    @Environment(\.onboardingLeading) private var leading
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: compactHeader ? 10 : 18) {
            Image(systemName: systemImage)
                .font(.system(size: compactHeader ? 36 : 64, weight: .medium))
                .foregroundStyle(.tint)
                .frame(height: compactHeader ? 44 : 80)

            Text(title)
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .multilineTextAlignment(leading ? .leading : .center)

            Text(text)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.75))
                .multilineTextAlignment(leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
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
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Onboarding") {
    OnboardingView {}
}


private struct OnboardingCompactHeaderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Beside the fold the page reads from the left edge, under the steps' column (design 14).
    @Entry var onboardingLeading = false
}

private extension EnvironmentValues {
    var onboardingCompactHeader: Bool {
        get { self[OnboardingCompactHeaderKey.self] }
        set { self[OnboardingCompactHeaderKey.self] = newValue }
    }
}

/// Each page owns its vertical scrolling; navigation never covers its content.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .environment(\.onboardingCompactHeader, geometry.size.height < 650)
                    .frame(maxWidth: 620)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
        }
    }
}

/// Native pagination keeps VoiceOver's localized page announcements and adjustable navigation.
private struct OnboardingPageControl: UIViewRepresentable {
    @Binding var page: Int
    let count: Int

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        context.coordinator.page = $page
        control.numberOfPages = count
        control.currentPage = page
        control.currentPageIndicatorTintColor = .label
        control.pageIndicatorTintColor = .tertiaryLabel
    }

    @MainActor final class Coordinator: NSObject {
        var page: Binding<Int>

        init(page: Binding<Int>) { self.page = page }

        @objc func changed(_ control: UIPageControl) {
            withAnimation { page.wrappedValue = control.currentPage }
        }
    }
}
