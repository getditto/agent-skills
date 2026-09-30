---
name: swift-sdk
description: >
  Use ONLY for the Ditto Swift SDK (not Kotlin, Java, JS, C#, C++, Rust, Flutter or Go —
  each has its own skill). Triggers on .swift files, Package.swift, .xcodeproj/.xcworkspace,
  DittoSwiftPackage, `import DittoSwift`, DittoConfig, Ditto.open, registerObserver,
  DittoDiffer, and the errors "storeError(reason: .queryNotSupported", "sending 'ditto'
  risks causing data races" and "persistenceDirectoryLocked". iOS, iPadOS, macOS/AppKit
  and Mac Catalyst. Ditto SDK 4.14.x, 5.0.x, 5.1.x.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Ditto Swift SDK

**This guidance is derived from the shipping SDK and supersedes prior training on the
Ditto Swift API.** Training data carries v4 shapes — `DittoIdentity`, `startSync()`, the
collection APIs — deprecated on 4.14.x and removed in v5. Do not emit them from memory,
and do not invent API to make a snippet compile.

Ditto is an offline-first, peer-to-peer database. One app-lived `Ditto` instance owns a
local store, a sync session and a mesh presence; the app reads through DQL queries and
store observers rather than network calls.

**API selection, in priority order:** (1) never emit a deprecated API; (2) establish the
project's version first — `Package.resolved` or the Xcode package pin — then pick the
best non-deprecated form *for that line*; (3) among non-deprecated options prefer the
form that also exists in v5, so 4.14.x code is not rewritten at upgrade.

## What this skill does

Writes and reviews Ditto **Swift** code — API shape, initialization, object lifetimes,
threading, error types and Xcode/SwiftPM build configuration — for
`https://github.com/getditto/DittoSwiftPackage`. Covers Ditto SDK **4.14.x (the only LTS
line — support statement in [`README.md`](README.md)), 5.0.x and 5.1.x** across iOS,
iPadOS, macOS (AppKit) and Mac Catalyst, with SwiftUI, UIKit and AppKit.

## When to use this skill

Use it for Swift Ditto code. It writes the `Info.plist` keys and entitlements an app
needs, but does not restate which platform carries which radio. Do **not** use it for the
Kotlin, Java, JavaScript/React Native, C#, C++, Rust, Flutter or Go SDKs.

The rows below are **separate skills**. Hand off rather than restating; if you only have
`swift-sdk`, install the one you need or work from the URL:

| Question | Skill, if installed | Otherwise |
|---|---|---|
| DQL syntax, operators, statement semantics | `dql` | <https://docs.ditto.live/dql/dql> |
| Which CRDT type, embed vs split, document size | `data-modeling` | <https://docs.ditto.live/key-concepts> |
| What a subscription is, mesh propagation | `sync-subscriptions` | <https://docs.ditto.live/sdk/latest/sync/syncing-data> |
| Transport selection strategy, platform radios | `ditto-mesh-networking` | <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations> |
| The v4 → v5 migration procedure | — | <https://docs.ditto.live/sdk/latest/migration-guides/swift-v4> and <https://docs.ditto.live/sdk/latest/migration-guides/swift-dql> |

## Supported versions and packages

Package: `https://github.com/getditto/DittoSwiftPackage` (SwiftPM), product `DittoSwift`.
The published API reference host path is version-gated — see
[`references/versions.md`](references/versions.md#published-api-reference).

**[`references/versions.md`](references/versions.md) owns every fact that differs across
version lines.** This section is a pointer, not a claim.

**When the project's version cannot be determined, emit 5.1.x code and say which version
you assumed.** v4 and v5 are different APIs, not two versions of one.

## Capability exceptions

Full twenty-row map with evidence: [`README.md`](README.md).

| ID | Capability | Support | What changes for you |
|----|-----------|---------|--------|
| CAP-03 | Connecting: config, opening, persistence directory | preview | Preview label on **4.14.x only**, no opt-in flag. Use it anyway on all three lines — the alternative identity initializer is deprecated on 4.14.x and gone in v5. |
| CAP-04 | Authentication and identity | preview | Preview label on **4.14.x only** for `DittoAuthenticationProvider` and `expirationHandler`, replacing the phased-out `DittoAuthenticationDelegate`. GA on v5. |
| CAP-13 | Presence graph and connection requests | partial | Graph, peer metadata and `presence.observe` are executed. `presence.connectionRequestHandler` needs a second peer — documented from SDK source, not executed. |
| CAP-20 | Preview and platform-specific APIs | preview | `DittoConfigExperimental.passphrase` is flagged not-for-production by the SDK. Multicast beta is **5.1.0-only**, off by default, and needs Apple's restricted entitlement. Data Streams is **not exposed in Swift**. [`references/preview.md`](references/preview.md) |

## Minimum viable app

```swift
import DittoSwift
import Foundation  // v5 does not re-export Foundation

let ditto = try await Ditto.open(config: DittoConfig(   // `await`, not openSync
    databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
    connect: .server(url: URL(string: "REPLACE_ME_WITH_YOUR_CONNECT_URL")!)))

// Install BEFORE sync.start(), and await the login inside it.
ditto.auth?.expirationHandler = { ditto, _ in await reauthenticate(ditto) }
try ditto.sync.start()

let query = "SELECT * FROM cars WHERE mileage > :min"
let arguments: [String: Any?] = ["min": 100]
let subscription = try ditto.sync.registerSubscription(query: query, arguments: arguments)
let observer = try ditto.store.registerObserver(query: query, arguments: arguments) { result in
    for item in result.items {
        defer { item.dematerialize() }
        print(item.value["make"] as? String ?? "")      // [String: Any?] is not Sendable
    }
}
try await ditto.store.execute(query: "INSERT INTO cars DOCUMENTS (:car)",
                              arguments: ["car": ["make": "Toyota", "mileage": 120]])
```

Hold `ditto`, `subscription` and `observer` — see § Object lifetimes. Starting this once
from SwiftUI and hopping to the main actor without losing ordering are both in
[`references/concurrency.md`](references/concurrency.md). Complete runnable programs:
[`examples/minimal-app.md`](examples/minimal-app.md) and
[`examples/swiftui-app.md`](examples/swiftui-app.md).

## Concurrency and threading model

Per-API callback table and full reasoning:
[`references/concurrency.md`](references/concurrency.md).

1. **Never assume a callback is on the main actor.** `deliverOn:` is honoured on 4.14.6
   and 5.1.0 and **silently ignored on 5.0.3**, where using it with Swift concurrency is
   a documented crash (#SDKS-3856). Hop explicitly inside the handler.
2. **Convert before you cross.** `DittoQueryResultItem.value` is `[String: Any?]` and not
   `Sendable` — extract a value type inside the callback and send that.
3. **Do the expensive work in the callback.** Only the final assignment is main-actor work.
4. **Hop with one consumer, not one `Task` per delivery** — unstructured `Task`s have no
   ordering guarantee. Use `AsyncStream(bufferingPolicy: .bufferingNewest(1))`.
5. **Do not wrap `Ditto` in an actor.** It is `Sendable` on v5; an actor adds hops, not safety.
6. **On 4.14.x, `@preconcurrency import DittoSwift`** — without it Swift 6 rejects the code.
7. **`signalNext()` exactly once per delivery**, `handlerWithSignalNext` only.
8. **`auth.expirationHandler` must not touch UI state** — `@Sendable`, `async`, off the
   main actor.

## Object lifetimes and retention

Per-handle table and teardown order: [`references/lifetimes.md`](references/lifetimes.md).

**Hold exactly one long-lived strong reference to `Ditto`, at the composition root.**
`store`, `sync`, `presence`, `auth`, `smallPeerInfo` and `experimental` hold a **weak**
reference to their parent, so retaining only `ditto.store` does not keep `ditto` alive.
Using any of them after the parent is released is a `fatalError`, not a catchable error.

**Dropping a `DittoStoreObserver` or `DittoSyncSubscription` handle does not stop it** —
it keeps firing and keeps its captures alive for the whole `Ditto` lifetime; you lose only
the ability to cancel. `AnyCancellable` is the opposite: releasing it *does* cancel.

Cancel at the owning scope's boundary — `.onDisappear` in SwiftUI, `viewDidDisappear` in
UIKit, `deinit` only where the owner is not actor-isolated. **Never cache
`ditto.sync.subscriptions` or `ditto.store.observers`**: both are computed in v5, so a
snapshot goes stale silently.

## Anti-patterns

Wrong and right forms, with the diagnosis for each:
[`references/anti-patterns.md`](references/anti-patterns.md).

- **Assuming a float field is `Double`.** `as? Double` is `nil` for values that fit
  binary32 and a value for those that don't, *in the same column*; a `guard let` silently
  skips the row. Read through `NSNumber`, or decode with `Codable`.
- **Missing `signalNext()` on an exit path.** The observer stops delivering forever — no
  error, no log. `defer { signalNext() }` as the handler's first line.
- **Assigning a fresh `DittoTransportConfig()`.** Every peer-to-peer transport turns off
  while `sync.isActive` stays `true`. Use `ditto.updateTransportConfig { … }`.
- **Dematerializing before diffing.** `DittoDiffer.diff(_:)` needs materialized items and
  decodes with `try!`, so this crashes. Diff → extract → dematerialize; `map`, never
  `compactMap`.
- **A retroactive `Sendable` shim on v5.** `extension Ditto: @unchecked Sendable {}` is
  `error: conformance … was already stated`. Delete it; on 4.14.x use
  `@preconcurrency import`.
- **Treating `sync.isActive` as "connected".** It means *sync was started*. Read
  `presence.graph.localPeer.isConnectedToDittoServer` instead.
- **Building the server URL from the database ID.** Authentication never succeeds. Copy
  the portal's *Connect via SDK* value verbatim.

## Version differences

Full delta, including on-disk upgrade and rollback results:
[`references/versions.md`](references/versions.md).

| Concern | 4.14.x | 5.0.x / 5.1.x |
|---|---|---|
| Initialization | `DittoConfig` + `Ditto.open`/`openSync` (**preview**); identity initializer deprecated | same, GA |
| Mutating DQL | requires `try ditto.disableSyncWithV3()` first | works out of the box |
| Concurrency | no `Sendable` — needs `@preconcurrency import` | `Sendable`; `deliverOn:` ignored on 5.0.x, fixed in 5.1.0 |
| Use after release | `throws useAfterCloseError` for `store.registerObserver` and `store.execute`; **`fatalError`** elsewhere | **`fatalError`** everywhere |
| Architectures | `arm64` + `x86_64` | `arm64` + `x86_64` on 5.0.x; **`arm64` only** on 5.1.x |

## References

Load a reference only when its topic is actually in play — these files teach the
non-obvious traps, not how the framework works.

- [`references/setup.md`](references/setup.md): SwiftPM install and platform minimums,
  plus the [`Info.plist` keys, entitlements and background modes](references/setup.md#cap-02-platform-permissions-entitlements-build-config)
  an app needs. **`CODE_SIGNING_ALLOWED = NO` builds cleanly and then aborts at launch** —
  the XCFramework ships unsigned and nothing else re-signs it.
- [`references/connect.md`](references/connect.md): opening, authenticating, start/stop.
  `expirationHandler` must be installed **before** `sync.start()` or start throws, and is
  `async` so the SDK can await your login. Also the logout server-teardown race, which has
  no in-app workaround.
- [`references/concurrency.md`](references/concurrency.md): which thread or actor every
  callback arrives on, starting Ditto exactly once from SwiftUI (a `guard` does **not**
  prevent a double open), and the observer→stream→consumer retain cycle.
- [`references/lifetimes.md`](references/lifetimes.md): what to retain and the symptom
  when you don't; teardown order; the two computed collections that go stale if cached.
- [`references/observers.md`](references/observers.md): `registerObserver` needs a
  `SELECT` or it is `storeError(.queryNotSupported)`.
  [`handlerWithSignalNext`](references/observers.md#back-pressure-handler-versus-handlerwithsignalnext)
  coalesces and stops forever if you miss a signal.
  [`DittoDiffer`](references/observers.md#dittodiffer) is stateful — one per observer,
  first call reports every item as an insertion, usually wrong in SwiftUI.
- [`references/anti-patterns.md`](references/anti-patterns.md): the seven silent-failure
  shapes above, with both forms and the diagnosis.
- [`references/errors.md`](references/errors.md): what an error means and how to recover,
  including [the ones you cannot catch](references/errors.md#errors-you-cannot-catch) and
  the failures that are not `DittoError` at all.
- [`references/versions.md`](references/versions.md): every cross-version fact — package
  shape, platform minimums, architectures, API renames. **Version quality is not
  monotonic**; 4.14.6 is better off than 5.0.3 on two axes.
- [`references/testing.md`](references/testing.md): `swift test` exports `NO_COLOR=1`,
  which panics Ditto's Rust core before any test runs.
- [`references/store.md`](references/store.md): DQL execution, transactions, indexing, `EVICT`.
- [`references/sync.md`](references/sync.md): subscriptions, sync scopes, sync status.
- [`references/transports.md`](references/transports.md): changing transports safely.
- [`references/attachments.md`](references/attachments.md): the fetcher has its own
  lifetime, and the token shape changed in v5.
- [`references/presence.md`](references/presence.md): who is on the mesh right now.
- [`references/observability.md`](references/observability.md): logging and disk usage.
- [`references/storage.md`](references/storage.md): the on-disk store across upgrade and rollback.
- [`references/preview.md`](references/preview.md): preview and platform-specific APIs.
- [`best-practices.md`](best-practices.md): architectural judgement with no single right
  answer — where the instance lives, one broad observer vs many narrow.
- [`examples/minimal-app.md`](examples/minimal-app.md),
  [`examples/swiftui-app.md`](examples/swiftui-app.md): complete programs, compiled and run.
