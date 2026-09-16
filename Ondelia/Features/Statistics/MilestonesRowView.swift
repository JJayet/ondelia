import SwiftUI

/// The badges, in a row: lit when earned, progress count when not.
struct MilestonesRowView: View {
    let statistics: ReadingStatistics
    let stats: ListeningStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                SectionLabel(NSLocalizedString("Milestones", comment: "Statistics: badges row"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Milestone.all) { milestone in
                        badge(milestone, progress: statistics.progress(of: milestone, in: stats))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(18)
        .glassCard()
    }

    private func badge(_ milestone: Milestone, progress: Int) -> some View {
        let unlocked = progress >= milestone.target
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.4)))
                Circle()
                    .strokeBorder(unlocked ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), lineWidth: 1.5)
                if unlocked {
                    Image(systemName: milestone.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.tint)
                } else {
                    Text(verbatim: "\(min(progress, milestone.target))/\(milestone.target)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 66, height: 66)
            Text(milestone.title)
                .font(.system(size: 11.5, weight: unlocked ? .semibold : .regular))
                .foregroundStyle(unlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .frame(width: 78)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            unlocked
                ? String(format: NSLocalizedString("%@, earned", comment: "Milestone accessibility: unlocked"), milestone.title)
                : String(format: NSLocalizedString("%@, %d of %d", comment: "Milestone accessibility: progress"), milestone.title, progress, milestone.target)
        )
    }
}

/// Slides in from the top when a badge is earned, and leaves on its own.
struct MilestoneToast: View {
    let milestone: Milestone
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: milestone.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(NSLocalizedString("Milestone earned", comment: "Toast title"))
                Text(milestone.title).font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 22)
        .padding(.horizontal, 16)
        .onTapGesture(perform: dismiss)
        .task {
            try? await Task.sleep(for: .seconds(4))
            dismiss()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .sensoryFeedback(.success, trigger: milestone)
    }
}
