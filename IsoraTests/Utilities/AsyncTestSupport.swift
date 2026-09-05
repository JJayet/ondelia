import Foundation

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
