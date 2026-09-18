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
  [storage.md](storage.md#default-persistence-directory).

### `open` versus `openSync`

`Ditto.open` wraps the synchronous `Ditto(config)` initializer in a continuation and
resumes it inline, with no suspension point inside the closure:

```swift
public static func open(config: DittoConfig = .default) async throws -> Ditto {
    // REFACTOR: asyncify properly at the FFI level.
    return try await withCheckedThrowingContinuation { continuation in
        do { let ditto = try Ditto(config); continuation.resume(returning: ditto) }
        catch { continuation.resume(throwing: error) }
    }
}
```

Identical on all three lines: `sdk-release-4.14.6:cocoa/DittoSwift/Ditto.swift:56-66`,
`sdk-release-5.0.3:sdks/cocoa/DittoSwift/Ditto.swift:115-125`,
`sdk-release-5.1.0:sdks/swift/DittoSwift/Ditto.swift:115-124`.

**That does not mean it runs on your actor.** `open` is declared **nonisolated**, and a
nonisolated `async` function does not inherit the caller's executor
([SE-0338](https://github.com/apple/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md));
it hops to the cooperative pool. All three shipped frameworks are built with a Swift 6
compiler, so the rule applies on every line — check any of them with
`head -2 DittoSwift.framework/Modules/DittoSwift.swiftmodule/*.swiftinterface`.

| | Use when |
|---|---|
| `Ditto.open(config:)` — `async throws` | Anywhere you can `await`. This is the default, and it is safe on the main actor. |
| `Ditto.openSync(config:)` — `throws` | A genuinely synchronous entry point — a command-line tool, or a test helper. |

**`await Ditto.open(...)` from `@MainActor` does not block the main thread. Calling
`Ditto.openSync(...)` there does.** Measured on 5.1.0 with a 5 ms main-queue timer
recording how long the main thread went unresponsive (**executed**):

| Call, from `@MainActor` | Open took | Main thread blocked |
|---|---|---|
| `await Ditto.open(config:)` | 59-203 ms | 6 ms — the timer interval; not blocked |
| `Ditto.openSync(config:)` | 48-67 ms | equal to the open, every run |

Opening is unbounded — a large store, a cold flash cache, or 5.1's automatic index
migration can all take seconds — so on the main thread of
`application(_:didFinishLaunchingWithOptions:)` `openSync` is a launch-watchdog
termination (`0x8badf00d`) that only reproduces on a real device with real data. Use
`await` and render a loading phase, the pattern in
[best-practices.md](../best-practices.md#instance-ownership).

**Do not reach for `Task.detached` here.** It schedules on the same cooperative pool
`open` already uses, so it moves nothing; it only costs you a `Sendable` warning on
4.14.x, where `Ditto` predates the conformance. What `open` *does* occupy for the
duration is one cooperative-pool thread. That matters only if you open many instances at
once — and if you must, get off the pool properly rather than deeper into it:

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
    do {
        try await Retry.run(
            attempts: 3,
            firstBackoffSeconds: 2,
            isRetryable: AuthCoordinator.isRetryable,
            onFailure: { attempt, error, nextDelay in
                let next = nextDelay.map { "retrying in \($0)s" } ?? "giving up"
                logger.warning("Ditto re-auth attempt \(attempt) failed (\(next)): \(error)")
            }
        ) {
            // INSIDE the closure. The handler runs because the token expired, so
            // hoisting the fetch out re-submits the same dead credential three times.
            let token = try await fetchToken()          // your backend, not UI state
            try await login(ditto, token: token, timeoutSeconds: 15)
        }
    } catch is CancellationError {
        logger.debug("Ditto re-authentication cancelled")   // a teardown, not a failure
    } catch {
        logger.error("Ditto re-authentication gave up: \(error.localizedDescription)")
    }
}
try ditto.sync.start()
```

`Retry` and `AuthCoordinator` are in `tests/swift-sdk/Sources/UIPatterns/`; `login` is the
bounded bridge below. The handler runs off the main actor and must not touch `@Published`
properties, view controllers or any other main-actor state directly — hop with
`await MainActor.run { … }` or a `Task { @MainActor in … }` to report status to the UI.

Four things that sample is doing deliberately:

- **Fetch the token inside the retry.** Nothing else calls this handler until the token
  next expires. Fetching once outside means all three attempts submit the credential the
  server has already rejected.
- **Classify the error.** A rejected credential or an expired license is a verdict, not a
  blip: retrying spends the whole budget to reach the answer you already had. Retry
  transport failures; stop on `authenticationError(.failedToAuthenticate)` and the
  `activationError` license cases.
- **Separate cancellation from failure.** `CancellationError` is a teardown. Logging it at
  error level puts a spurious auth failure in every sysdiagnose taken after a clean exit.
- **Bound everything inside, including the token fetch.** The SDK *awaits* this handler, so
  an unbounded `fetchToken` — a `URLSession` call behind a captive portal — parks
  re-authentication permanently on the first attempt, and no retry budget saves you. Bound
  the fetch as well as the login: `attempts × (fetch + login)` plus backoff is the real
  worst case, and it is what the user waits through.

Retrying at all is the point: one attempt lost to a captive portal leaves the instance
unauthenticated for the rest of the session — sync stops and nothing reports why. The
awaited launch login is the opposite case, and `AuthCoordinator.login(_:)` deliberately
does **not** retry: there is a caller and a UI, so fail fast and offer a button.

`AuthCoordinator` and `Retry` in `tests/swift-sdk/Sources/UIPatterns/` are the worked
form. `Retry` is **executed**, including that a cancelled caller is released during the
backoff instead of running out its remaining attempts.

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

**That bridge is not enough on its own, and must not be shipped as written.** It is
neither bounded nor cancellable: if the completion never fires — unreachable server,
captive portal, DNS black hole — the awaiting task suspends forever, and at launch that
is an iOS watchdog termination. A task group does **not** fix it: a group does not return
until every child finishes, and a child suspended in `withCheckedThrowingContinuation` is
not cancellable, so the timeout child produces an error and the group then blocks forever
waiting for its sibling (measured: a 2-second timeout still blocked after 8 seconds).

The deadline has to resume the **same** continuation, with a gate admitting exactly one
resumption, plus a `withTaskCancellationHandler` so a cancelled caller is released rather
than waiting out the full timeout. The complete, tested implementation is `Deadline` in
`tests/swift-sdk/Sources/UIPatterns/`, and
[`examples/minimal-app.md`](../examples/minimal-app.md) carries a self-contained copy.

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

**A failed startup must still release the instance, not on the main actor, and the retry
must wait for that release.** If `Ditto.open` succeeds and a later step throws —
activation, login, the first query — the instance is live and holding the directory lock,
so a retry that reopens before it is released fails with
`storeError(.persistenceDirectoryLocked)`. Dropping that last reference from a `@MainActor`
error path is also the debug-build stall described below, and that stall is what makes the
window wide: `shouldWaitForCleanupOnClose` is `true` in debug, so the release blocks on SDK
cleanup for up to `Ditto.deinitTimeoutSeconds` (10). Three things have to be true:

```swift
// 1. A box carries the instance across, so the LAST release happens off this actor.
private final class Handoff: @unchecked Sendable {
    private let lock = NSLock()
    private var ditto: Ditto?
    init(_ ditto: Ditto?) { self.ditto = ditto }
    func clear() { lock.lock(); ditto = nil; lock.unlock() }
}

// 2. Hand off, THEN drop this actor's own reference — `if let failed = opened` would
//    leave a second strong reference here whose release could be the final one.
let handoff = Handoff(opened)
opened = nil
releaseTask = Task.detached { handoff.clear() }

// 3. The next open awaits it. Without this the Retry button races the release.
if let releaseTask { await releaseTask.value; self.releaseTask = nil }
```

`DittoLoader` in `tests/swift-sdk/Sources/UIPatterns/CarListView.swift` is the worked form.
It is compiled on every platform and version but **not executed** — see the "Not verified"
list in [`README.md`](../README.md).

**Releasing a server-backed instance shortly after it authenticates can abort the
process.** Observed on 5.1.0 in roughly one run in four:

```
Panic: Attempted to submit auth request after the Ditto instance was closed
   1: ditto_shutdown::until_shutdown::UntilShutdown<T>::borrow_to
   2: ditto_auth::client::AuthClientInner<BS>::login::{{closure}}
```

This is a race inside the SDK's auth client between an in-flight login and shutdown.
**No ordering reliably avoids it.** Clearing the handler, calling `logout()` and pausing
before release all reduce the frequency — one measurement went from 2 aborts in 8 runs to
0 in 11 — but the same sequence later aborted a test process anyway. Treat it as an SDK
defect to report, not as something to engineer around.

What *does* avoid it is not releasing the instance at all:

```swift
ditto.auth?.expirationHandler = nil   // stop new logins being submitted
exit(0)                                // terminates without running deinitializers
```

**`exit(0)` is for command-line tools and test harnesses only.** Never call `exit()` from
an iOS or macOS app: it skips `applicationWillTerminate`, reads to the user as a crash,
and is an App Store rejection. The reason it works here is that it does what normal
process termination does — an app holds its instance for the whole process lifetime and
never deinitializes Ditto on the way out either.

**In an app there is no safe workaround on 5.1.0.** The exposed flow is
logout-and-sign-in-as-a-different-user: it releases a server-backed instance
mid-process, which is exactly the case. Hold the instance and re-authenticate in place
rather than releasing and reopening.

This is listed under "Not verified" in [`README.md`](../README.md): it is a race, and a
race that does not reproduce is not a race that is fixed.

### How release behaves

Two static properties control what happens when the last strong reference goes away:

- `Ditto.shouldWaitForCleanupOnClose` — whether deinit blocks until cleanup finishes.
- `Ditto.deinitTimeoutSeconds` / `Ditto.deinitLogIntervalSeconds` — how long it waits and
  how often it logs while waiting.

`shouldWaitForCleanupOnClose` defaults to **`true` in debug builds and `false` in
release** (`sdk-release-5.1.0:sdks/swift/DittoSwift/Ditto.swift:190-192`), so a shipped
app does not block unless you set it. In debug, though, releasing the last strong
reference **on the main thread** — the normal case for a `@MainActor` app model — is a
main-thread hang for up to `deinitTimeoutSeconds`. Release off the main actor, or accept
the pause deliberately.

### Ownership

`store`, `sync`, `presence`, `auth`, `diskUsage`, `smallPeerInfo` and `experimental` are
**aggregate children holding a weak reference to their parent**. Holding only
`ditto.store` does not keep `ditto` alive, and using an aggregate afterwards is a
`fatalError` on every supported line — except `store.registerObserver` and
`store.execute`, which throw `useAfterCloseError` on 4.14.6 only. See
[`SKILL.md`](../SKILL.md#object-lifetimes-and-retention) and
[versions.md](versions.md#use-after-the-owning-ditto-is-released).

Where the instance should live, per UI framework, is
[best-practices.md](../best-practices.md#instance-ownership).
