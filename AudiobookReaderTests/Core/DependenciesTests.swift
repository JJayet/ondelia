//
//  DependenciesTests.swift
//  AudiobookReaderTests
//
//  Created by AudiobookReader Testing Infrastructure
//

import Testing
import SwiftUI
@testable import AudiobookReader

struct DependenciesTests {
    
    // MARK: - Live Dependencies Tests
    
    @Test("Live dependencies should be properly initialized")
    func liveDependenciesInitialization() async throws {
        let dependencies = LiveDependencies()
        
        #expect(dependencies.audioManager is GlobalAudioManager)
        #expect(dependencies.themeManager is ThemeManager)
        #expect(dependencies.audiobookManager is AudiobookManager)
        #expect(dependencies.persistenceController === PersistenceController.shared)
        
        let statistics = dependencies.createReadingStatistics()
        #expect(statistics is ReadingStatistics)
    }
    
    @Test("Live dependencies should provide singleton instances where appropriate")
    func liveDependenciesSingletons() async throws {
        let dependencies1 = LiveDependencies()
        let dependencies2 = LiveDependencies()
        
        // These should be the same shared instances
        #expect(dependencies1.persistenceController === dependencies2.persistenceController)
    }
    
    // MARK: - Preview Dependencies Tests
    
    @Test("Preview dependencies should be properly initialized")
    func previewDependenciesInitialization() async throws {
        let dependencies = PreviewDependencies()
        
        #expect(dependencies.audioManager is MockGlobalAudioManager)
        #expect(dependencies.themeManager is MockThemeManager)
        #expect(dependencies.audiobookManager is MockAudiobookManager)
        #expect(dependencies.persistenceController === PersistenceController.preview)
        
        let statistics = dependencies.createReadingStatistics()
        #expect(statistics is MockReadingStatistics)
    }
    
    @Test("Preview dependencies should provide separate instances")
    func previewDependenciesSeparation() async throws {
        let dependencies1 = PreviewDependencies()
        let dependencies2 = PreviewDependencies()
        
        // These should be the same preview instance
        #expect(dependencies1.persistenceController === dependencies2.persistenceController)
        
        // But audio managers should be separate instances for isolated testing
        #expect(dependencies1.audioManager !== dependencies2.audioManager)
    }
    
    // MARK: - Mock Dependency Injection Tests
    
    @Test("Mock dependencies should fulfill protocol requirements")
    func mockDependencyProtocolCompliance() async throws {
        let dependencies = PreviewDependencies()
        
        // Test AudioManagerProtocol compliance
        let audioManager = dependencies.audioManager
        #expect(audioManager.playbackState == .stopped)
        #expect(audioManager.showMiniPlayer == false)
        #expect(audioManager.currentAudiobook == nil)
        #expect(audioManager.isLoading == false)
        #expect(audioManager.isReady == true)
        
        // Test ThemeManagerProtocol compliance
        let themeManager = dependencies.themeManager
        #expect(themeManager.currentTheme == .system)
        #expect(themeManager.accentColor == .blue)
        #expect(themeManager.skipInterval == .fifteen)
        
        // Test ReadingStatisticsProtocol compliance
        let statistics = dependencies.createReadingStatistics()
        #expect(statistics.totalListeningTime > 0)
        #expect(statistics.booksCompleted > 0)
        #expect(statistics.currentStreak > 0)
        #expect(statistics.averageSpeed > 0)
    }
    
    // MARK: - Environment Detection Tests
    
    @Test("Environment detection should work correctly")
    func environmentDetection() async throws {
        // Test preview detection (this will be false in test environment)
        #expect(ProcessInfo.isPreview == false)
        
        // Test running in test environment
        #expect(ProcessInfo.isRunningTests == true)
    }
    
    @Test("Default environment values should be correctly set")
    func defaultEnvironmentValues() async throws {
        // Create a test environment
        struct TestEnvironmentView: View {
            @Environment(\.dependencies) var dependencies
            
            var body: some View {
                Text("Test")
            }
        }
        
        let view = await MainActor.run { TestEnvironmentView() }
        
        // In test environment, should get live dependencies by default
        // (since ProcessInfo.isPreview is false in tests)
        #expect(view.dependencies is LiveDependencies)
    }
    
    // MARK: - Mock Data Generation Tests
    
    @Test("Mock data should be generated correctly")
    func mockDataGeneration() async throws {
        let dependencies = PreviewDependencies()
        let mockAudioManager = dependencies.audioManager as! MockGlobalAudioManager
        
        // Test mock time values
        #expect(mockAudioManager.getCurrentTime() == 450.0) // 7:30
        #expect(mockAudioManager.getDuration() == 3600.0) // 1 hour
        #expect(mockAudioManager.getPlaybackRate() == 1.0)
        
        // Test mock statistics
        let mockStats = dependencies.createReadingStatistics() as! MockReadingStatistics
        #expect(mockStats.totalListeningTime > 100000) // Should have significant listening time
        #expect(mockStats.booksCompleted > 10)
        #expect(mockStats.currentStreak > 5)
        #expect(mockStats.averageSpeed > 1.0)
    }
    
    // MARK: - Mock Behavioral Tests
    
    @Test("Mock audio manager should respond to playback controls")
    func mockAudioManagerPlaybackControls() async throws {
        let dependencies = PreviewDependencies()
        let mockAudioManager = dependencies.audioManager as! MockGlobalAudioManager
        
        // Initial state
        #expect(mockAudioManager.playbackState == .stopped)
        #expect(mockAudioManager.isPlaying() == false)
        
        // Start playback
        mockAudioManager.startPlayback()
        #expect(mockAudioManager.playbackState == .playing)
        #expect(mockAudioManager.isPlaying() == true)
        
        // Pause playback
        mockAudioManager.pausePlayback()
        #expect(mockAudioManager.playbackState == .paused)
        #expect(mockAudioManager.isPlaying() == false)
        
        // Resume playback
        mockAudioManager.resumePlayback()
        #expect(mockAudioManager.playbackState == .playing)
        #expect(mockAudioManager.isPlaying() == true)
        
        // Stop playback
        mockAudioManager.stopPlayback()
        #expect(mockAudioManager.playbackState == .stopped)
        #expect(mockAudioManager.isPlaying() == false)
        #expect(mockAudioManager.showMiniPlayer == false)
    }
    
    @Test("Mock audio manager should handle seek operations")
    func mockAudioManagerSeekOperations() async throws {
        let dependencies = PreviewDependencies()
        let mockAudioManager = dependencies.audioManager as! MockGlobalAudioManager
        
        let initialTime = mockAudioManager.getCurrentTime()
        let duration = mockAudioManager.getDuration()
        
        // Skip forward
        mockAudioManager.skipForward(30)
        #expect(mockAudioManager.getCurrentTime() == initialTime + 30)
        
        // Skip backward
        mockAudioManager.skipBackward(15)
        #expect(mockAudioManager.getCurrentTime() == initialTime + 15)
        
        // Seek to specific time
        mockAudioManager.seek(to: 1000)
        #expect(mockAudioManager.getCurrentTime() == 1000)
        
        // Test boundary conditions
        mockAudioManager.seek(to: -100) // Should clamp to 0
        #expect(mockAudioManager.getCurrentTime() == 0)
        
        mockAudioManager.seek(to: duration + 100) // Should clamp to duration
        #expect(mockAudioManager.getCurrentTime() == duration)
    }
    
    @Test("Mock theme manager should handle theme changes")
    func mockThemeManagerThemeChanges() async throws {
        let dependencies = PreviewDependencies()
        let mockThemeManager = dependencies.themeManager as! MockThemeManager
        
        // Initial state
        #expect(mockThemeManager.currentTheme == .system)
        #expect(mockThemeManager.accentColor == .blue)
        #expect(mockThemeManager.skipInterval == .fifteen)
        
        // Change theme
        mockThemeManager.setTheme(.dark)
        #expect(mockThemeManager.currentTheme == .dark)
        
        // Change accent color
        mockThemeManager.setAccentColor(.red)
        #expect(mockThemeManager.accentColor == .red)
        
        // Change skip interval
        mockThemeManager.setSkipInterval(.thirty)
        #expect(mockThemeManager.skipInterval == .thirty)
    }
    
    @Test("Mock reading statistics should handle updates")
    func mockReadingStatisticsUpdates() async throws {
        let dependencies = PreviewDependencies()
        let mockStats = dependencies.createReadingStatistics() as! MockReadingStatistics
        
        let initialListeningTime = mockStats.totalListeningTime
        let initialBooksCompleted = mockStats.booksCompleted
        let initialStreak = mockStats.currentStreak
        
        // Add listening time
        mockStats.addListeningTime(600, playbackRate: 1.5) // 10 minutes at 1.5x speed
        #expect(mockStats.totalListeningTime == initialListeningTime + 600)
        
        // Mark book completed
        mockStats.markBookCompleted()
        #expect(mockStats.booksCompleted == initialBooksCompleted + 1)
        #expect(mockStats.currentStreak == initialStreak + 1)
        
        // Test average speed calculation
        let averageSpeed = mockStats.getAverageSpeed()
        #expect(averageSpeed > 1.0) // Should be influenced by 1.5x playback
    }
}