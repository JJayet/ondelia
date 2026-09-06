//
//  IsoraWatchApp.swift
//  IsoraWatch Watch App
//
//  Created by Jonathan Jayet on 06/09/2026.
//

import SwiftData
import SwiftUI

@main
struct IsoraWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task { PhoneSyncService.shared.activate() }
                .onOpenURL(perform: handle)
        }
        .modelContainer(WatchLibraryStore.shared.container)
    }

    /// `isora://resume` comes from the complication: play whatever the watch can actually play.
    private func handle(_ url: URL) {
        guard url.scheme == "isora", url.host == "resume" else { return }
        Task { @MainActor in
            guard let book = mostRecentPlayableBook() else { return }
            await WatchAudioManager.shared.loadAndPlay(book)
        }
    }

    @MainActor
    private func mostRecentPlayableBook() -> AudiobookModel? {
        var descriptor = FetchDescriptor<AudiobookModel>(
            sortBy: [SortDescriptor(\.lastPlayed, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let books = (try? WatchLibraryStore.shared.context.fetch(descriptor)) ?? []
        return books.first { !WatchLibraryDisk.chaptersOnDisk(bookID: $0.id).isEmpty }
    }
}
