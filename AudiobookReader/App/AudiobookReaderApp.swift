//
//  AudiobookReaderApp.swift
//  AudiobookReader
//
//  Created by Jonathan Jayet on 14/08/2025.
//

import SwiftUI
import SwiftData
import WidgetKit

@main
struct AudiobookReaderApp: App {
    // Use StateObject for proper SwiftUI lifecycle management
    @StateObject private var swiftDataController = SwiftDataController.shared
    @StateObject private var globalAudioManager = GlobalAudioManager.shared
    @StateObject private var playbackCommandCoordinator = PlaybackCommandCoordinator()
    
    var body: some Scene {
        WindowGroup {
            // Show a loading view only during initial SwiftData loading
            if swiftDataController.isLoading {
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
            } else if let errorMessage = swiftDataController.loadErrorMessage {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Library Unavailable", comment: "SwiftData startup failure title"),
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                } description: {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Your library could not be opened. Your files have not been deleted.\n%@",
                                comment: "SwiftData startup failure description"
                            ),
                            errorMessage
                        )
                    )
                } actions: {
                    Button(NSLocalizedString("Try Again", comment: "Retry SwiftData startup button")) {
                        swiftDataController.retryInitialization()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if swiftDataController.isLoaded {
                // Main app content - loads immediately once SwiftData setup is complete
                MainTabView()
                    .modelContainer(swiftDataController.container)
                    .environment(\.theme, ThemeManager.shared)
                    .environmentObject(globalAudioManager)
                    .onAppear {
                        // Initialize widgets on app startup
                        WidgetCenter.shared.reloadAllTimelines()
                        playbackCommandCoordinator.consumePendingCommand()
                    }
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
            let audiobookManager = AudiobookManager.shared
            audiobookManager.updateProgress(for: audiobook, currentTime: currentTime)
            
            // Save SwiftData context
            swiftDataController.save()
        }
    }
    
    private func handleAppDidBecomeActive() {
        playbackCommandCoordinator.consumePendingCommand()
        // Refresh Now Playing info when app becomes active
        if globalAudioManager.isPlaying() {
            // Update now playing info to ensure it's current
            globalAudioManager.resumePlayback()
        }
    }
}
