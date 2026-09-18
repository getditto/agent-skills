//
// Bounded retry with exponential backoff.
//
// The authentication expiration handler is the reason this exists. It is `async` so the
// SDK can await re-authentication before treating sync as authenticated, and it has no
// caller to rethrow to — so a single failed attempt that only logs leaves the instance
// unauthenticated until the token next expires, which for a long-lived session is
// "sync silently stopped working". A captive portal or a server blip at exactly the
// wrong second is enough.
//
// Retrying inside the handler is not free: the SDK is awaiting it, so the worst case is
// `attempts × login timeout` plus the backoff. Keep both bounded and deliberate.
//

import Foundation

public enum Retry {
    /// Runs `body`, retrying a thrown error up to `attempts` times with exponential
    /// backoff. Rethrows the LAST error once the attempts are spent.
    ///
    /// - Parameter isRetryable: decides whether an error is worth another attempt.
    ///   The default retries everything, which is wrong for most real callers: a
    ///   credential the server rejected will be rejected again, so retrying it just
    ///   spends the caller's deadline before reporting the failure it already had.
    /// - Parameter onFailure: called for each failed attempt with the delay before the
    ///   next one, or `nil` when this was the last. Reporting the delay is what lets a
    ///   caller log "retrying in 4s" — and what lets a test assert the backoff policy
    ///   without measuring a clock.
    ///
    /// Cancellation is honoured and is never retried: a cancelled caller is released
    /// during the backoff rather than running out the remaining attempts, and a caller
    /// that was already cancelled does not get one free attempt first.
    public static func run(
        attempts: Int,
        firstBackoffSeconds: Double = 1,
        isRetryable: @Sendable (Error) -> Bool = { _ in true },
        onFailure: (@Sendable (Int, Error, Double?) -> Void)? = nil,
        _ body: @Sendable () async throws -> Void
    ) async throws {
        try Task.checkCancellation()

        let total = max(1, attempts)
        var backoff = firstBackoffSeconds

        for attempt in 1...total {
            do {
                try await body()
                return
            } catch is CancellationError {
                // Never a failed attempt: it is the caller going away. Reporting it as
                // one turns a deliberate teardown into error-level auth telemetry.
                throw CancellationError()
            } catch {
                let isLast = attempt == total || !isRetryable(error)
                onFailure?(attempt, error, isLast ? nil : backoff)
                if isLast { throw error }
                // `Task.sleep(nanoseconds:)`, not `sleep(for:)`: `Duration` is iOS 16+
                // and the SDK's own floor is iOS 15. This throws `CancellationError`,
                // which is what releases a cancelled caller early.
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff *= 2
            }
        }
    }
}
