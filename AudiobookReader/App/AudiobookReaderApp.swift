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
            // Show a loading view only during initial Core Data loading
            if persistenceController.isLoading {
                // Optimized loading view that doesn't block
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle())
                    Text(NSLocalizedString("Starting up...", comment: "App startup loading message"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                // Main app content - loads immediately once Core Data setup is complete
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
