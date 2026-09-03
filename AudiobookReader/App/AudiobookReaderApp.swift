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
    private let swiftDataController = SwiftDataController.shared
    private let globalAudioManager = GlobalAudioManager.shared
    @State private var playbackCommandCoordinator = PlaybackCommandCoordinator()
    
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
                        .foregroundStyle(.secondary)
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
        // Save current playback position when app goes to background. The manager owns the same
        // write on a timer, so this only shortens the window, and it shares the guard that keeps
        // a still-loading book from saving a position of zero.
        globalAudioManager.persistProgress()
        swiftDataController.save()
    }
    
    private func handleAppDidBecomeActive() {
        playbackCommandCoordinator.consumePendingCommand()
        // Files can be handed over while the app is in the background.
        AudiobookManager.shared.importInboxFiles()
        // Refresh Now Playing info when app becomes active
        if globalAudioManager.isPlaying() {
            // Update now playing info to ensure it's current
            globalAudioManager.resumePlayback()
        }
    }
}
