# AudiobookReader Testing Strategy

## Overview

This document outlines a comprehensive testing strategy for the AudiobookReader iOS application, covering unit tests, integration tests, UI tests, and performance testing.

## Testing Architecture

### Testing Pyramid
- **Unit Tests (60-70%)**: Fast, isolated tests for business logic
- **Integration Tests (20-30%)**: Component interaction and workflow testing  
- **UI Tests (10-15%)**: Critical user journey validation
- **Performance Tests (5%)**: Audio processing and memory usage

### Test Categories

## 1. Unit Tests

### 1.1 Audio Engine Tests
**Target**: `AudioEngine.swift`
```swift
// Test file: AudioEngineTests.swift
class AudioEngineTests: XCTestCase {
    func testAudioSessionSetup()
    func testAudioSessionFallback()
    func testPlaybackControls()
    func testTimeObservers()
    func testMemoryCleanup()
    func testThreadingSafety()
    func testWeakReferenceHandling()
}
```

**Key Test Cases**:
- ✅ Audio session configuration with various options
- ✅ Fallback audio session when primary setup fails
- ✅ Play/pause/seek functionality
- ✅ Time observer setup and cleanup
- ✅ Memory management and deallocation
- ✅ Thread-safe operations on audioQueue
- ✅ Weak reference handling in async operations

### 1.2 MultiFile Audio Engine Tests
**Target**: `MultiFileAudioEngine.swift`
```swift
// Test file: MultiFileAudioEngineTests.swift
class MultiFileAudioEngineTests: XCTestCase {
    func testMultiFileLoading()
    func testChapterNavigation()
    func testCrossFadeTransitions()
    func testFileValidation()
    func testErrorRecovery()
}
```

### 1.3 CUE Parser Tests
**Target**: `CUEParser.swift`
```swift
// Test file: CUEParserTests.swift
class CUEParserTests: XCTestCase {
    func testBasicCUEParsing()
    func testTimeFormatConversion()
    func testMalformedCUEHandling()
    func testChapterExtraction()
    func testAudioFileMatching()
    func testInternationalCharacters()
}
```

**Key Test Cases**:
- ✅ Parse standard CUE file format (MM:SS:FF)
- ✅ Convert frames to seconds (75 frames = 1 second)
- ✅ Handle malformed CUE files gracefully
- ✅ Extract chapter titles and metadata
- ✅ Match CUE files with audio files (case insensitive)
- ✅ Handle international characters and special symbols
- ✅ Parse files with missing metadata fields
- ✅ Handle empty or corrupt CUE files

### 1.4 Metadata Extractor Tests
**Target**: `MetadataExtractor.swift`
```swift
// Test file: MetadataExtractorTests.swift  
class MetadataExtractorTests: XCTestCase {
    func testM4BMetadataExtraction()
    func testMP3MetadataExtraction()
    func testChapterExtraction()
    func testCoverArtExtraction()
    func testCorruptFileHandling()
    func testSecurityScopedResources()
}
```

### 1.5 Import Services Tests

#### 1.5.1 Folder Importer Tests
**Target**: `FolderImporter.swift`
```swift
// Test file: FolderImporterTests.swift
class FolderImporterTests: XCTestCase {
    func testSingleAudioFileFolder()
    func testMultipleAudioFilesFolder()
    func testCUEFileDetection()
    func testCoverImageDiscovery()
    func testFolderNameParsing()
    func testEmptyFolderHandling()
}
```

#### 1.5.2 ZIP Importer Tests
**Target**: `ZIPImporter.swift`
```swift
// Test file: ZIPImporterTests.swift
class ZIPImporterTests: XCTestCase {
    func testZIPExtraction()
    func testNestedFolderHandling()
    func testCorruptZIPHandling()
    func testPasswordProtectedZIP()
    func testLargeZIPFiles()
    func testCUEFileInZIP()
}
```

### 1.6 Manager Classes Tests

#### 1.6.1 Global Audio Manager Tests
**Target**: `GlobalAudioManager.swift`
```swift
// Test file: GlobalAudioManagerTests.swift
class GlobalAudioManagerTests: XCTestCase {
    func testEngineSelection()
    func testEngineCleanup()
    func testAudiobookLoading()
    func testPlaybackStateManagement()
    func testPositionTracking()
    func testEngineRetention()
}
```

#### 1.6.2 Audiobook Manager Tests
**Target**: `AudiobookManager.swift`
```swift
// Test file: AudiobookManagerTests.swift
class AudiobookManagerTests: XCTestCase {
    func testSingleFileImport()
    func testFolderImport()
    func testZIPImport()
    func testCUEBasedImport()
    func testDuplicateHandling()
    func testProgressPersistence()
    func testMetadataStorage()
}
```

### 1.7 Utility Classes Tests

#### 1.7.1 Theme Manager Tests
**Target**: `ThemeManager.swift`
```swift
// Test file: ThemeManagerTests.swift
class ThemeManagerTests: XCTestCase {
    func testThemeSwitching()
    func testColorSchemeHandling()
    func testPersistence()
    func testDefaultTheme()
}
```

#### 1.7.2 Dependencies System Tests
**Target**: `AudiobookDependencies.swift`, `MockDependencies.swift`
```swift
// Test file: DependenciesTests.swift
class DependenciesTests: XCTestCase {
    func testMockDependencyInjection()
    func testPreviewModeDetection()
    func testDependencyResolution()
    func testMockDataGeneration()
}
```

## 2. Integration Tests

### 2.1 Audio Playback Workflows
```swift
// Test file: AudioPlaybackIntegrationTests.swift
class AudioPlaybackIntegrationTests: XCTestCase {
    func testSingleFilePlaybackWorkflow()
    func testMultiFilePlaybackWorkflow()
    func testCUEBasedPlaybackWorkflow()
    func testChapterNavigationWorkflow()
    func testPlaybackInterruption()
    func testBackgroundPlayback()
}
```

**Key Integration Scenarios**:
- ✅ Complete single file audiobook playback
- ✅ Multi-file audiobook with chapter transitions
- ✅ CUE-based single file with virtual chapters
- ✅ Chapter navigation and position saving
- ✅ Audio interruption (calls, other apps)
- ✅ Background playback and control center

### 2.2 Import Workflows
```swift
// Test file: ImportWorkflowTests.swift
class ImportWorkflowTests: XCTestCase {
    func testCompleteM4BImport()
    func testFolderWithCUEImport()
    func testZIPExtractionAndImport()
    func testComplexFolderStructure()
    func testImportWithMissingFiles()
}
```

### 2.3 Data Persistence Integration
```swift
// Test file: DataPersistenceTests.swift
class DataPersistenceTests: XCTestCase {
    func testAudiobookSaveAndLoad()
    func testProgressPersistence()
    func testBookmarkManagement()
    func testCoreDataMigration()
}
```

## 3. UI Tests

### 3.1 Critical User Journeys
```swift
// Test file: AudiobookReaderUITests.swift
class AudiobookReaderUITests: XCTestCase {
    func testImportAndPlayAudiobook()
    func testLibraryNavigation()
    func testPlayerControls()
    func testChapterNavigation()
    func testSettingsConfiguration()
    func testThemeSwitching()
}
```

**Key UI Test Scenarios**:
- ✅ Import audiobook from files app
- ✅ Navigate library and select audiobook
- ✅ Play/pause/seek controls functionality
- ✅ Chapter skip and selection
- ✅ Settings panel interactions
- ✅ Theme switching visual validation
- ✅ Mini player functionality
- ✅ Background app return behavior

### 3.2 SwiftUI Preview Tests
```swift
// Test file: PreviewTests.swift
class PreviewTests: XCTestCase {
    func testAllPreviewsCompile()
    func testMockDependencyInjection()
    func testPreviewDataGeneration()
    func testThemePreviewVariations()
}
```

## 4. Performance Tests

### 4.1 Audio Performance Tests
```swift
// Test file: AudioPerformanceTests.swift
class AudioPerformanceTests: XCTestCase {
    func testLargeFileLoadingPerformance()
    func testMultiFileTransitionPerformance()
    func testMemoryUsageDuringPlayback()
    func testCUEParsingPerformance()
    func testMetadataExtractionPerformance()
}
```

**Performance Benchmarks**:
- ✅ Large file (>1GB) loading time < 3 seconds
- ✅ Chapter transitions < 500ms
- ✅ Memory usage stable during long playback
- ✅ CUE parsing < 100ms for typical files
- ✅ Metadata extraction < 2 seconds for large files

### 4.2 Memory Leak Tests
```swift
// Test file: MemoryLeakTests.swift
class MemoryLeakTests: XCTestCase {
    func testAudioEngineMemoryLeaks()
    func testManagerClassMemoryLeaks()
    func testUIViewMemoryLeaks()
    func testObserverMemoryLeaks()
}
```

## 5. Test Infrastructure

### 5.1 Test Data Setup
```
AudiobookReaderTests/
├── TestResources/
│   ├── SampleAudioFiles/
│   │   ├── short-audiobook.m4b
│   │   ├── multi-chapter.mp3
│   │   ├── corrupt-file.m4a
│   │   └── large-audiobook.m4b (>1GB)
│   ├── SampleCUEFiles/
│   │   ├── standard-format.cue
│   │   ├── international-chars.cue
│   │   ├── malformed.cue
│   │   └── empty.cue
│   ├── SampleZIPFiles/
│   │   ├── audiobook-folder.zip
│   │   ├── cue-with-audio.zip
│   │   ├── nested-structure.zip
│   │   └── corrupt.zip
│   └── SampleImages/
│       ├── cover.jpg
│       ├── folder.png
│       └── albumart.webp
```

### 5.2 Mock Framework Setup
```swift
// MockFramework.swift - Custom mocking utilities
class MockAVAudioSession {
    static var shouldFailSetup = false
    static var preferredSampleRate: Double = 44100.0
}

class MockFileManager {
    static var mockFileExists: [String: Bool] = [:]
    static var mockDirectoryContents: [String: [URL]] = [:]
}

class MockAVURLAsset {
    let mockDuration: TimeInterval
    let mockMetadata: [AVMetadataItem]
    
    init(duration: TimeInterval, metadata: [AVMetadataItem] = []) {
        self.mockDuration = duration
        self.mockMetadata = metadata
    }
}
```

### 5.3 Test Configuration
```swift
// TestConfiguration.swift
enum TestConfiguration {
    static let testTimeout: TimeInterval = 10.0
    static let performanceTimeout: TimeInterval = 5.0
    static let memoryTestIterations = 100
    
    static func setupTestEnvironment() {
        // Configure for testing
        UserDefaults.standard.removePersistentDomain(
            forName: Bundle.main.bundleIdentifier!
        )
    }
}
```

## 6. Continuous Integration Setup

### 6.1 GitHub Actions Workflow
```yaml
# .github/workflows/tests.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Unit Tests
        run: |
          xcodebuild test \
            -project AudiobookReader.xcodeproj \
            -scheme AudiobookReader \
            -destination 'platform=iOS Simulator,name=iPhone 15'
      
      - name: Run UI Tests
        run: |
          xcodebuild test \
            -project AudiobookReader.xcodeproj \
            -scheme AudiobookReaderUITests \
            -destination 'platform=iOS Simulator,name=iPhone 15'
      
      - name: Upload Coverage Reports
        uses: codecov/codecov-action@v3
```

### 6.2 Test Coverage Goals
- **Overall Coverage**: > 80%
- **Critical Classes Coverage**: > 90%
  - AudioEngine: > 95%
  - GlobalAudioManager: > 90%
  - CUEParser: > 95%
  - AudiobookManager: > 90%

## 7. Testing Tools & Frameworks

### 7.1 Required Dependencies
```swift
// Test dependencies to add to Package.swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0"),
    .package(url: "https://github.com/nalexn/ViewInspector", from: "0.9.0"),
]
```

### 7.2 Custom Test Utilities
```swift
// TestUtilities.swift
extension XCTestCase {
    func waitForAudioEngineReady(_ engine: AudioEngine, timeout: TimeInterval = 5.0) {
        let expectation = XCTestExpectation(description: "Audio engine ready")
        // Implementation
    }
    
    func createMockAudiobook() -> Audiobook {
        // Create test audiobook with Core Data
    }
    
    func validateMemoryLeak<T: AnyObject>(_ instance: T, file: StaticString = #file, line: UInt = #line) {
        // Memory leak detection
    }
}
```

## 8. Implementation Phases

### Phase 1: Foundation (Week 1)
- ✅ Set up test targets and infrastructure
- ✅ Create test data resources
- ✅ Implement basic mock framework
- ✅ Add core utility classes tests

### Phase 2: Core Logic (Week 2-3)
- ✅ AudioEngine and MultiFileAudioEngine tests
- ✅ CUEParser comprehensive test suite
- ✅ MetadataExtractor tests
- ✅ Import services tests

### Phase 3: Integration (Week 4)
- ✅ Audio playback workflow tests
- ✅ Import workflow integration tests
- ✅ Manager class interaction tests

### Phase 4: UI & Performance (Week 5)
- ✅ SwiftUI component tests
- ✅ UI journey automation
- ✅ Performance benchmarking
- ✅ Memory leak detection

### Phase 5: CI/CD & Polish (Week 6)
- ✅ GitHub Actions setup
- ✅ Coverage reporting
- ✅ Test documentation
- ✅ Performance regression testing

## 9. Testing Anti-Patterns to Avoid

### ❌ Don't Do
- Test implementation details instead of behavior
- Create overly complex test setups
- Skip edge cases and error scenarios
- Test multiple concerns in single test
- Use real file system operations in unit tests
- Ignore memory management in audio tests
- Skip threading tests for concurrent code

### ✅ Do Instead  
- Focus on public API behavior
- Use simple, focused test arrangements
- Extensively test error conditions
- Follow single responsibility in tests
- Mock file system interactions
- Test memory cleanup explicitly
- Validate thread safety in concurrent operations

## 10. Success Metrics

### Quantitative Goals
- **Test Coverage**: >80% overall, >90% for critical components
- **Test Execution Time**: Unit tests <30 seconds, Integration <2 minutes  
- **CI Pipeline**: <10 minutes total including tests
- **Flaky Test Rate**: <2% of test runs

### Qualitative Goals
- **Confidence**: Refactoring without fear
- **Documentation**: Tests serve as usage examples
- **Regression Prevention**: Catch bugs before production
- **Performance Assurance**: No performance degradation

---

*This testing strategy ensures comprehensive coverage of the AudiobookReader application while maintaining fast feedback loops and high confidence in code changes.*