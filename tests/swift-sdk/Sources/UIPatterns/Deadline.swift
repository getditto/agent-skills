//
// Bounding a completion-handler API that has no cancellation of its own.
//
// Several Ditto APIs are completion-based (`auth.login`, the attachment fetcher's
// events). Bridging one with `withCheckedThrowingContinuation` is correct, but the
// result is neither cancellable nor bounded: if the completion never fires the awaiting
// task suspends forever, which at app launch is a watchdog termination.
//
// The obvious bound — race the continuation against a sleeping sibling in a task group —
// DOES NOT WORK, and reads as if it does. A task group does not return until every child
// finishes, and a child suspended inside `withCheckedThrowingContinuation` is not
// cancellable, so `cancelAll()` cannot end it. Measured: a 2-second timeout around a
// never-resuming continuation was still blocked after 8 seconds.
//
// The deadline has to resume the SAME continuation. That is what this does.
//

import Foundation

public enum Deadline {
    public struct Exceeded: Error, Equatable {}

    /// Runs `body`, which must eventually call its `complete` argument, and throws
    /// `Exceeded` if it has not done so within `seconds`.
    ///
    /// Exactly one of the two paths resumes the continuation; the loser no-ops, so a
    /// late completion after a timeout is harmless rather than a double-resume crash.
    public static func run(
        seconds: UInt64,
        _ body: @escaping @Sendable (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        let gate = Gate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let timer = Task {
                // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is iOS 16+
                // and this package's floor is the SDK's own iOS 15.
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                if await gate.claim() { continuation.resume(throwing: Exceeded()) }
            }
            body { error in
                Task {
                    guard await gate.claim() else { return }
                    timer.cancel()
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    /// Ensures a continuation is resumed exactly once when two paths can resume it.
    actor Gate {
        private var claimed = false
        func claim() -> Bool {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
