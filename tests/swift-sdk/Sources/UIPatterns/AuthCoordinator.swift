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
public actor TokenStore {
    private var token: String

    public init(token: String) {
        self.token = token
    }

    public func current() -> String { token }

    public func replace(with token: String) { self.token = token }
}

public struct AuthCoordinator: Sendable {
    public enum AuthError: Error {
        case noAuthenticator
        case timedOut
    }

    private let tokens: TokenStore
    private let provider: DittoAuthenticationProvider
    private let timeoutSeconds: UInt64

    public init(
        tokens: TokenStore,
        provider: DittoAuthenticationProvider = .development,
        timeoutSeconds: UInt64 = 15
    ) {
        self.tokens = tokens
        self.provider = provider
        self.timeoutSeconds = timeoutSeconds
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
    public func install(on ditto: Ditto) {
        let tokens = self.tokens
        let provider = self.provider
        let timeoutSeconds = self.timeoutSeconds
        ditto.auth?.expirationHandler = { ditto, _ in
            do {
                try await Self.performLogin(
                    ditto, tokens: tokens, provider: provider, timeoutSeconds: timeoutSeconds
                )
            } catch {
                Logger(subsystem: "live.ditto.skill-samples", category: "auth")
                    .error("Ditto re-authentication failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The same login, awaited — for launch, where the app should not proceed until the
    /// first login has succeeded, failed, or timed out.
    public func login(_ ditto: Ditto) async throws {
        try await Self.performLogin(
            ditto, tokens: tokens, provider: provider, timeoutSeconds: timeoutSeconds
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
        tokens: TokenStore,
        provider: DittoAuthenticationProvider,
        timeoutSeconds: UInt64
    ) async throws {
        guard let auth = ditto.auth else { throw AuthError.noAuthenticator }
        let token = await tokens.current()

        do {
            try await Deadline.run(seconds: timeoutSeconds) { complete in
                auth.login(token: token, provider: provider) { _, error in complete(error) }
            }
        } catch is Deadline.Exceeded {
            throw AuthError.timedOut
        }
    }
}
