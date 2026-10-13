import SwiftUI

// MARK: - Either side of the fold (design 14)
//
// iPhone Duo: the six steps as a list on the left, in place of the dots, with Back and Skip;
// tapping a step goes there. The page and its button on the right, under the right thumb.
extension OnboardingView {
    private var steps: [(title: String, detail: String)] {
        [
            (NSLocalizedString("Welcome", comment: "Onboarding step: welcome"),
             NSLocalizedString("Your books, on your device", comment: "Onboarding step: welcome detail")),
            (NSLocalizedString("Bring your books", comment: "Onboarding: import title"),
             NSLocalizedString("Files, AirDrop, series", comment: "Onboarding step: import detail")),
            (NSLocalizedString("Make it yours", comment: "Onboarding: appearance title"),
             NSLocalizedString("Theme, accent, icon", comment: "Onboarding step: appearance detail")),
            (NSLocalizedString("How you listen", comment: "Onboarding: playback title"),
             NSLocalizedString("Skips, smart rewind", comment: "Onboarding step: playback detail")),
            (NSLocalizedString("Connect, if you like", comment: "Onboarding: integrations title"),
             NSLocalizedString("iCloud, AudiobookShelf, Hardcover", comment: "Onboarding step: integrations detail")),
            (NSLocalizedString("You're set", comment: "Onboarding: ready title"),
             NSLocalizedString("What's worth knowing", comment: "Onboarding step: ready detail")),
        ]
    }

    var foldSteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if page == 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "headphones")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.background)
                            .frame(width: 36, height: 36)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        Text(OnboardingWelcomePage.appName).font(.system(size: 17, weight: .bold))
                    }
                } else {
                    Button {
                        withHapticFeedback { withAnimation { page -= 1 } }
                    } label: {
                        Label(NSLocalizedString("Back", comment: "Onboarding: previous step button"),
                              systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.primary)
                }
                Spacer()
                if page < pageCount - 1 {
                    Button(NSLocalizedString("Skip", comment: "Onboarding: skip button")) {
                        withHapticFeedback { onFinish() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.glass)
                    .foregroundStyle(.primary)
                }
            }
            .frame(minHeight: 44)

            Spacer(minLength: 0)
            // Large text no longer fits the six rows: they scroll rather than clip.
            ViewThatFits(in: .vertical) {
                stepList
                ScrollView { stepList }
            }
            Spacer(minLength: 0)

            Text(NSLocalizedString("Everything can change later in Settings.", comment: "Onboarding: steps footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 26)
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: NSLocalizedString("Getting Started · %1$d of %2$d", comment: "Onboarding: steps header, current step and count"),
                        page + 1, pageCount))
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            ForEach(steps.indices, id: \.self) { index in
                Button {
                    withHapticFeedback { withAnimation { page = index } }
                } label: {
                    OnboardingStepRow(number: index + 1, title: steps[index].title, detail: steps[index].detail,
                                      isDone: index < page, isCurrent: index == page)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == page ? .isSelected : [])
            }
        }
    }
}

/// One step of the list: its number (a check once passed), its name and what it covers.
private struct OnboardingStepRow: View {
    let number: Int
    let title: String
    let detail: String
    let isDone: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if isDone {
                    Circle().fill(.tint.opacity(0.16))
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.tint)
                } else if isCurrent {
                    Circle().fill(.tint)
                    Text(number, format: .number).foregroundStyle(.background)
                } else {
                    Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1.5)
                    Text(number, format: .number).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isCurrent ? 1 : isDone ? 0.75 : 0.6))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(isCurrent ? 0.62 : 0.42))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.tint.opacity(0.1))
                    .strokeBorder(.tint.opacity(0.3), lineWidth: 0.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
