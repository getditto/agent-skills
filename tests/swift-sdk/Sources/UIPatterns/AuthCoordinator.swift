//
// CAP-04: the authentication expiration handler under Swift 6.
//
// `DittoAuthenticationExpirationHandler` is `@Sendable` and `async`. It runs off the
// main actor, must not touch UI state directly, and must be installed before
// `sync.start()` — starting a server-backed instance without one fails with
// `DittoError.authenticationError(.expirationHandlerMissing)`.
//

import Foundation
import os

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

/// Owns the mutable token state. This is what an actor is for — not for wrapping
/// `Ditto`, which is already `Sendable` on v5 and gains nothing from an actor hop.
///
/// **A real app replaces this with a call to its own backend.** The expiration handler
/// runs *because the token expired*, so re-submitting the cached one cannot succeed —
/// see `AuthCoordinator.init(fetchToken:)`. This type is the shape of the seam, with a
/// literal behind it so the samples compile; it is not a credential store. In particular
/// it does not persist anything, and a shipped app should keep the token in the Keychain
/// rather than in a `String` in the app binary.
public actor TokenStore {
    private var token: String

    public init(token: String) {
        self.token = token
    }

    public func current() -> String { token }

    public func replace(with token: String) { self.token = token }
}

public struct AuthCoordinator: Sendable {
    public enum AuthError: Error, Equatable {
        case noAuthenticator
        case timedOut
    }

    private let fetchToken: @Sendable () async throws -> String
    private let provider: DittoAuthenticationProvider
    private let timeoutSeconds: UInt64
    private let reauthenticationAttempts: Int

    /// - Parameter fetchToken: fetches a CURRENT token, called once per attempt. It is
    ///   bounded by `timeoutSeconds`, but that bound only releases this caller — it
    ///   cannot stop work that does not observe cancellation. Make it cancellation-aware
    ///   (`URLSession`'s async API is) or the abandoned attempt keeps running.
    /// - Parameter reauthenticationAttempts: how many times the **expiration handler**
    ///   retries. The SDK awaits that handler, so the worst case it costs is
    ///   `reauthenticationAttempts × (fetch + login) timeouts` plus backoff. The explicit
    ///   `login(_:)` used at launch does not retry: there the caller is a UI that should
    ///   show a failure and offer a button, not stall.
    public init(
        fetchToken: @escaping @Sendable () async throws -> String,
        provider: DittoAuthenticationProvider = .development,
        timeoutSeconds: UInt64 = 15,
        reauthenticationAttempts: Int = 3
    ) {
        self.fetchToken = fetchToken
        self.provider = provider
        self.timeoutSeconds = timeoutSeconds
        self.reauthenticationAttempts = reauthenticationAttempts
    }

    /// Convenience for a fixed token — tests, and a server whose token outlives the
    /// session. Anything with a real expiry must use `init(fetchToken:)`.
    public init(
        tokens: TokenStore,
        provider: DittoAuthenticationProvider = .development,
        timeoutSeconds: UInt64 = 15,
        reauthenticationAttempts: Int = 3
    ) {
        self.init(
            fetchToken: { await tokens.current() },
            provider: provider,
            timeoutSeconds: timeoutSeconds,
            reauthenticationAttempts: reauthenticationAttempts
        )
    }

    /// Whether another attempt could plausibly succeed.
    ///
    /// A rejected credential and an expired license are verdicts, not blips: retrying
    /// spends the caller's whole deadline to arrive at the answer it already had, and
    /// buries it under two more identical log lines.
    public static func isRetryable(_ error: Error) -> Bool {
        // `auth` is nil for the whole lifetime of a `.smallPeersOnly` instance, so this
        // one is a configuration mistake, not a transient failure.
        if let error = error as? AuthError, error == .noAuthenticator { return false }
        guard let error = error as? DittoError else { return true }
        switch error {
        case .authenticationError(.failedToAuthenticate):
            return false
        case .activationError(.licenseTokenExpired),
             .activationError(.licenseTokenVerificationFailed),
             .activationError(.licenseTokenUnsupportedFutureVersion):
            return false
        default:
            return true
        }
    }

    /// Installs the handler and performs the first login. Call before `sync.start()`.
    public func start(_ ditto: Ditto) async throws {
        install(on: ditto)
        try await login(ditto)
    }

    /// Installs the expiration handler.
    ///
    /// The handler is `async` precisely so the SDK can **await** re-authentication
    /// before treating sync as authenticated, so it awaits the login rather than
    /// dispatching one and returning. There is no caller to rethrow to, so failure goes
    /// to `os.Logger` at error level — which is what a sysdiagnose and a crash reporter
    /// pick up. It must not touch UI state: it runs off the main actor.
    ///
    /// **It retries.** This is the only chance to re-authenticate: nothing calls the
    /// handler again until the token next expires, so a single attempt lost to a captive
    /// portal or a server blip leaves the instance unauthenticated for the rest of the
    /// session — sync stops and nothing reports why. See `reauthenticationAttempts` for
    /// what that costs.
    public func install(on ditto: Ditto) {
        let fetchToken = self.fetchToken
        let provider = self.provider
        let timeoutSeconds = self.timeoutSeconds
        let attempts = self.reauthenticationAttempts
        let logger = Logger(subsystem: "live.ditto.skill-samples", category: "auth")
        ditto.auth?.expirationHandler = { ditto, _ in
            do {
                try await Retry.run(
                    attempts: attempts,
                    firstBackoffSeconds: 2,
                    isRetryable: Self.isRetryable,
                    onFailure: { attempt, error, nextDelay in
                        let retrying = nextDelay.map { "retrying in \($0)s" } ?? "giving up"
                        logger.warning(
                            "Ditto re-authentication attempt \(attempt, privacy: .public) failed (\(retrying, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                ) {
                    // Fetched inside the retry, not once outside it: the handler runs
                    // BECAUSE the token expired, so every attempt needs a fresh one.
                    try await Self.performLogin(
                        ditto,
                        fetchToken: fetchToken,
                        provider: provider,
                        timeoutSeconds: timeoutSeconds
                    )
                }
            } catch is CancellationError {
                // A teardown, not a failure. Logging it at error level would put a
                // spurious auth failure in every sysdiagnose taken after a clean exit.
                logger.debug("Ditto re-authentication cancelled")
            } catch {
                logger.error(
                    "Ditto re-authentication gave up: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// The same login, awaited — for launch, where the app should not proceed until the
    /// first login has succeeded, failed, or timed out.
    ///
    /// Deliberately does NOT retry. Here there is a caller and a UI: report the failure
    /// and offer a button, rather than stalling launch behind three attempts.
    public func login(_ ditto: Ditto) async throws {
        try await Self.performLogin(
            ditto,
            fetchToken: fetchToken,
            provider: provider,
            timeoutSeconds: timeoutSeconds
        )
    }

    /// Bridges the completion-handler `login` into async/await **with a deadline**.
    ///
    /// `withCheckedThrowingContinuation` alone is neither cancellable nor bounded, so if
    /// the completion never fires — unreachable server, captive portal, DNS black hole —
    /// the awaiting task suspends forever. At launch that is an iOS watchdog termination.
    ///
    /// **A task group does not bound it.** A group does not return until every child
    /// finishes, and a child suspended inside `withCheckedThrowingContinuation` is not
    /// cancellable, so `cancelAll()` cannot end it: the timeout child produces the error
    /// and the group then blocks forever waiting for its sibling. Measured — a 2-second
    /// timeout against a never-resuming continuation was still blocked after 8 seconds.
    ///
    /// The deadline therefore has to resume the **same** continuation. `Gate` makes
    /// exactly one of the two resumptions win; the losing SDK callback no-ops. The
    /// sensible response to `.timedOut` is usually to proceed offline, because Ditto's
    /// local store works without authentication.
    private static func performLogin(
        _ ditto: Ditto,
        fetchToken: @escaping @Sendable () async throws -> String,
        provider: DittoAuthenticationProvider,
        timeoutSeconds: UInt64
    ) async throws {
        guard let auth = ditto.auth else { throw AuthError.noAuthenticator }

        // Inside the deadline, not passed in as an already-evaluated argument.
        // `fetchToken` is the app's own network call — behind a captive portal it can
        // suspend for its own timeout or forever, and an argument is evaluated BEFORE
        // this function's body runs, so a deadline set up below could never have bounded
        // it. The SDK awaits the expiration handler, so an unbounded fetch there parks
        // re-authentication permanently on the first attempt.
        let token: String
        do {
            token = try await Deadline.value(seconds: timeoutSeconds) { try await fetchToken() }
        } catch is Deadline.Exceeded {
            throw AuthError.timedOut
        }

        do {
            try await Deadline.run(seconds: timeoutSeconds) { complete in
                auth.login(token: token, provider: provider) { _, error in complete(error) }
            }
        } catch is Deadline.Exceeded {
            throw AuthError.timedOut
        }
    }

}
