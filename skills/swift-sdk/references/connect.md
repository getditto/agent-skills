# Connecting, authentication and lifecycle — Ditto Swift SDK

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

Four details that cost a build or a support ticket if missed:

- **`databaseID` is spelled with an uppercase `ID`.** `databaseId` does not compile.
- **`.server(url:)` takes a `URL`, not a `String`.** A string literal does not compile.
- **The URL is the portal's *Connect via SDK* value copied verbatim** — an `https://`
  host. Do not build it from the database ID and do not substitute the `wss://` sync URL.
- **`persistenceDirectory` is a `URL?`.** `nil` means
  `<Application Support>/ditto-{databaseID}` with a fallback to the v4 location; see
  [versions.md](storage.md#default-persistence-directory).

### `open` versus `openSync`

| | Use when |
|---|---|
| `Ditto.open(config:)` — `async throws` | The composition root is already async: SwiftUI `.task`, an `async` app-model initializer, an `async` test. |
| `Ditto.openSync(config:)` — `throws` | A genuinely synchronous entry point that cannot await — a command-line tool, or a test helper. |

They produce the same instance.

**Do not call `openSync` on an iOS app's main thread.** It blocks while the store opens,
and that is unbounded: a large store, a cold flash cache, or 5.1's automatic index
migration can all take seconds. On the main thread of
`application(_:didFinishLaunchingWithOptions:)` that is a launch-watchdog termination
(`0x8badf00d`) that only reproduces on a real device with real data. Open Ditto
asynchronously and render a loading phase — the pattern in
[best-practices.md](../best-practices.md#instance-ownership). Also do not call `openSync`
from a cooperative-concurrency thread, where blocking starves the pool.

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

`ditto.isActivated` is `false` until that call succeeds (**executed**). An invalid token
throws `DittoError.activationError(.licenseTokenVerificationFailed(message:))`; an expired
one throws `.licenseTokenExpired`.

### One opened instance per persistence directory

Opening a second instance against a directory a live instance already holds fails
(**executed**), with this in the log:

> Multiple Ditto instances cannot run at the same time within the same working
> directory. Either use unique working directories for each instance, or consider
> managing your Ditto instance as a singleton instead.

The error is `DittoError.storeError(.persistenceDirectoryLocked(message:))`, added in
4.12.0 (`sdk/v4/release-notes/swift.mdx:413`) — **executed**, matching the case and not
merely "something threw". Releasing the first instance frees the directory —
**executed**: a second instance opened on the same directory afterwards read back what
the first had written.

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
ditto.auth?.expirationHandler = { ditto, _ in
    let token = await tokenStore.current()      // actor-owned, not UI state
    ditto.auth?.login(token: token, provider: .development) { _, error in
        if let error { print("Ditto login failed: \(error)") }
    }
}
try ditto.sync.start()
```

The handler runs off the main actor. It must not touch `@Published` properties, view
controllers or any other main-actor state directly — hop with `await MainActor.run { … }`
or a `Task { @MainActor in … }` if it needs to report status to the UI.

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
task hangs forever.

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

**Executed on all three lines.** `sync.start()` throws; `sync.stop()` does not.

**`isActive` reports that sync was started, not that anything connected.** It is `true`
on an offline-only instance with every transport disabled. To find out whether a peer is
actually reachable, read the presence graph — see [presence.md](presence.md).

**Stopping sync does not close the store.** The local store stays fully readable and
writable after `sync.stop()` (**executed**); only replication with other peers stops.
That is the switch to use for a "work offline" mode, not tearing down the instance.

### Shutdown

There is no `close()`. A `Ditto` instance is released when its last strong reference goes
away, and releasing it is what frees the persistence directory lock.

**Releasing a server-backed instance shortly after it authenticates can abort the
process.** Observed on 5.1.0 in roughly one run in four:

```
Panic: Attempted to submit auth request after the Ditto instance was closed
   1: ditto_shutdown::until_shutdown::UntilShutdown<T>::borrow_to
   2: ditto_auth::client::AuthClientInner<BS>::login::{{closure}}
```

This is a race inside the SDK's auth client between an in-flight login and shutdown, not
an ordering an app can guarantee its way out of. The sequence below avoided it in every
run tried (11 of 11, against 2 of 8 without it), and is what to do when you must release
a server-backed instance:

```swift
ditto.auth?.expirationHandler = nil   // stop new logins being submitted
ditto.auth?.logout()
try? await Task.sleep(nanoseconds: 500_000_000)  // let the auth client settle
ditto.sync.stop()
ditto = nil                            // now the directory lock is free
```

In practice this mostly affects tests and short-lived command-line tools. A real app
holds its instance for the whole process lifetime and never hits it.
 Two static knobs
control how that release behaves:

- `Ditto.shouldWaitForCleanupOnClose` — whether deinit blocks until cleanup finishes.
- `Ditto.deinitTimeoutSeconds` / `Ditto.deinitLogIntervalSeconds` — how long it waits and
  how often it logs while waiting.

These are not neutral knobs. If the last strong reference is released **on the main
thread** — which is the normal case for a `@MainActor` app model — a blocking deinit is a
main-thread hang for up to `deinitTimeoutSeconds`. Release the instance off the main
actor, or accept the pause deliberately.

### Ownership

`store`, `sync`, `presence`, `auth`, `diskUsage`, `smallPeerInfo` and `experimental` are
**aggregate children holding a weak reference to their parent**. Holding only
`ditto.store` does not keep `ditto` alive, and using it afterwards is a `fatalError` on
v5 — see [`SKILL.md`](../SKILL.md#object-lifetimes-and-retention) and
[versions.md](versions.md#use-after-the-owning-ditto-is-released-v5-is-strictly-worse).

Where the instance should live, per UI framework, is
[best-practices.md](../best-practices.md#instance-ownership).
