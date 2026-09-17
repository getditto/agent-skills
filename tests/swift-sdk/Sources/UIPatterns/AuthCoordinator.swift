//
// CAP-04: the authentication expiration handler under Swift 6.
//
// `DittoAuthenticationExpirationHandler` is `@Sendable` and `async`. It runs off the
// main actor, must not touch UI state directly, and must be installed before
// `sync.start()` — starting a server-backed instance without one fails with
// `DittoError.authenticationError(.expirationHandlerMissing)`.
//

import Foundation

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
    private let tokens: TokenStore
    private let provider: DittoAuthenticationProvider

    public init(tokens: TokenStore, provider: DittoAuthenticationProvider = .development) {
        self.tokens = tokens
        self.provider = provider
    }

    /// Installs the handler. Call this before `ditto.sync.start()`.
    public func install(on ditto: Ditto) {
        let tokens = self.tokens
        let provider = self.provider
        ditto.auth?.expirationHandler = { ditto, _ in
            let token = await tokens.current()
            ditto.auth?.login(token: token, provider: provider) { _, error in
                if let error {
                    // Log; do not mutate UI state from here.
                    print("Ditto login failed: \(error)")
                }
            }
        }
    }

    /// The same login, awaited — useful at launch, where the app should not proceed
    /// until the first login has either succeeded or failed.
    public func login(_ ditto: Ditto) async throws {
        let token = await tokens.current()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let auth = ditto.auth else {
                continuation.resume(
                    throwing: DittoError.authenticationError(reason: .failedToAuthenticate)
                )
                return
            }
            auth.login(token: token, provider: provider) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
