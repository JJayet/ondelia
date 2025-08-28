//
//  AudiobookReaderApp.swift
//  AudiobookReader
//
//  Created by Jonathan Jayet on 14/08/2025.
//

import SwiftUI

@main
struct AudiobookReaderApp: App {
    // Use StateObject for proper SwiftUI lifecycle management
    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var globalAudioManager = GlobalAudioManager.shared
    
    var body: some Scene {
        WindowGroup {
            // Show a loading view until Core Data is ready
            if persistenceController.isLoaded {
                MainTabView()
                    .environment(\.managedObjectContext, persistenceController.context)
                    .environment(\.theme, ThemeManager.shared)
                    .environmentObject(globalAudioManager)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        handleAppWillResignActive()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        handleAppDidBecomeActive()
                    }
            } else {
                // Simple loading view while Core Data initializes
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .padding()
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    // Trigger lazy loading of Core Data
                    let _ = persistenceController.context
                }
            }
        }
    }
    
    private func handleAppWillResignActive() {
        // Save current playback position when app goes to background
        if let audiobook = globalAudioManager.currentAudiobook {
            let currentTime = globalAudioManager.getCurrentTime()
            let audiobookManager = AudiobookManager()
            audiobookManager.updateProgress(for: audiobook, currentTime: currentTime)
            
            // Save Core Data context
            try? persistenceController.context.save()
        }
    }
    
    private func handleAppDidBecomeActive() {
        // Refresh Now Playing info when app becomes active
        if globalAudioManager.isPlaying() {
            // Update now playing info to ensure it's current
            globalAudioManager.resumePlayback()
        }
    }
}
