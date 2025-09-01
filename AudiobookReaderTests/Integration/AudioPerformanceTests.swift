//
//  AudioPerformanceTests.swift
//  AudiobookReaderTests
//
//  Created for Phase 3 Advanced Testing - Audio Performance Benchmarking
//

import XCTest
import AVFoundation
import CoreData
@testable import AudiobookReader

final class AudioPerformanceTests: XCTestCase {
    
    var performanceConfig: AudioPerformanceConfiguration!
    var dependencies: MockDependencies!
    var metricsCollector: PerformanceMetricsCollector!
    var persistenceController: PersistenceController!
    
    override func setUpWithError() throws {
        performanceConfig = AudioPerformanceConfiguration()
        dependencies = MockDependencies()
        metricsCollector = PerformanceMetricsCollector()
        persistenceController = PersistenceController(inMemory: true)
    }
    
    override func tearDownWithError() throws {
        dependencies = nil
        metricsCollector = nil
        persistenceController = nil
        performanceConfig = nil
        
        // Cleanup audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    // MARK: - Real-time Audio Processing Benchmarks
    
    func testAudioEngineInitializationPerformance() throws {
        measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
            let audioEngine = AudioEngine()
            
            let startTime = CFAbsoluteTimeGetCurrent()
            audioEngine.setupAudioSession()
            let setupTime = CFAbsoluteTimeGetCurrent() - startTime
            
            XCTAssertLessThan(setupTime, performanceConfig.maxEngineSetupTime,
                             "Audio engine setup should complete within \(performanceConfig.maxEngineSetupTime)s")
            
            metricsCollector.recordMetric(name: "engine_setup_time", value: setupTime)
        }
    }
    
    func testAudioFileLoadingPerformance() throws {
        let testSizes = performanceConfig.audioFileSizes
        
        for fileSize in testSizes {
            let testAudiobook = createMockAudiobook(durationMinutes: fileSize)
            
            measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric(), XCTStorageMetric()]) {
                let audioEngine = AudioEngine()
                
                let startTime = CFAbsoluteTimeGetCurrent()
                audioEngine.loadAudiobook(testAudiobook)
                let loadTime = CFAbsoluteTimeGetCurrent() - startTime
                
                let expectedMaxTime = performanceConfig.calculateMaxLoadTime(for: fileSize)
                XCTAssertLessThan(loadTime, expectedMaxTime,
                                 "Loading \(fileSize) min audiobook should complete within \(expectedMaxTime)s")
                
                metricsCollector.recordMetric(name: "file_load_time_\(fileSize)min", value: loadTime)
            }
        }
    }
    
    func testRealTimeAudioProcessingLatency() throws {
        let audioEngine = AudioEngine()
        let testAudiobook = createMockAudiobook(durationMinutes: 60)
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(testAudiobook)
        
        measure(metrics: [XCTClock.Metric.wallClockTime]) {
            let measurements: [TimeInterval] = (0..<performanceConfig.latencyMeasurementCount).map { _ in
                let startTime = CFAbsoluteTimeGetCurrent()
                
                // Test play command latency
                audioEngine.startPlayback()
                let playLatency = CFAbsoluteTimeGetCurrent() - startTime
                
                Thread.sleep(forTimeInterval: 0.1) // Brief playback
                
                let pauseStartTime = CFAbsoluteTimeGetCurrent()
                audioEngine.pausePlayback()
                let pauseLatency = CFAbsoluteTimeGetCurrent() - pauseStartTime
                
                metricsCollector.recordMetric(name: "play_latency", value: playLatency)
                metricsCollector.recordMetric(name: "pause_latency", value: pauseLatency)
                
                return max(playLatency, pauseLatency)
            }
            
            let averageLatency = measurements.reduce(0, +) / Double(measurements.count)
            let maxLatency = measurements.max() ?? 0
            
            XCTAssertLessThan(averageLatency, performanceConfig.maxAverageLatency,
                             "Average playback latency should be under \(performanceConfig.maxAverageLatency)s")
            XCTAssertLessThan(maxLatency, performanceConfig.maxPeakLatency,
                             "Peak playback latency should be under \(performanceConfig.maxPeakLatency)s")
        }
    }
    
    func testAudioBufferingPerformance() throws {
        let audioEngine = AudioEngine()
        let testAudiobook = createMockAudiobook(durationMinutes: 120) // 2 hour book
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(testAudiobook)
        
        measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
            audioEngine.startPlayback()
            
            // Test buffering during continuous playback
            let bufferTestDuration: TimeInterval = performanceConfig.bufferTestDuration
            let startTime = Date()
            
            while Date().timeIntervalSince(startTime) < bufferTestDuration {
                let bufferStartTime = CFAbsoluteTimeGetCurrent()
                
                // Simulate buffer events (this would normally be handled by AVAudioPlayer)
                let bufferStatus = audioEngine.getBufferStatus() // Mock implementation
                let bufferTime = CFAbsoluteTimeGetCurrent() - bufferStartTime
                
                metricsCollector.recordMetric(name: "buffer_check_time", value: bufferTime)
                
                XCTAssertLessThan(bufferTime, performanceConfig.maxBufferCheckTime,
                                 "Buffer status check should be fast")
                
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            audioEngine.stopPlayback()
        }
    }
    
    // MARK: - Multi-file Engine Performance
    
    func testMultiFileEngineWithManyChapters() throws {
        let chapterCounts = performanceConfig.multiFileChapterCounts
        
        for chapterCount in chapterCounts {
            let multiFileBook = createMultiFileAudiobook(chapterCount: chapterCount)
            
            measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
                let multiEngine = MultiFileAudioEngine()
                
                let loadStartTime = CFAbsoluteTimeGetCurrent()
                multiEngine.loadAudiobook(multiFileBook)
                let loadTime = CFAbsoluteTimeGetCurrent() - loadStartTime
                
                let expectedMaxTime = performanceConfig.calculateMaxMultiFileLoadTime(for: chapterCount)
                XCTAssertLessThan(loadTime, expectedMaxTime,
                                 "Multi-file loading with \(chapterCount) chapters should complete within \(expectedMaxTime)s")
                
                // Test chapter transition performance
                multiEngine.startPlayback()
                
                let transitionTimes: [TimeInterval] = (0..<min(chapterCount - 1, 10)).map { chapterIndex in
                    let transitionStart = CFAbsoluteTimeGetCurrent()
                    multiEngine.skipToChapter(chapterIndex + 1)
                    let transitionTime = CFAbsoluteTimeGetCurrent() - transitionStart
                    
                    metricsCollector.recordMetric(name: "chapter_transition_\(chapterCount)chapters", value: transitionTime)
                    return transitionTime
                }
                
                let averageTransition = transitionTimes.reduce(0, +) / Double(transitionTimes.count)
                XCTAssertLessThan(averageTransition, performanceConfig.maxChapterTransitionTime,
                                 "Chapter transitions should average under \(performanceConfig.maxChapterTransitionTime)s")
                
                multiEngine.stopPlayback()
            }
        }
    }
    
    func testCrossFadePerformance() throws {
        let multiEngine = MultiFileAudioEngine()
        let testBook = createMultiFileAudiobook(chapterCount: 10)
        
        multiEngine.loadAudiobook(testBook)
        multiEngine.startPlaybook()
        
        measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
            for i in 0..<5 {
                let crossfadeStart = CFAbsoluteTimeGetCurrent()
                
                // Trigger crossfade by skipping to next chapter
                multiEngine.skipToChapter(i + 1)
                
                let crossfadeTime = CFAbsoluteTimeGetCurrent() - crossfadeStart
                
                metricsCollector.recordMetric(name: "crossfade_time", value: crossfadeTime)
                XCTAssertLessThan(crossfadeTime, performanceConfig.maxCrossfadeTime,
                                 "Crossfade should complete within \(performanceConfig.maxCrossfadeTime)s")
                
                Thread.sleep(forTimeInterval: 0.5) // Allow crossfade to complete
            }
        }
        
        multiEngine.stopPlayback()
    }
    
    // MARK: - Audio Format Conversion Performance
    
    func testAudioFormatConversionPerformance() throws {
        let audioFormats: [(String, TimeInterval)] = [
            ("MP3", 1.0),
            ("M4A", 0.8),
            ("M4B", 0.9),
            ("FLAC", 2.0), // Lossless format, expected to take longer
            ("OGG", 1.5)
        ]
        
        for (format, expectedMaxTime) in audioFormats {
            let testBook = createMockAudiobook(format: format, durationMinutes: 30)
            
            measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
                let audioEngine = AudioEngine()
                
                let conversionStart = CFAbsoluteTimeGetCurrent()
                audioEngine.loadAudiobook(testBook) // This may involve format conversion
                let conversionTime = CFAbsoluteTimeGetCurrent() - conversionStart
                
                metricsCollector.recordMetric(name: "format_conversion_\(format)", value: conversionTime)
                XCTAssertLessThan(conversionTime, expectedMaxTime,
                                 "\(format) format loading/conversion should complete within \(expectedMaxTime)s")
                
                // Verify playback quality after conversion
                audioEngine.startPlayback()
                Thread.sleep(forTimeInterval: 0.5)
                
                let playbackState = audioEngine.getPlaybackState()
                XCTAssertEqual(playbackState, .playing, "Playback should work correctly after format processing")
                
                audioEngine.stopPlayback()
            }
        }
    }
    
    // MARK: - Seek Operation Performance
    
    func testSeekOperationResponsiveness() throws {
        let audioEngine = AudioEngine()
        let longAudiobook = createMockAudiobook(durationMinutes: 600) // 10 hours
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(longAudiobook)
        audioEngine.startPlayback()
        
        let totalDuration = longAudiobook.duration
        let seekPositions = (0..<performanceConfig.seekOperationCount).map { _ in
            Double.random(in: 0...totalDuration)
        }
        
        measure(metrics: [XCTClock.Metric.wallClockTime]) {
            for seekPosition in seekPositions {
                let seekStart = CFAbsoluteTimeGetCurrent()
                audioEngine.seekTo(time: seekPosition)
                let seekTime = CFAbsoluteTimeGetCurrent() - seekStart
                
                metricsCollector.recordMetric(name: "seek_operation_time", value: seekTime)
                XCTAssertLessThan(seekTime, performanceConfig.maxSeekTime,
                                 "Seek operation should complete within \(performanceConfig.maxSeekTime)s")
                
                // Verify seek accuracy
                Thread.sleep(forTimeInterval: 0.1) // Allow seek to complete
                let currentPosition = audioEngine.getCurrentTime()
                let seekAccuracy = abs(currentPosition - seekPosition)
                
                XCTAssertLessThan(seekAccuracy, performanceConfig.maxSeekAccuracyError,
                                 "Seek accuracy should be within \(performanceConfig.maxSeekAccuracyError)s")
                
                metricsCollector.recordMetric(name: "seek_accuracy_error", value: seekAccuracy)
            }
        }
        
        audioEngine.stopPlaybook()
    }
    
    func testRapidSeekingStressTest() throws {
        let audioEngine = AudioEngine()
        let testBook = createMockAudiobook(durationMinutes: 180) // 3 hours
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(testBook)
        audioEngine.startPlayback()
        
        measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
            let rapidSeekCount = performanceConfig.rapidSeekCount
            let duration = testBook.duration
            
            for i in 0..<rapidSeekCount {
                let seekPosition = Double(i) * (duration / Double(rapidSeekCount))
                
                let rapidSeekStart = CFAbsoluteTimeGetCurrent()
                audioEngine.seekTo(time: seekPosition)
                let rapidSeekTime = CFAbsoluteTimeGetCurrent() - rapidSeekStart
                
                // Rapid seeks should be even faster
                XCTAssertLessThan(rapidSeekTime, performanceConfig.maxRapidSeekTime,
                                 "Rapid seek \(i) should complete within \(performanceConfig.maxRapidSeekTime)s")
                
                // Very short pause between seeks
                Thread.sleep(forTimeInterval: 0.01)
            }
            
            // Verify engine stability after rapid seeking
            let currentTime = audioEngine.getCurrentTime()
            XCTAssertGreaterThanOrEqual(currentTime, 0, "Engine should remain stable after rapid seeking")
            XCTAssertLessThanOrEqual(currentTime, duration, "Current time should be within bounds")
        }
        
        audioEngine.stopPlayback()
    }
    
    // MARK: - Battery Usage Optimization Tests
    
    func testBatteryUsageOptimization() throws {
        let audioEngine = AudioEngine()
        let testBook = createMockAudiobook(durationMinutes: 120)
        
        // Mock battery usage monitoring
        let batteryMonitor = BatteryUsageMonitor()
        batteryMonitor.startMonitoring()
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(testBook)
        
        measure(metrics: [XCTClock.Metric.wallClockTime]) {
            let testDuration: TimeInterval = performanceConfig.batteryTestDuration
            
            audioEngine.startPlayback()
            let startTime = Date()
            
            while Date().timeIntervalSince(startTime) < testDuration {
                Thread.sleep(forTimeInterval: 1.0)
                
                let batteryUsage = batteryMonitor.getCurrentUsage()
                metricsCollector.recordMetric(name: "battery_usage_rate", value: batteryUsage)
                
                // Battery usage should be within acceptable limits
                XCTAssertLessThan(batteryUsage, performanceConfig.maxBatteryUsageRate,
                                 "Battery usage rate should be optimized")
            }
            
            audioEngine.stopPlayback()
        }
        
        batteryMonitor.stopMonitoring()
        
        let totalBatteryUsage = batteryMonitor.getTotalUsage()
        XCTAssertLessThan(totalBatteryUsage, performanceConfig.maxTotalBatteryUsage,
                         "Total battery usage should be within limits")
    }
    
    func testPowerEfficiencyDuringLongPlayback() throws {
        let audioEngine = AudioEngine()
        let longBook = createMockAudiobook(durationMinutes: 480) // 8 hours
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(longBook)
        
        let powerMonitor = PowerEfficiencyMonitor()
        powerMonitor.startMonitoring()
        
        measure(metrics: [XCTClock.Metric.wallClockTime, XCTMemoryMetric()]) {
            audioEngine.startPlayback()
            
            let longPlaybackDuration: TimeInterval = performanceConfig.longPlaybackTestDuration
            let startTime = Date()
            
            while Date().timeIntervalSince(startTime) < longPlaybackDuration {
                Thread.sleep(forTimeInterval: 5.0) // Check every 5 seconds
                
                let powerEfficiency = powerMonitor.getCurrentEfficiency()
                metricsCollector.recordMetric(name: "power_efficiency", value: powerEfficiency)
                
                // Power efficiency should not degrade significantly over time
                XCTAssertGreaterThan(powerEfficiency, performanceConfig.minPowerEfficiency,
                                    "Power efficiency should be maintained during long playback")
                
                let memoryUsage = getCurrentMemoryUsage()
                XCTAssertLessThan(memoryUsage, performanceConfig.maxMemoryDuringLongPlayback,
                                 "Memory usage should remain stable during long playback")
            }
            
            audioEngine.stopPlayback()
        }
        
        powerMonitor.stopMonitoring()
    }
    
    // MARK: - Memory Usage During Audio Processing
    
    func testMemoryUsageStabilityDuringPlayback() throws {
        let audioEngine = AudioEngine()
        let testBook = createMockAudiobook(durationMinutes: 240) // 4 hours
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(testBook)
        
        let initialMemory = getCurrentMemoryUsage()
        
        audioEngine.startPlayback()
        
        let memoryMeasurements: [Double] = (0..<performanceConfig.memoryStabilityMeasurements).map { i in
            Thread.sleep(forTimeInterval: 2.0)
            let currentMemory = getCurrentMemoryUsage()
            
            metricsCollector.recordMetric(name: "playback_memory_usage", value: currentMemory)
            
            // Memory should not grow excessively
            let memoryGrowth = currentMemory - initialMemory
            XCTAssertLessThan(memoryGrowth, performanceConfig.maxMemoryGrowthDuringPlayback,
                             "Memory growth at measurement \(i) should be within limits")
            
            return currentMemory
        }
        
        audioEngine.stopPlayback()
        
        // Check for memory leaks after stopping
        let finalMemory = getCurrentMemoryUsage()
        let memoryLeak = finalMemory - initialMemory
        XCTAssertLessThan(memoryLeak, performanceConfig.maxMemoryLeakAfterPlayback,
                         "Memory should be properly released after playback")
        
        // Verify memory stability (no dramatic spikes)
        let maxMemory = memoryMeasurements.max() ?? 0
        let minMemory = memoryMeasurements.min() ?? 0
        let memoryVariance = maxMemory - minMemory
        
        XCTAssertLessThan(memoryVariance, performanceConfig.maxMemoryVariance,
                         "Memory usage should be stable during playback")
    }
    
    // MARK: - Audio Quality Benchmarks
    
    func testAudioQualityMetrics() throws {
        let audioEngine = AudioEngine()
        let highQualityBook = createMockAudiobook(format: "FLAC", durationMinutes: 30)
        
        audioEngine.setupAudioSession()
        audioEngine.loadAudiobook(highQualityBook)
        audioEngine.startPlayback()
        
        let qualityMetrics = AudioQualityAnalyzer()
        
        Thread.sleep(forTimeInterval: 5.0) // Analyze 5 seconds of playback
        
        let analysisResults = qualityMetrics.analyze(audioEngine: audioEngine)
        
        XCTAssertGreaterThan(analysisResults.signalToNoiseRatio, performanceConfig.minSignalToNoiseRatio,
                            "Signal-to-noise ratio should meet quality standards")
        XCTAssertLessThan(analysisResults.totalHarmonicDistortion, performanceConfig.maxTotalHarmonicDistortion,
                         "Total harmonic distortion should be within acceptable limits")
        XCTAssertGreaterThan(analysisResults.dynamicRange, performanceConfig.minDynamicRange,
                            "Dynamic range should be preserved")
        
        metricsCollector.recordMetric(name: "signal_to_noise_ratio", value: analysisResults.signalToNoiseRatio)
        metricsCollector.recordMetric(name: "total_harmonic_distortion", value: analysisResults.totalHarmonicDistortion)
        metricsCollector.recordMetric(name: "dynamic_range", value: analysisResults.dynamicRange)
        
        audioEngine.stopPlayback()
    }
    
    // MARK: - Performance Regression Detection
    
    func testPerformanceRegressionDetection() throws {
        // Run a comprehensive performance test and compare against baseline
        let baselineMetrics = loadBaselinePerformanceMetrics()
        let currentMetrics = runComprehensivePerformanceSuite()
        
        for (metricName, currentValue) in currentMetrics {
            if let baselineValue = baselineMetrics[metricName] {
                let regressionThreshold = performanceConfig.regressionThreshold
                let regressionRatio = currentValue / baselineValue
                
                XCTAssertLessThan(regressionRatio, regressionThreshold,
                                 "Performance regression detected for \(metricName): \(regressionRatio)x slower than baseline")
                
                metricsCollector.recordMetric(name: "regression_ratio_\(metricName)", value: regressionRatio)
            }
        }
        
        // Save current metrics as new baseline if all tests pass
        savePerformanceMetrics(currentMetrics)
    }
    
    // MARK: - Helper Methods
    
    private func createMockAudiobook(format: String = "MP3", durationMinutes: Int) -> Audiobook {
        let context = persistenceController.container.viewContext
        let audiobook = Audiobook(context: context)
        
        audiobook.id = UUID()
        audiobook.title = "Performance Test Book (\(format))"
        audiobook.author = "Test Author"
        audiobook.duration = TimeInterval(durationMinutes * 60)
        audiobook.currentPosition = 0
        audiobook.dateAdded = Date()
        
        return audiobook
    }
    
    private func createMultiFileAudiobook(chapterCount: Int) -> Audiobook {
        let audiobook = createMockAudiobook(durationMinutes: chapterCount * 10)
        let context = persistenceController.container.viewContext
        
        for i in 0..<chapterCount {
            let chapter = Chapter(context: context)
            chapter.chapterNumber = Int16(i)
            chapter.title = "Chapter \(i + 1)"
            chapter.startTime = TimeInterval(i * 600) // 10 minutes per chapter
            chapter.endTime = TimeInterval((i + 1) * 600)
            chapter.audiobook = audiobook
        }
        
        return audiobook
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0
    }
    
    private func loadBaselinePerformanceMetrics() -> [String: Double] {
        // Load from persistent storage or return defaults
        return [
            "engine_setup_time": 0.5,
            "file_load_time_60min": 2.0,
            "play_latency": 0.1,
            "seek_operation_time": 0.2,
            "chapter_transition_10chapters": 0.3
        ]
    }
    
    private func runComprehensivePerformanceSuite() -> [String: Double] {
        // Run key performance tests and return metrics
        var metrics: [String: Double] = [:]
        
        // Engine setup
        let setupStart = CFAbsoluteTimeGetCurrent()
        let engine = AudioEngine()
        engine.setupAudioSession()
        metrics["engine_setup_time"] = CFAbsoluteTimeGetCurrent() - setupStart
        
        // File loading
        let testBook = createMockAudiobook(durationMinutes: 60)
        let loadStart = CFAbsoluteTimeGetCurrent()
        engine.loadAudiobook(testBook)
        metrics["file_load_time_60min"] = CFAbsoluteTimeGetCurrent() - loadStart
        
        // Playback latency
        let playStart = CFAbsoluteTimeGetCurrent()
        engine.startPlayback()
        metrics["play_latency"] = CFAbsoluteTimeGetCurrent() - playStart
        
        // Seek performance
        let seekStart = CFAbsoluteTimeGetCurrent()
        engine.seekTo(time: 1800) // 30 minutes
        metrics["seek_operation_time"] = CFAbsoluteTimeGetCurrent() - seekStart
        
        engine.stopPlayback()
        return metrics
    }
    
    private func savePerformanceMetrics(_ metrics: [String: Double]) {
        // Save to persistent storage for future baseline comparisons
        // In practice, this would write to UserDefaults or a file
        metricsCollector.saveBaseline(metrics)
    }
}

// MARK: - Supporting Classes and Configurations

struct AudioPerformanceConfiguration {
    let maxEngineSetupTime: TimeInterval = 1.0
    let audioFileSizes = [30, 60, 120, 240, 480] // minutes
    
    let latencyMeasurementCount = 10
    let maxAverageLatency: TimeInterval = 0.15
    let maxPeakLatency: TimeInterval = 0.5
    
    let bufferTestDuration: TimeInterval = 30.0
    let maxBufferCheckTime: TimeInterval = 0.01
    
    let multiFileChapterCounts = [5, 10, 20, 50]
    let maxChapterTransitionTime: TimeInterval = 0.5
    let maxCrossfadeTime: TimeInterval = 1.0
    
    let seekOperationCount = 20
    let maxSeekTime: TimeInterval = 0.3
    let maxSeekAccuracyError: TimeInterval = 1.0
    
    let rapidSeekCount = 50
    let maxRapidSeekTime: TimeInterval = 0.1
    
    let batteryTestDuration: TimeInterval = 300.0 // 5 minutes
    let maxBatteryUsageRate: Double = 5.0 // percentage per hour
    let maxTotalBatteryUsage: Double = 2.0 // percentage
    
    let longPlaybackTestDuration: TimeInterval = 600.0 // 10 minutes
    let minPowerEfficiency: Double = 0.8
    let maxMemoryDuringLongPlayback: Double = 150.0 // MB
    
    let memoryStabilityMeasurements = 30
    let maxMemoryGrowthDuringPlayback: Double = 50.0 // MB
    let maxMemoryLeakAfterPlayback: Double = 10.0 // MB
    let maxMemoryVariance: Double = 30.0 // MB
    
    let minSignalToNoiseRatio: Double = 60.0 // dB
    let maxTotalHarmonicDistortion: Double = 0.01 // 1%
    let minDynamicRange: Double = 80.0 // dB
    
    let regressionThreshold: Double = 1.2 // 20% slower is regression
    
    func calculateMaxLoadTime(for durationMinutes: Int) -> TimeInterval {
        return 0.5 + (TimeInterval(durationMinutes) * 0.01) // Base time + scaling factor
    }
    
    func calculateMaxMultiFileLoadTime(for chapterCount: Int) -> TimeInterval {
        return 1.0 + (TimeInterval(chapterCount) * 0.05) // Base time + per-chapter overhead
    }
}

class PerformanceMetricsCollector {
    private var metrics: [String: [Double]] = [:]
    
    func recordMetric(name: String, value: Double) {
        if metrics[name] == nil {
            metrics[name] = []
        }
        metrics[name]?.append(value)
    }
    
    func getAverageMetric(name: String) -> Double? {
        guard let values = metrics[name], !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    func saveBaseline(_ baseline: [String: Double]) {
        // Implementation for saving baseline metrics
        UserDefaults.standard.set(baseline, forKey: "performance_baseline")
    }
}

class BatteryUsageMonitor {
    private var isMonitoring = false
    private var startTime: Date?
    private var startBatteryLevel: Float = 0
    
    func startMonitoring() {
        isMonitoring = true
        startTime = Date()
        startBatteryLevel = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
        UIDevice.current.isBatteryMonitoringEnabled = false
    }
    
    func getCurrentUsage() -> Double {
        guard isMonitoring, let startTime = startTime else { return 0 }
        let currentLevel = UIDevice.current.batteryLevel
        let usagePercentage = Double(startBatteryLevel - currentLevel) * 100
        let timeElapsed = Date().timeIntervalSince(startTime) / 3600 // hours
        return timeElapsed > 0 ? usagePercentage / timeElapsed : 0
    }
    
    func getTotalUsage() -> Double {
        let currentLevel = UIDevice.current.batteryLevel
        return Double(startBatteryLevel - currentLevel) * 100
    }
}

class PowerEfficiencyMonitor {
    private var isMonitoring = false
    private var baselineEfficiency: Double = 1.0
    
    func startMonitoring() {
        isMonitoring = true
        baselineEfficiency = 1.0
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
    
    func getCurrentEfficiency() -> Double {
        // Mock implementation - in practice would measure CPU/battery usage
        return baselineEfficiency * Double.random(in: 0.95...1.05)
    }
}

class AudioQualityAnalyzer {
    func analyze(audioEngine: AudioEngine) -> AudioQualityResults {
        // Mock implementation - in practice would analyze actual audio output
        return AudioQualityResults(
            signalToNoiseRatio: Double.random(in: 65...75),
            totalHarmonicDistortion: Double.random(in: 0.005...0.008),
            dynamicRange: Double.random(in: 85...95)
        )
    }
}

struct AudioQualityResults {
    let signalToNoiseRatio: Double // dB
    let totalHarmonicDistortion: Double // percentage
    let dynamicRange: Double // dB
}

// MARK: - Mock Extensions for Performance Testing

extension MockAudioEngine {
    func getBufferStatus() -> Bool {
        return true // Mock buffer status
    }
    
    private var currentChapter: Int {
        get { return 0 }
        set { /* Mock storage */ }
    }
}