#if DEBUG
import SwiftData
import UIKit

// MARK: - App Store screenshots
//
// `--seed-showcase` fills the library with a shelf worth photographing: six books with
// generated covers, varied progress, a series, and a fortnight of listening sessions so the
// statistics screen has something to show. `scripts/screenshots.sh` drives it.
extension UITestBootstrap {
    private struct ShowcaseBook {
        let title: String
        let author: String
        let narrator: String
        let progress: Double
        let colors: (UIColor, UIColor)
        var series: (name: String, position: Double)? = nil
    }

    private static let showcase: [ShowcaseBook] = [
        .init(title: "The Final Empire", author: "Brandon Sanderson", narrator: "Michael Kramer", progress: 0.42,
              colors: (#colorLiteral(red: 0.55, green: 0.12, blue: 0.18, alpha: 1), #colorLiteral(red: 0.12, green: 0.08, blue: 0.14, alpha: 1)), series: ("Mistborn", 1)),
        .init(title: "The Well of Ascension", author: "Brandon Sanderson", narrator: "Michael Kramer", progress: 0,
              colors: (#colorLiteral(red: 0.16, green: 0.32, blue: 0.55, alpha: 1), #colorLiteral(red: 0.06, green: 0.1, blue: 0.2, alpha: 1)), series: ("Mistborn", 2)),
        .init(title: "The Hero of Ages", author: "Brandon Sanderson", narrator: "Michael Kramer", progress: 0,
              colors: (#colorLiteral(red: 0.75, green: 0.55, blue: 0.2, alpha: 1), #colorLiteral(red: 0.3, green: 0.18, blue: 0.05, alpha: 1)), series: ("Mistborn", 3)),
        .init(title: "Project Hail Mary", author: "Andy Weir", narrator: "Ray Porter", progress: 0.78,
              colors: (#colorLiteral(red: 0.95, green: 0.6, blue: 0.15, alpha: 1), #colorLiteral(red: 0.1, green: 0.12, blue: 0.25, alpha: 1))),
        .init(title: "Piranesi", author: "Susanna Clarke", narrator: "Chiwetel Ejiofor", progress: 0.15,
              colors: (#colorLiteral(red: 0.2, green: 0.5, blue: 0.45, alpha: 1), #colorLiteral(red: 0.05, green: 0.15, blue: 0.15, alpha: 1))),
        .init(title: "The Name of the Wind", author: "Patrick Rothfuss", narrator: "Nick Podehl", progress: 1,
              colors: (#colorLiteral(red: 0.35, green: 0.25, blue: 0.5, alpha: 1), #colorLiteral(red: 0.1, green: 0.06, blue: 0.15, alpha: 1))),
    ]

    static func seedShowcase(context: ModelContext) throws {
        for session in try context.fetch(FetchDescriptor<ListeningSessionModel>()) { context.delete(session) }

        // One real hour of silence, so the player shows an audiobook-shaped timeline rather
        // than the 30-second fixture the functional suites use.
        let directory = AudiobookModel.libraryFolderURL.appendingPathComponent("UITestFixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("showcase.wav")
        if !FileManager.default.fileExists(atPath: audioURL.path) { try writeSilentWave(to: audioURL, seconds: 3600) }

        let french = Locale.current.language.languageCode == "fr"
        let now = Date()
        for (index, entry) in showcase.enumerated() {
            let book = AudiobookModel(
                title: entry.title,
                author: entry.author,
                narrator: entry.narrator,
                fileURL: AudiobookModel.storedPath(for: audioURL),
                duration: 3600,
                currentPosition: 3600 * entry.progress,
                isFinished: entry.progress >= 1,
                coverImageData: cover(title: entry.title, author: entry.author, colors: entry.colors),
                dateAdded: now.addingTimeInterval(Double(-index) * 86_400 * 3),
                lastPlayed: entry.progress > 0 ? now.addingTimeInterval(Double(-index) * 3_600 * 5) : .distantPast
            )
            book.hardcover = HardcoverLink(
                id: index + 1, title: entry.title, author: entry.author,
                seriesID: entry.series == nil ? nil : 42, seriesName: entry.series?.name,
                seriesPosition: entry.series?.position, seriesChecked: true,
                summary: french
                    ? "Une histoire qui vaut chaque heure. Chapitres, signets et votre progression restent synchronisés entre iPhone, Apple Watch et CarPlay."
                    : "A story worth every hour. Chapters, bookmarks and your place in it stay in sync across iPhone, Apple Watch and CarPlay.",
                genres: ["Fantasy", "Adventure"], detailsChecked: true
            )
            for chapter in 1...12 {
                let model = ChapterModel(title: "\(french ? "Chapitre" : "Chapter") \(chapter)", chapterNumber: Int16(chapter), startTime: Double(chapter - 1) * 300, endTime: Double(chapter) * 300)
                model.audiobook = book
                context.insert(model)
            }
            context.insert(book)

            // A fortnight of listening, heavier on the books in progress.
            guard entry.progress > 0 else { continue }
            for day in 0..<14 where (day + index) % 3 != 0 {
                let started = Calendar.current.date(byAdding: .day, value: -day, to: now)!.addingTimeInterval(-3_600 * 2)
                context.insert(ListeningSessionModel(book: book, startedAt: started, seconds: Double(35 + (day * 7 + index * 11) % 50) * 60,
                                                     finishedBook: day == 2 && entry.progress >= 1))
            }
        }
        try context.save()
    }

    /// A flat two-tone cover with the title on it. Real covers are copyrighted; these are not.
    private static func cover(title: String, author: String, colors: (UIColor, UIColor)) -> Data? {
        let size = CGSize(width: 600, height: 900)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            let gradient = CGGradient(colorsSpace: nil, colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph
            ]
            let authorAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: UIColor.white.withAlphaComponent(0.8), .paragraphStyle: paragraph
            ]
            (title as NSString).draw(in: CGRect(x: 50, y: 300, width: 500, height: 320), withAttributes: titleAttributes)
            (author as NSString).draw(in: CGRect(x: 50, y: 760, width: 500, height: 60), withAttributes: authorAttributes)
        }
    }
}
#endif
