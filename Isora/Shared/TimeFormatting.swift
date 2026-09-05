import Foundation

extension TimeInterval {
    /// `1:02:03`, or `2:03` under an hour. The transport clock: player, chapters, bookmarks.
    var clockFormatted: String {
        let duration = Duration.seconds(max(self, 0))
        return duration >= .seconds(3600)
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }

    /// `2h 5m`, `2h`, or `5m`. The coarse form used for totals and library rows.
    var hoursMinutesFormatted: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
        }
    }
}
