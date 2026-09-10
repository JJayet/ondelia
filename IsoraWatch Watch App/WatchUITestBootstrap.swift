#if DEBUG
import SwiftData
import SwiftUI

/// `--uitesting --seed-showcase`: three books for the App Store screenshots, two of them with
/// audio "on the watch". Nothing here runs in a normal launch.
@MainActor
enum WatchUITestBootstrap {
    static func prepareIfRequested(context: ModelContext) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--seed-showcase") else { return }

        for book in try context.fetch(FetchDescriptor<AudiobookModel>()) { context.delete(book) }
        try context.save()
        WatchLibraryDisk.deleteEverything()

        let french = Locale.current.language.languageCode == "fr"
        let books: [(String, String, Double, Color, Color, Bool)] = [
            ("The Final Empire", "Brandon Sanderson", 0.42, Color(red: 0.55, green: 0.12, blue: 0.18), Color(red: 0.12, green: 0.08, blue: 0.14), false),
            ("Project Hail Mary", "Andy Weir", 0.78, Color(red: 0.95, green: 0.6, blue: 0.15), Color(red: 0.1, green: 0.12, blue: 0.25), true),
            ("Piranesi", "Susanna Clarke", 0.15, Color(red: 0.2, green: 0.5, blue: 0.45), Color(red: 0.05, green: 0.15, blue: 0.15), true)
        ]
        for (index, (title, author, progress, top, bottom, onWatch)) in books.enumerated() {
            let book = AudiobookModel(
                title: title,
                author: author,
                duration: 3600,
                currentPosition: 3600 * progress,
                coverImageData: cover(title: title, top: top, bottom: bottom),
                lastPlayed: Date().addingTimeInterval(Double(-index) * 3600 * 5)
            )
            book.fileURL = book.id.uuidString
            for number in 1...12 {
                let chapter = ChapterModel(
                    title: "\(french ? "Chapitre" : "Chapter") \(number)",
                    chapterNumber: Int16(number),
                    startTime: Double(number - 1) * 300,
                    endTime: Double(number) * 300
                )
                chapter.audiobook = book
                context.insert(chapter)
            }
            context.insert(book)
            // The row reads "on the watch" from the files on disk; their content never plays here.
            if onWatch {
                let folder = WatchLibraryDisk.bookFolder(book.id)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for number in 1...4 {
                    try Data(count: 2_400_000).write(to: WatchLibraryDisk.chapterURL(bookID: book.id, number: number))
                }
            }
        }
        try context.save()
    }

    private static func cover(title: String, top: Color, bottom: Color) -> Data? {
        let renderer = ImageRenderer(content:
            ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
            .frame(width: 200, height: 200)
        )
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}
#endif
