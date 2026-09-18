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
                    do {
                        // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is
                        // iOS 16+ and this package's floor is the SDK's own iOS 15.
                        try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                    } catch {
                        // `try?` here would be a BUG, not a shortcut. A cancelled sleep
                        // returns IMMEDIATELY, so swallowing its error would send this
                        // task straight on to report `Exceeded` — turning `cancel()`
                        // below from "stop the timer" into "start a race with the
                        // completion that just won". Returning is what makes cancelling
                        // the timer mean anything.
                        return
                    }
                    await gate.finish(Exceeded())
                }
                Task { await gate.adopt(timer) }

                body { error in
                    Task {
                        timer.cancel()
                        await gate.finish(error)
                    }
                }
            }
        } onCancel: {
            // An unstructured `Task` does NOT inherit cancellation, so the timer above
            // cannot observe it — without this handler a cancelled caller stays blocked
            // for the full deadline and then reports `Exceeded`, mistaking a deliberate
            // teardown for an unreachable server. `finish` also stops the timer, which
            // would otherwise sleep out the full deadline after the caller had gone.
            Task { await gate.finish(CancellationError()) }
        }
    }

    /// The same bound, for an `async` call that returns a value.
    ///
    /// Built on `run(seconds:_:)` rather than on a task group. A task group does NOT
    /// bound this: it does not return until every child finishes, so a `work` that is not
    /// cancellation-aware keeps the group alive and the timeout never escapes. Measured
    /// on exactly that shape — a 2-second deadline still blocked at 8.5s, having leaked
    /// its continuation. The gate below owns the continuation and resumes it, so the
    /// caller is released whether or not `work` can be cancelled.
    ///
    /// The abandoned `work` is cancelled on the way out, which only helps if it observes
    /// cancellation; if it does not, it runs to completion in the background and its
    /// result is discarded. **Releasing the caller is the guarantee, not stopping the
    /// work.**
    public static func value<T: Sendable>(
        seconds: UInt64,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let outcome = Box<Result<T, Error>>()
        let worker = Box<Task<Void, Never>>()

        do {
            try await run(seconds: seconds) { complete in
                worker.value = Task {
                    do {
                        outcome.value = .success(try await work())
                        complete(nil)
                    } catch {
                        outcome.value = .failure(error)
                        complete(error)
                    }
                }
            }
        } catch {
            worker.value?.cancel()
            throw error
        }

        guard let result = outcome.value else { throw Exceeded() }
        return try result.get()
    }

    /// Minimal thread-safe cell. `run`'s body is a synchronous closure, so a result has
    /// to cross back through shared storage rather than an actor hop.
    final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value?
        var value: Value? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
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
        private var timer: Task<Void, Never>?

        /// Lets whoever finishes first stop the deadline, including `onCancel`.
        func adopt(_ timer: Task<Void, Never>) {
            if finished {
                timer.cancel()
                return
            }
            self.timer = timer
        }

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
            timer?.cancel()
            timer = nil
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
