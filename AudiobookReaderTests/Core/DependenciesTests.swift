import Testing
import SwiftUI
@testable import AudiobookReader

/// What the container actually has to guarantee: the live one hands back the real singletons,
/// the preview one substitutes audio and the library so a preview never drives playback or
/// touches the store, and the environment default picks the right one.
///
/// The mocks' own behaviour is not tested here. `PlayerViewModelTests` exercises them through
/// the code that consumes them, which is the only place their behaviour matters.
@MainActor
struct DependenciesTests {

    @Test("Live dependencies hand back the app's shared instances")
    func liveDependenciesUseSharedInstances() {
        let dependencies = LiveDependencies()

        #expect(dependencies.audioManager === GlobalAudioManager.shared)
        #expect(dependencies.audiobookManager as AnyObject === AudiobookManager.shared)
        #expect(dependencies.themeManager === ThemeManager.shared)
        #expect(dependencies.readingStatistics === ReadingStatistics.shared)
        #expect(dependencies.swiftDataController === SwiftDataController.shared)
    }

    @Test("Preview dependencies substitute audio and the library, and share one in-memory store")
    func previewDependenciesSubstituteSideEffects() {
        let first = PreviewDependencies()
        let second = PreviewDependencies()

        #expect(first.audioManager is MockGlobalAudioManager)
        #expect(first.audiobookManager is MockAudiobookManager)
        // Separate audio managers, so two previews on screen cannot fight over one state.
        #expect(first.audioManager !== second.audioManager)
        // One in-memory store, so previews stay cheap.
        #expect(first.swiftDataController === SwiftDataController.preview)
        #expect(first.swiftDataController === second.swiftDataController)
    }

    @Test("The environment default is the live container outside previews")
    func environmentDefaultIsLiveOutsidePreviews() {
        struct Probe: View {
            @Environment(\.dependencies) var dependencies
            var body: some View { EmptyView() }
        }

        #expect(ProcessInfo.isPreview == false)
        #expect(Probe().dependencies is LiveDependencies)
    }
}
