import SwiftUI

/// The year, month by month: which books took the hours. Books share the row in proportion.
struct YearlyMixCard: View {
    let stats: ListeningStats
    @State private var year = Calendar.current.component(.year, from: Date())

    var body: some View {
        let months = stats.monthlyMix(ofYear: year)
        let peak = months.map(\.total).max() ?? 0
        StatCard(symbol: "chart.bar", title: NSLocalizedString("Yearly Book Mix", comment: "Statistics card")) {
            Spacer()
            Stepper("", value: $year, in: 2000...Calendar.current.component(.year, from: Date()))
                .labelsHidden()
                .controlSize(.mini)
            Text(verbatim: "\(year)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
        } content: {
            if months.isEmpty {
                Text(NSLocalizedString("Nothing yet", comment: "Statistics: empty list"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(months) { month in
                HStack(spacing: 10) {
                    Text(month.month.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    row(month, peak: peak)
                    Text(month.total.hoursMinutesFormatted)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    /// Up to three books as tinted segments sized by their share of the month; the rest as +N.
    private func row(_ month: ListeningStats.MonthMix, peak: TimeInterval) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width * (peak > 0 ? month.total / peak : 0)
            let shown = month.books.prefix(3)
            let rest = month.books.count - shown.count
            HStack(spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, book in
                    Text(book.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(width: max(width * book.seconds / max(month.total, 1) - (rest > 0 ? 10 : 0), 8), height: 26)
                        .background(Color.accentColor.opacity(0.85 - 0.22 * Double(index)), in: Capsule())
                        .foregroundStyle(.black)
                }
                if rest > 0 {
                    Text(verbatim: "+\(rest)")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .frame(height: 26)
    }
}
