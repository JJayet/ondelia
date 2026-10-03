import Foundation
import Testing

@MainActor
func waitUntil(
    timeout: TimeInterval = 3,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    return condition()
}

extension Trait where Self == ConditionTrait {
    /// For tests that wait for audio to play in real time. The CI simulator has no audio output and
    /// playback there stalls at random, so these run locally only. CI sets `TEST_RUNNER_CI`, which
    /// xcodebuild passes to the tests as `CI`.
    static var needsRealTimePlayback: Self {
        .disabled(
            if: !(ProcessInfo.processInfo.environment["CI"] ?? "").isEmpty,
            "Real-time playback stalls on the CI simulator"
        )
    }
}
