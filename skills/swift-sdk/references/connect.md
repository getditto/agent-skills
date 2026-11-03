# Connecting, authentication and lifecycle — Ditto Swift SDK

## Contents

- [CAP-03 Connecting: config, opening, persistence directory](#cap-03-connecting-config-opening-persistence-directory)
- [CAP-04 Authentication and identity](#cap-04-authentication-and-identity)
- [CAP-05 Lifecycle: start/stop sync, shutdown, ownership](#cap-05-lifecycle-startstop-sync-shutdown-ownership)

Everything here is the **5.1.x** form. The 4.14.x differences are in
[versions.md](versions.md#initialization-and-lifecycle).

## CAP-03 Connecting: config, opening, persistence directory

A `Ditto` instance is built from a `DittoConfig` and opened with a factory method.

```swift
import DittoSwift
import Foundation  // v5 does not re-export Foundation

let config = DittoConfig(
    databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
    connect: .server(url: URL(string: "REPLACE_ME_WITH_YOUR_CONNECT_URL")!),
    persistenceDirectory: applicationSupportDirectory()
)

let ditto = try await Ditto.open(config: config)
```

The server URL is the portal's *Connect via SDK* value, copied verbatim — an `https://`
host. Do not build it from the database ID or substitute the `wss://` sync URL. A `nil`
`persistenceDirectory` uses `<Application Support>/ditto-{databaseID}`; see
[storage.md](storage.md#default-persistence-directory).

### `open` versus `openSync`

`Ditto.open` performs the same synchronous open as `Ditto.openSync`, wrapped in an
`async` function. It is declared **nonisolated**, so it does not run on the caller's
actor ([SE-0338](https://github.com/apple/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md));
it runs on the cooperative pool.

| | Use when |
|---|---|
| `Ditto.open(config:)` — `async throws` | Anywhere you can `await`. This is the default, and it is safe on the main actor. |
| `Ditto.openSync(config:)` — `throws` | A genuinely synchronous entry point — a command-line tool, or a test helper. |

**`await Ditto.open(...)` from `@MainActor` does not block the main thread. Calling
`Ditto.openSync(...)` there does**, for the whole open. Opening can take seconds — a large
store, a cold cache, or 5.1's automatic index migration — so `openSync` on the main thread
at launch risks a watchdog termination (`0x8badf00d`) on devices with real data. Use
`await` and render a loading phase, the pattern in
[best-practices.md](../best-practices.md#instance-ownership).

**`Task.detached` is not needed here.** It schedules on the same cooperative pool `open`
already uses. `open` occupies one pool thread for its duration, which matters only if you
open many instances at once; in that case, open on a dispatch queue instead:

```swift
let ditto: Ditto = try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(with: Result { try Ditto.openSync(config: config) })
    }
}
```

### Offline-only instances

An instance with no server needs an offline license token before it will accept work:

```swift
let config = DittoConfig(
    databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
    connect: .smallPeersOnly(),
    persistenceDirectory: applicationSupportDirectory()
)
let ditto = try await Ditto.open(config: config)
try ditto.setOfflineOnlyLicenseToken("REPLACE_ME_WITH_YOUR_OFFLINE_LICENSE")
```

`ditto.isActivated` is `false` until that call succeeds. An invalid token throws
`DittoError.activationError(.licenseTokenVerificationFailed(message:))`; an expired one
throws `.licenseTokenExpired`.

### One opened instance per persistence directory

Opening a second instance against a directory a live instance already holds fails with
`DittoError.storeError(.persistenceDirectoryLocked(message:))` (added in 4.12.0), and
this in the log:

> Multiple Ditto instances cannot run at the same time within the same working
> directory. Either use unique working directories for each instance, or consider
> managing your Ditto instance as a singleton instead.

Releasing the first instance frees the directory; a new instance opened on it afterwards
reads what the first wrote.

`DittoConfigConnect` is a non-frozen enum from another module, so an exhaustive `switch`
over it needs `@unknown default` or it will not compile.

### Encryption at rest

`DittoConfigExperimental.passphrase` turns on encryption. It is preview — see
[preview.md](preview.md). `ditto.isEncrypted` reports the current state. Opening an
encrypted store without the passphrase throws
`DittoError.encryptionError(.passphraseNotGiven)`; passing one to an unencrypted store
throws `.extraneousPassphraseGiven`; a wrong one throws `.passphraseInvalid`.

## CAP-04 Authentication and identity

`ditto.auth` is `nil` for `.smallPeersOnly` and non-`nil` for `.server`.

### The expiration handler is required, `@Sendable`, and `async`

```swift
public typealias DittoAuthenticationExpirationHandler =
    @Sendable (_ ditto: Ditto, _ timeUntilExpiration: TimeInterval) async -> Void
```

Install it **before** `sync.start()`. Starting a server-backed instance without one fails
with `DittoError.authenticationError(.expirationHandlerMissing(message:))`.

```swift
/// A rejected credential or a license problem will not change on retry.
func isRetryable(_ error: Error) -> Bool {
    guard let error = error as? DittoError else { return true }
    switch error {
    case .authenticationError(.failedToAuthenticate),
         .activationError(.licenseTokenExpired),
         .activationError(.licenseTokenVerificationFailed),
         .activationError(.licenseTokenUnsupportedFutureVersion):
        return false
    default:
        return true
    }
}

ditto.auth?.expirationHandler = { ditto, _ in
    var backoff: UInt64 = 2
    for attempt in 1...3 {
        do {
            // Fetch a fresh token on every attempt: the handler runs because the
            // previous one expired.
            let token = try await fetchToken()          // your backend; bound this call
            try await login(ditto, token: token, timeoutSeconds: 15)
            return
        } catch is CancellationError {
            logger.debug("Ditto re-authentication cancelled")   // teardown, not a failure
            return
        } catch {
            guard attempt < 3, isRetryable(error) else {
                logger.error("Ditto re-authentication gave up: \(error.localizedDescription)")
                return
            }
            logger.warning("Ditto re-auth attempt \(attempt) failed, retrying in \(backoff)s: \(error)")
            do { try await Task.sleep(nanoseconds: backoff * 1_000_000_000) } catch { return }
            backoff *= 2
        }
    }
}
try ditto.sync.start()
```

`login` is the bounded bridge described [below](#awaiting-the-first-login). The handler
runs off the main actor and must not touch `@Published` properties, view controllers or
any other main-actor state directly — hop with `await MainActor.run { … }` or a
`Task { @MainActor in … }` to report status to the UI.

What the sample does, and why:

- **Fetches the token inside the retry.** Fetching once outside means every attempt
  submits the credential the server has already rejected.
- **Classifies the error.** Retry transport failures; stop on
  `authenticationError(.failedToAuthenticate)` and the `activationError` license cases.
- **Separates cancellation from failure.** `CancellationError` is a teardown, not an
  authentication failure, so it is not logged at error level.
- **Bounds every step, including the token fetch.** The SDK awaits this handler, so an
  unbounded `fetchToken` (for example a `URLSession` call behind a captive portal) stalls
  re-authentication. The worst case the user waits through is
  `attempts × (fetch + login)` plus backoff.

Without a retry, one failed attempt leaves the instance unauthenticated until the token
next expires, and sync stops. The awaited launch login is different: there is a caller and
a UI, so fail fast and offer a retry button instead.

`.development` is the development-token provider. Any other provider is named by string:
`DittoAuthenticationProvider("my-provider")`.

### Awaiting the first login

`login(token:provider:completion:)` is completion-based. Bridge it when launch should not
proceed until authentication resolves:

```swift
try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    ditto.auth?.login(token: token, provider: .development) { _, error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
```

Resume the continuation on **every** path, including the `ditto.auth == nil` path, or the
task hangs.

**Add a timeout before using this in an app.** If the completion never fires — an
unreachable server, a captive portal — the awaiting task stays suspended, and at launch
that becomes a watchdog termination. A task group does not solve this: a group waits for
every child, and a child suspended in `withCheckedThrowingContinuation` cannot be
cancelled, so the group still waits after the timeout child finishes.

Instead, have the deadline resume the **same** continuation, with a gate that admits
exactly one resumption, plus `withTaskCancellationHandler` so a cancelled caller is
released immediately. [`examples/minimal-app.md`](../examples/minimal-app.md) has a
complete, self-contained implementation.

### Status

`ditto.auth?.status` is a `DittoAuthenticationStatus` with `isAuthenticated` and
`userID`. `observeStatus(_:)` returns a `DittoObserver` you stop with `.stop()`, and
`DittoAuthenticator.StatusPublisher` is the Combine form. A
`Notification.Name.dittoAuthenticationStatusDidChange` notification is also posted.

`logout(cleanup:)` takes an optional closure that receives the `Ditto` instance after the
logout completes — the place to evict user data.

## CAP-05 Lifecycle: start/stop sync, shutdown, ownership

```swift
try ditto.sync.start()
ditto.sync.isActive     // true
ditto.sync.stop()
ditto.sync.isActive     // false
```

`sync.start()` throws; `sync.stop()` does not. This is the same on all four lines.

**`isActive` reports that sync was started, not that anything connected.** It is `true`
on an offline-only instance with every transport disabled. To find out whether a peer is
reachable, read the presence graph — see [presence.md](presence.md).

**Stopping sync does not close the store.** The local store stays fully readable and
writable after `sync.stop()`; only replication with other peers stops. Use it for a
"work offline" mode rather than tearing down the instance.

### Shutdown

There is no `close()`. A `Ditto` instance is released when its last strong reference goes
away, and releasing it is what frees the persistence directory lock.

**Hold one instance for the app's lifetime.** To switch users, call `auth.logout(cleanup:)`
and log in again on the same instance rather than releasing it and opening a new one.

**A failed startup must release the instance before retrying.** If `Ditto.open` succeeds
and a later step throws — activation, login, the first query — the instance is live and
holds the directory lock. A retry that reopens before every reference to it is dropped
fails with `storeError(.persistenceDirectoryLocked)`. Drop all references — including
local copies such as an `if let` binding — before the retry opens again.

### How release behaves

Two static properties control what happens when the last strong reference goes away:

- `Ditto.shouldWaitForCleanupOnClose` — whether deinit blocks until cleanup finishes.
  It is `false` in shipped SDK builds.
- `Ditto.deinitTimeoutSeconds` / `Ditto.deinitLogIntervalSeconds` — how long it waits and
  how often it logs while waiting.

If you set `shouldWaitForCleanupOnClose` to `true`, release the last reference off the
main thread; otherwise the main thread can block for up to `deinitTimeoutSeconds`.

### Ownership

`store`, `sync`, `presence`, `auth`, `smallPeerInfo` and `experimental` are
**aggregate children holding a weak reference to their parent**. Holding only
`ditto.store` does not keep `ditto` alive, and using an aggregate afterwards is a
`fatalError` on every supported line — except `store.registerObserver` and
`store.execute`, which throw `useAfterCloseError` on 4.14.6 only. See
[`SKILL.md`](../SKILL.md#object-lifetimes-and-retention) and
[versions.md](versions.md#use-after-the-owning-ditto-is-released).

Where the instance should live, per UI framework, is
[best-practices.md](../best-practices.md#instance-ownership).
