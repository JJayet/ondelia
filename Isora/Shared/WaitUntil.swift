import Foundation
import Observation

/// Suspends until `condition` holds.
///
/// Everything these callers wait on is `@Observable`, so the wait can be driven by the change
/// itself instead of a 100 ms timer: the loops this replaced woke ten times a second to ask
/// whether the store had finished loading yet.
///
/// `condition` must read at least one observable property, or nothing will ever wake it.
@MainActor
func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
