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
// Both the deadline and cancellation therefore have to resume the SAME continuation.
// `Gate` owns it and admits exactly one resumption.
//

import Foundation

public enum Deadline {
    public struct Exceeded: Error, Equatable {}

    /// Runs `body`, which must eventually call its `complete` argument.
    ///
    /// Throws `Exceeded` if `body` has not completed within `seconds`, and
    /// `CancellationError` if the calling task is cancelled first. A late completion
    /// after either is a no-op rather than a double-resume crash.
    public static func run(
        seconds: UInt64,
        _ body: @escaping @Sendable (@escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        let gate = Gate()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task { await gate.install(continuation) }

                let timer = Task {
                    // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is iOS
                    // 16+ and this package's floor is the SDK's own iOS 15.
                    try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                    await gate.finish(Exceeded())
                }

                body { error in
                    Task {
                        // Not required for correctness — `Gate` already ignores the
                        // later of the two. It stops the sleeping task early so the
                        // deadline does not outlive the call it was bounding.
                        timer.cancel()
                        await gate.finish(error)
                    }
                }
            }
        } onCancel: {
            // An unstructured `Task` does NOT inherit cancellation, so the timer above
            // cannot observe it — without this handler a cancelled caller stays blocked
            // for the full deadline and then reports `Exceeded`, mistaking a deliberate
            // teardown for an unreachable server.
            Task { await gate.finish(CancellationError()) }
        }
    }

    /// Owns the continuation so that the deadline, the completion and cancellation can
    /// all resume it, and exactly one of them wins.
    ///
    /// `finished` is the SINGLE place that invariant is enforced — deliberately, so it is
    /// testable. An earlier version also cleared `continuation` and cancelled the timer,
    /// which is defence in depth that no test can distinguish from the real guard:
    /// removing any one of the three left every test green.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var outcome: Error?
        private var finished = false

        func install(_ continuation: CheckedContinuation<Void, Error>) {
            // A resumption can arrive before `install` runs, since both are scheduled
            // onto this actor: replay it rather than dropping it.
            if finished {
                resume(continuation)
                return
            }
            self.continuation = continuation
        }

        func finish(_ error: Error?) {
            guard !finished else { return }
            finished = true
            outcome = error
            if let continuation { resume(continuation) }
        }

        private func resume(_ continuation: CheckedContinuation<Void, Error>) {
            if let outcome {
                continuation.resume(throwing: outcome)
            } else {
                continuation.resume()
            }
        }
    }
}
