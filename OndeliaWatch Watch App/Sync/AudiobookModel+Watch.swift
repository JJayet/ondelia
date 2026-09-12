import Foundation

/// Small read-only helpers the watch screens need. Watch target only.
extension AudiobookModel {
    func chapter(at time: TimeInterval) -> ChapterModel? {
        let chapters = sortedChapters
        return chapters.first { time >= $0.startTime && time < $0.endTime } ?? chapters.last
    }

    /// The chapter the saved position sits in — what "play" and "download" act on.
    var currentChapterNumber: Int? {
        chapter(at: currentPosition).map { Int($0.chapterNumber) }
    }

    var displayTitle: String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AudiobookModel.unknownTitle : trimmed
    }
}

extension Int64 {
    /// `42 MB`, `1.2 GB`. Every size the watch shows is a real file size.
    var fileSizeFormatted: String {
        formatted(.byteCount(style: .file))
    }
}

/// The sleep-timer choices, shared by the manager and its picker.
enum SleepTimerOption: Equatable, Hashable, Identifiable {
    case off
    case minutes(Int)
    case endOfChapter

    static let all: [SleepTimerOption] = [.off, .minutes(10), .minutes(15), .minutes(25), .minutes(45), .endOfChapter]

    var id: String {
        switch self {
        case .off: "off"
        case .minutes(let minutes): "m\(minutes)"
        case .endOfChapter: "chapter"
        }
    }

    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .minutes(let minutes): "\(minutes) min"
        case .endOfChapter: String(localized: "End of chapter")
        }
    }

    var isActive: Bool { self != .off }
}
