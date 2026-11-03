# Versions — Ditto Swift SDK

## Contents

- [Identify the version in use](#identify-the-version-in-use)
- [4.14.x](#414x)
- [5.0.x](#50x)
- [5.1.x](#51x)
- [All lines](#all-lines)
  - [5.2.0 and Data Streams](#520-and-data-streams)
- [Cross-version reference](#cross-version-reference)
- [CAP-19 v4 to v5 migration, API and on-disk store](#cap-19-v4-to-v5-migration-api-and-on-disk-store)

**This file owns every fact that differs between 4.14.x, 5.0.x and 5.1.x.** Every other
file in this skill shows the 5.1.x form and links here. Covered releases: **4.14.6**,
**5.0.3**, **5.1.0**.

---

## Identify the version in use

Read the pin before writing any Ditto code:

- **Xcode project:** the `DittoSwiftPackage` entry in
  `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, or
  *Package Dependencies* in the project navigator.
- **SwiftPM package:** the `.package(url: "https://github.com/getditto/DittoSwiftPackage", …)`
  requirement in `Package.swift`, and the resolved version in `Package.resolved`.
- **At runtime:** `Ditto.version` returns the linked SDK version string.

**When the version cannot be determined, emit 5.1.x code and say so.**

| Line | Status | What to check first |
|---|---|---|
| [4.14.x](#414x) | LTS. Pin **4.14.6**. | `disableSyncWithV3()` before mutating DQL; no `Sendable` conformances |
| [5.0.x](#50x) | Supported. Pin **5.0.3**. | `deliverOn:` is ignored — hop explicitly in observer handlers |
| [5.1.x](#51x) | Current. Pin **5.1.0**. | `arm64` only; 5 MiB per-document limit |

---

## 4.14.x

### API surface on 4.14.x

- **Opening:** `DittoConfig` + `Ditto.open(config:)` is labelled *preview* on this line,
  while the `Ditto(identity:persistenceDirectory:)` path is *deprecated*. Use the config
  path anyway: it is the recommended initialization path on 4.14.x and the only path in
  v5. Never emit `DittoIdentity`, `startSync()` / `stopSync()` or the other deprecated
  members listed in [Initialization and lifecycle](#initialization-and-lifecycle).
- **Activation state:** `ditto.isActivated` does not exist; `ditto.activated` is present
  and deprecated.
- **Concurrency:** no public type is `Sendable`. See
  [below](#sendable-conformances-v4-has-none).
- **Package:** two products, `DittoSwift` and `DittoObjC`. `DittoSwift` re-exports
  `Foundation`.
- **Attachments:** `DittoAttachmentToken` is public and is what a query result carries;
  `newAttachment(data:metadata:)` does not exist (file path only).
- **Disk usage:** `DiskUsage` / `DiskUsageItem` / `.exec` and the nested
  `DiskUsageObserverHandle`.
- **Logging:** `DittoLogger.isEnabled`, with `enabled` as a deprecated alias.
- **HTTP listener:** `DittoHTTPListenConfig.webSocketSync` defaults to `true`.
- **Platforms:** iOS 14, macOS 11, Mac Catalyst 14, tvOS 14; `x86_64` slices ship.
- **Presence and Combine** names differ from v5 — see
  [api-compatibility.md](api-compatibility.md).

### 4.14.x refuses mutating DQL until `disableSyncWithV3()` is called

`SELECT` works; the first mutating statement throws:

```
DittoError.storeError(reason: .queryNotSupported(message:
  "<dql> Unsupported feature: Encountered `INSERT` statement. Mutating DQL statements
   require that your application is updated to the latest version. Please configure your
   app to disable sync with V3 to use DQL"))
```

```swift
// 4.14.x only. Not needed, and not available, on 5.0.x or 5.1.x.
let ditto = try await Ditto.open(config: config)
try ditto.disableSyncWithV3()
try ditto.sync.start()
```

Call it before `sync.start()`, in both connect modes. It is **irreversible** and
propagates to every peer the device syncs with. It is deprecated on this line and still
required; it is the one deprecated API this skill emits.

### `Sendable` conformances: v4 has none

Compiling v5-shaped code against 4.14.x in Swift 6 language mode fails with
`error: sending 'ditto' risks causing data races` (and the same for `ditto.store`). Use
`@preconcurrency import DittoSwift` on this line. Do **not** add retroactive
`extension Ditto: @unchecked Sendable {}` shims: on v5 they fail with
`error: conformance of 'Ditto' to protocol 'Sendable' was already stated in the type's
module 'DittoSwift'`.

### Known issues on 4.14.x

| Issue | Affects | What to do |
|---|---|---|
| Regression in 4.14.5 (per the v4 release notes) | 4.14.5 | Pin 4.14.6. Never recommend 4.14.5. |
| mDNS advertised and browsed with incorrect information, so LAN discovery fails | before 4.14.3 | Upgrade to 4.14.6. |
| Use after the owning `Ditto` is released: `store.registerObserver` / `store.execute` throw `useAfterCloseError`; every other aggregate call is a `fatalError` | 4.14.6 | Keep the `Ditto` instance alive for as long as anything uses it — see [Use after release](#use-after-the-owning-ditto-is-released). |

### Best practice on 4.14.x

- Pin exactly `4.14.6`.
- Open with `Ditto.open(config:)`, call `disableSyncWithV3()`, then `sync.start()`.
- `@preconcurrency import DittoSwift` in Swift 6 language mode.
- Hop to the main actor inside observer handlers instead of relying on `deliverOn:`, so
  the same code is correct after upgrading to 5.0.x — see [observers.md](observers.md).
- tvOS apps stay on 4.14.x; no v5 line supports tvOS.

---

## 5.0.x

### API surface on 5.0.x

Changes from 4.14.x:

- **Removed:** the identity initializer, `DittoIdentity`, `startSync()` / `stopSync()`,
  `ditto.activated`, `appID`, `siteID`, `persistenceDirectory`, `disableSyncWithV3()`,
  `runGarbageCollection()`, `transportDiagnostics()`, `isHistoryTrackingEnabled`. Full
  replacements in [Initialization and lifecycle](#initialization-and-lifecycle).
- **Added:** `ditto.isActivated`; `newAttachment(data:metadata:)`.
- **`Sendable`:** most public types, including `Ditto` and `DittoStore`, are `Sendable`.
  `DittoAuthenticationExpirationHandler` and `DittoConnectionRequestHandler` are
  `@Sendable`; the observer handler aliases are not yet — see
  [`@Sendable` closure aliases](#sendable-closure-aliases-two-arrive-in-50-the-rest-in-510).
- **Package:** one product, `DittoSwift`. `Foundation` is no longer re-exported — add
  `import Foundation`. Re-pinning an Xcode target from 4.14.x leaves a stale `DittoObjC`
  reference; remove it from the target.
- **Attachments:** `DittoAttachmentToken` is not public; a query result carries the token
  as `[String: Any]`.
- **Renamed:** `DittoDiskUsage` / `DittoDiskUsageItem` / `.item`, and the standalone
  `DittoDiskUsageObserver`. `DittoDiskUsageItem`'s property names are unchanged.
- **Defaults:** `DittoHTTPListenConfig.webSocketSync` defaults to `false`.
- **Deprecated:** `DittoError.transportError` / `TransportErrorReason`.
- **Platforms:** iOS 15, macOS 12, Mac Catalyst 15. tvOS is no longer supported, although
  a tvOS slice still ships in the 5.0.3 binary — do not target it.

### `deliverOn:` is ignored on 5.0.x

`registerObserver(deliverOn:)` accepts a queue on 5.0.x but does not deliver on it.
Handlers run on an SDK queue. Handler code that passes `deliverOn: .main` and then touches
main-actor state is correct on 4.14.x and 5.1.x and fails on 5.0.x; the 5.1 changelog
describes the fix as *"resolving a crash when used with Swift concurrency"*.

**Write code that does not depend on it:** hop explicitly inside the handler, and the
same source is correct on all three lines — see [observers.md](observers.md).

### Known issues on 5.0.x

| Issue | Fixed in | What to do |
|---|---|---|
| `deliverOn:` is ignored (above) | 5.1.0 | Hop to the main actor inside the handler. |
| An uncaught exception thrown inside an SDK callback is reported as a `SIGABRT` attributed to Ditto rather than with the original call stack | 4.14.6, 5.1.0 | Catch errors inside callbacks; upgrade to 5.1.x for readable reports. |
| A custom `DITIdentityProvider` stalls the SDK on the first credential refresh | 5.1.0 | Upgrade to 5.1.x if the app uses a custom identity provider. |
| Use after the owning `Ditto` is released is a `fatalError` on every aggregate, including `store.registerObserver` and `store.execute` | not changed | Keep the `Ditto` instance alive — see [Use after release](#use-after-the-owning-ditto-is-released). |

### Best practice on 5.0.x

- Pin exactly `5.0.3`; prefer 5.1.x for new work.
- Hop explicitly in every observer handler.
- `import Foundation` alongside `import DittoSwift`.

---

## 5.1.x

### API surface on 5.1.x

Changes from 5.0.x:

- **`@Sendable` observer aliases:** `DittoStoreObservationHandler`,
  `DittoStoreObservationHandlerWithSignalNext` and `DittoSignalNext` are `@Sendable`.
- **`deliverOn:` is honoured** again.
- **Added:** `DittoConnectionType.multicast` and `DittoMulticastBetaConfig` (beta — see
  [preview.md](preview.md)); `ADVISE` / `ADVISE AND PROVISION` through `store.execute`
  (a parse error on earlier lines).
- **Deprecated and no longer produced:** the `CBOR` enum,
  `DittoError.StoreErrorReason.invalidDocumentStructure(cbor:)` and
  `.nonStringKeyInDocument(key:)`. Do not write recovery code for them.
- **Removed:** tvOS. `DittoPeerOS.tvOS` is deprecated but retained so older tvOS peers
  stay identifiable in the presence graph.
- **Architectures:** `arm64` only — see
  [Shipped XCFramework slices](#shipped-xcframework-slices).
- **API reference host** moved from `/cocoa/` to `/swift/` — see
  [Published API reference](#published-api-reference).
- **On-disk index format** changed — see [storage.md](storage.md).

### The 5 MiB per-document limit is new in 5.1.0

5.1.x rejects a document larger than 5 242 880 bytes. 4.14.x and 5.0.x accept documents of
that size, so an app that writes them works on 5.0.x and starts failing after upgrading:

```
DittoError.unknownError(message: "<dql> Query failed: `DQL Internal execution error:
  Insert failed: <store> Document `_id = \"oversized\"` size is 5243057 bytes and
  exceeds limit of 5242880 bytes`. …")
```

The error case is `unknownError`, **not** `validationError(.sizeLimitExceeded)` — match on
the message, not the case. Documents should be far smaller than the limit anyway; see the
`data-modeling` skill or <https://docs.ditto.live/key-concepts>.

### Known issues on 5.1.x

| Issue | What to do |
|---|---|
| No `x86_64` slice: Intel Macs cannot build or run macOS, iOS Simulator or Mac Catalyst targets against 5.1.0 | Build on Apple silicon, or stay on 5.0.3 for Intel hosts. Generic Simulator builds must target `arm64` only, or they fail with `unsupported Swift architecture`. |
| Oversized documents fail with `unknownError` (above) | Keep documents small; match the size error by message. |
| Downgrading a store written by 5.1.x | Route through 5.0.2+ or 4.14.6+, which recognise the new index format — see [storage.md](storage.md). |
| Use after the owning `Ditto` is released is a `fatalError` on every aggregate | Keep the `Ditto` instance alive — see [Use after release](#use-after-the-owning-ditto-is-released). |

### Best practice on 5.1.x

- Pin exactly `5.1.0`. This is the default line for new code.
- `deliverOn:` works, but hopping explicitly keeps code portable to 5.0.x.

---

## All lines

### 5.2.0 and Data Streams

5.2.0 is **not** one of this skill's documented lines; it is referenced only because the
Data Streams preview exists in Swift from 5.2.0, as `@_spi(PreviewDataStreams) import
DittoSwift` ([data-streams.md](data-streams.md)). The fixture's existing test suite passes
on 5.2.0 unchanged (executed), and 5.2.0 adds a `DittoConfig` initializer with
`systemParameters:` and the `DittoError.dataStreamsError(message:)` case. Pin 5.1.0 for
everything else until this skill covers 5.2.x.

### `NO_COLOR` must be `true` or `false`

The SDK reads `NO_COLOR` during initialization and accepts only `true` or `false`. With
`NO_COLOR=1` — the common convention, and what `swift test` sets in the test process — the
process aborts before any Ditto API returns. Unset the variable or set `NO_COLOR=true` in
any process that opens Ditto; see [testing.md](testing.md).

---

## Cross-version reference

### Package and toolchain

One SPM URL serves all three lines: `https://github.com/getditto/DittoSwiftPackage`. The
version pin changes the package's shape, not its identity.

| | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `swift-tools-version` in the package manifest | `5.8.1` | `6.0` | `6.0` |
| Library products | `DittoSwift` **and** `DittoObjC` | `DittoSwift` | `DittoSwift` |
| `DittoSwift` target kind | source wrapper over two binary targets | one `binaryTarget` | one `binaryTarget` |
| Declared platforms | iOS 14, macOS 11, Catalyst 14, tvOS 14 | iOS 15, macOS 12, Catalyst 15, tvOS 15 | iOS 15, macOS 12, Catalyst 15 |
| Xcode / Swift floor | Swift tools 5.8.1 (from the manifest) | Xcode 16+, Swift 6.0+ | Xcode 16+, Swift 6.0+ |

Sources: `Package.swift` at each tag of
[getditto/DittoSwiftPackage](https://github.com/getditto/DittoSwiftPackage), and
<https://docs.ditto.live/sdk/latest/compatibility/swift>.

### Shipped XCFramework slices

From the `Info.plist` of each published XCFramework. A declared SPM platform is not a
shipped binary slice, and the two disagree for tvOS.

| Slice | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `macos` | `arm64`, `x86_64` | `arm64`, `x86_64` | **`arm64` only** |
| `ios` (device) | `arm64` | `arm64` | `arm64` |
| `ios-simulator` | `arm64`, `x86_64` | `arm64`, `x86_64` | **`arm64` only** |
| `ios-maccatalyst` | `arm64`, `x86_64` | `arm64`, `x86_64` | **`arm64` only** |
| `tvos` + `tvos-simulator` | present | present (unsupported) | absent |
| `watchos`, `xros` (visionOS) | absent | absent | absent |

- **5.1.0 drops `x86_64` everywhere**, not only on the Mac: the iOS Simulator and Mac
  Catalyst on Intel hardware are affected too.
- **tvOS is not supported on any v5 line.** Support was withdrawn in 5.0 and the binary
  removed in 5.1. A tvOS app should stay on 4.14.x and contact Ditto support, as the
  [migration guide](https://docs.ditto.live/sdk/latest/migration-guides/swift-v4)
  instructs.
- **visionOS and watchOS** are not supported on any line.

### Platform minimums

| | 4.14.x | 5.0.x / 5.1.x |
|---|---|---|
| iOS / iPadOS / Simulator | 14.0 | 15.0 |
| macOS (AppKit) | 11.0 | 12.0 |
| Mac Catalyst | 14.0 | 15.0 |

`DittoSwiftTools` is a **separate** package with its own floor — see
[preview.md](preview.md).

### Published API reference

Host: `https://software.ditto.live`. The path is `/cocoa/` up to 5.0.x and `/swift/` from
5.1.0; `/cocoa/` returns 404 for 5.1.0.

| Version | Browsable reference | Per-symbol DocC JSON |
|---|---|---|
| 5.1.0 | `…/swift/DittoSwift/5.1.0/api-reference/documentation/dittoswift/` | `…/swift/DittoSwift/5.1.0/api-reference/data/documentation/dittoswift/<symbol>.json` |
| 5.0.3 | `…/cocoa/DittoSwift/5.0.3/api-reference/documentation/dittoswift/` | `…/cocoa/DittoSwift/5.0.3/api-reference/data/documentation/dittoswift/<symbol>.json` |
| 4.14.6 | `…/cocoa/DittoSwift/4.14.6/api-reference/` | not published |

Resolve a member by fetching the **parent type's** JSON and reading the slug from its
`topicSections`, rather than constructing one by hand.

### Initialization and lifecycle

| | 4.14.6 | 5.0.3 / 5.1.0 |
|---|---|---|
| Recommended entry point | `DittoConfig` + `Ditto.open(config:)` / `openSync(config:)` | same |
| `DittoConfig` / `Ditto.open` stability label | **preview** | GA |
| `Ditto(identity:persistenceDirectory:)` | deprecated | removed |
| `DittoIdentity` | deprecated | removed |
| `startSync()` / `stopSync()` | deprecated | removed — use `ditto.sync.start()` / `.stop()` |
| `ditto.activated` | present, deprecated | removed |
| `ditto.isActivated` | **does not exist** | present |
| `ditto.appID` | deprecated | removed — use `ditto.config.databaseID` |
| `ditto.siteID` | deprecated | removed — use `presence.graph.localPeer` |
| `ditto.persistenceDirectory` | deprecated | removed — use `absolutePersistenceDirectory` |
| `disableSyncWithV3()` | present, deprecated, **and required for mutating DQL** | removed |
| `runGarbageCollection()`, `transportDiagnostics()`, `isHistoryTrackingEnabled` | deprecated | removed |

### `@Sendable` closure aliases: two arrive in 5.0, the rest in 5.1.0

| Alias | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `DittoAuthenticationExpirationHandler` | plain | `@Sendable` | `@Sendable` |
| `DittoConnectionRequestHandler` | plain | `@Sendable` | `@Sendable` |
| `DittoStoreObservationHandler` | plain | plain | `@Sendable` |
| `DittoStoreObservationHandlerWithSignalNext` | plain | plain | `@Sendable` |
| `DittoSignalNext` | plain | plain | `@Sendable` |

Type conformances split v4 from v5; closure annotations split 5.0 from 5.1. Mark observer
closures `@Sendable` yourself so the same source compiles on every line.

### Store, results and errors

| | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `store.observers` / `sync.subscriptions` | stored `Set` | **computed** | **computed** |
| `newAttachment(data:metadata:)` | absent (file path only) | present | present |
| `DittoAttachmentToken` as a public type | public | **not public** | **not public** |
| Attachment token in a query result | `DittoAttachmentToken` | `[String: Any]` | `[String: Any]` |
| `DiskUsage` / `DiskUsageItem` / `.exec` | present, deprecated | `DittoDiskUsage` / `DittoDiskUsageItem` / `.item` | same as 5.0 |
| `DiskUsageObserverHandle` (nested) | present | `DittoDiskUsageObserver` (standalone) | same as 5.0 |
| `DittoLogger.isEnabled` | **present**; `enabled` is a deprecated alias | `isEnabled` only | `isEnabled` only |
| `DittoHTTPListenConfig.webSocketSync` default | `true` | **`false`** | **`false`** |
| `DittoConnectionType.multicast` | absent | absent | **present** |
| `ADVISE` / `ADVISE AND PROVISION` through `store.execute` | parse error | parse error | **present** |
| Per-document size limit enforced | **no** | **no** | **yes, 5 242 880 bytes** |
| `DittoError.transportError` | plain | deprecated | deprecated |
| Use after release: `store.registerObserver` / `store.execute` | `throws useAfterCloseError` | **`fatalError`** | **`fatalError`** |
| Use after release: `sync.*`, `presence.*`, `smallPeerInfo.*`, `store.fetchAttachment` | **`fatalError`** | **`fatalError`** | **`fatalError`** |

### Use after the owning `Ditto` is released

Aggregates (`store`, `sync`, `presence`, `smallPeerInfo`, `auth`, `experimental`) hold a
weak reference to their `Ditto`. Calling one after the last strong reference to `Ditto`
is gone is an unrecoverable `fatalError` on every line. The only exception is 4.14.6,
where `store.registerObserver` and `store.execute` throw `useAfterCloseError` instead;
that behaviour is not present in 5.0.x or 5.1.x.

The rule is therefore the same on all three lines: own the `Ditto` instance for as long
as anything uses its aggregates. See [lifetimes.md](lifetimes.md) and
[`SKILL.md`](../SKILL.md#object-lifetimes-and-retention).

---

## CAP-19 v4 to v5 migration, API and on-disk store

This skill owns the *API form Swift uses on each line* (above) and the *on-disk
behaviour* ([storage.md](storage.md)). It does not author a migration procedure — the
published step-by-step guides are
<https://docs.ditto.live/sdk/latest/migration-guides/swift-v4> (API) and
<https://docs.ditto.live/sdk/latest/migration-guides/swift-dql> (queries), and this skill
recommends the same initialization, sync and observation forms they do.

Presence, peer and Combine renames between 4.14.x and v5 are in
[api-compatibility.md](api-compatibility.md).
