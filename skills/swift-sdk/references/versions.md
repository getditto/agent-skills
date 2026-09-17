# Versions — Ditto Swift SDK

**This file owns every fact that differs between 4.14.x, 5.0.x and 5.1.x.** Every other
file in this skill shows the v5 form and links here.

Verified releases: **4.14.6**, **5.0.3**, **5.1.0**. Claims that were executed say so;
the rest name the SDK source file or documentation page they came from.

**When the project's version cannot be determined, emit 5.1.x code and say so.**

---

## CAP-19 v4 to v5 migration, API and on-disk store

This skill owns the *API form Swift uses on each line* and the *measured on-disk
behaviour*. It does not author a migration procedure — the published step-by-step guides
are <https://docs.ditto.com/sdk/latest/migration-guides/swift-v4> (API) and
<https://docs.ditto.com/sdk/latest/migration-guides/swift-dql> (queries), and this skill
recommends the same initialization, sync and observation forms they do.

---

## Package and toolchain

One SPM URL serves all three lines: `https://github.com/getditto/DittoSwiftPackage`. The
version pin changes the package's shape, not its identity.

| | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `swift-tools-version` in the package manifest | `5.8.1` | `6.0` | `6.0` |
| Library products | `DittoSwift` **and** `DittoObjC` | `DittoSwift` | `DittoSwift` |
| `DittoSwift` target kind | source target `DittoSwiftWrapper` over two binary targets | one `binaryTarget` | one `binaryTarget` |
| Declared platforms | iOS 14, macOS 11, Catalyst 14, tvOS 14 | iOS 15, macOS 12, Catalyst 15, tvOS 15 | iOS 15, macOS 12, Catalyst 15 |
| Xcode / Swift floor | not published; the manifest requires Swift tools 5.8.1 | Xcode 16+, Swift 6.0+ | Xcode 16+, Swift 6.0+ |

Sources: `Package.swift` at tags `4.14.6`, `5.0.3` and `5.1.0` of
`getditto/DittoSwiftPackage`, and `sdk/latest/compatibility/swift.mdx` for the v5 Xcode
and Swift floor. `sdk/v4/compatibility/swift.mdx` has **no** Development Requirements
section, so the v4 toolchain floor can only come from the manifest.

Because 4.14.6 ships two products, an Xcode target pinned to 4.14.x links `DittoSwift`
and `DittoObjC`; re-pinning to 5.x leaves a stale `DittoObjC` reference that has to be
removed from the target by hand.

### Shipped XCFramework slices

Read from the `Info.plist` of the XCFramework each pin resolved. A declared SPM platform
is not a shipped binary slice, and the two disagree for tvOS.

| Slice | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `macos` | `arm64`, `x86_64` | `arm64`, `x86_64` | **`arm64` only** |
| `ios` (device) | `arm64` | `arm64` | `arm64` |
| `ios-simulator` | `arm64`, `x86_64` | `arm64`, `x86_64` | **`arm64` only** |
| `ios-maccatalyst` | `arm64`, `x86_64` | `arm64`, `x86_64` | **`arm64` only** |
| `tvos` + `tvos-simulator` | present | **present** | **absent** |
| `watchos`, `xros` (visionOS) | absent | absent | absent |

Two consequences the release notes state less precisely:

- **5.1.0 drops `x86_64` everywhere**, not only on the Mac. An Intel Mac cannot build or
  run the iOS *Simulator* against 5.1.0 either, and a Catalyst app built against 5.1.0
  will not run on Intel hardware. The changelog says only
  *"Removed: Support for Intel (`x86_64`) Macs. (#SDKS-2924)"*.
- **tvOS binaries exist on 5.0.3** even though
  `sdk/latest/migration-guides/swift-v4.mdx` says tvOS is *"No longer supported in
  v5.0"* and the 5.1 changelog says *"Removed: tvOS platform support. (#SDKS-3944)"*.
  Support was withdrawn in 5.0 and the binary was removed in 5.1. **This skill claims no
  tvOS support on any v5 line**: a declared platform with an untested binary is not
  support. A tvOS app should stay on 4.14.x and contact Ditto support, which is what the
  migration guide instructs.

visionOS is in the same position on paper — `swift-v4.mdx` lists *"visionOS (beta) — No
longer supported in v5.0"* — but no v4 SPM slice ships for it, so an SPM-installed v4 app
was never building for visionOS. watchOS is excluded on every line.

### Platform minimums

| | 4.14.x | 5.0.x / 5.1.x |
|---|---|---|
| iOS / iPadOS / Simulator | 14.0 | 15.0 |
| macOS (AppKit) | 11.0 | 12.0 |
| Mac Catalyst | 14.0 | 15.0 |

The v4 documentation disagrees with itself and the manifest is the tie-breaker:
`sdk/v4/install-guides/swift.mdx` states Catalyst 14+ and macOS (AppKit) 11+, while
`sdk/v4/compatibility/swift.mdx` lists only iOS, iPadOS and the Simulator. The 4.14.6
manifest declares `.macOS(.v11)` and `.macCatalyst(.v14)` and a macOS slice ships, so the
install guide is right and the compatibility page is incomplete.

`DittoSwiftTools` is a **separate** package with its own floor — see
[preview.md](preview.md).

### Published API reference

The host path is version-gated — `/cocoa/` up to 5.0.x, `/swift/` from 5.1.0 — and the
migration guide gets it wrong for 5.1.0. All of these were checked with an HTTP request:

| Version | Browsable reference | Per-symbol DocC JSON |
|---|---|---|
| 5.1.0 | `…/swift/DittoSwift/5.1.0/api-reference/documentation/dittoswift/` | `…/swift/DittoSwift/5.1.0/api-reference/data/documentation/dittoswift/<symbol>.json` |
| 5.0.3 | `…/cocoa/DittoSwift/5.0.3/api-reference/documentation/dittoswift/` | `…/cocoa/DittoSwift/5.0.3/api-reference/data/documentation/dittoswift/<symbol>.json` |
| 4.14.6 | `…/cocoa/DittoSwift/4.14.6/api-reference/` | **not published** — 404 |

Host: `https://software.ditto.live`. `swift-v4.mdx:28` tells the reader to use `/cocoa/`
for *"any later `5.x` release"*, which 404s on 5.1.0 — the line this skill emits by
default. 4.14.6 publishes no DocC JSON at all, so the source tree is the symbol evidence
for that line. Resolve a member by fetching the **parent type's** JSON and reading the
slug from its `topicSections` rather than hand-constructing one.

---

## Initialization and lifecycle

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

### The 4.14.x deprecation polarity is the opposite of "old is safer"

On 4.14.6 there is no un-caveated way to open Ditto: the identity path is **deprecated**
and the config path is labelled **preview**
(`sdk-release-4.14.6:cocoa/DittoSwift/Ditto.swift:142`;
`sdk/v4/release-notes/swift.mdx:419,421`). The config path is still the right answer:
`Ditto.open(config:)`'s doc comment at
`sdk-release-4.14.6:cocoa/DittoSwift/Ditto.swift:31` calls it *"the recommended
initialization path"* that *"will be the only supported path in SDK 5.0"* — which is what
shipped. Emit the config path on all three lines; never emit a deprecated API.

### 4.14.x refuses mutating DQL until `disableSyncWithV3()` is called

**Executed on 4.14.6.** `SELECT` works; the first mutating statement throws:

```
DittoError.storeError(reason: .queryNotSupported(message:
  "<dql> Unsupported feature: Encountered `INSERT` statement. Mutating DQL statements
   require that your application is updated to the latest version. Please configure your
   app to disable sync with V3 to use DQL"))
```

```swift
// 4.14.x only. Not needed — and not available — on 5.0.x or 5.1.x.
let ditto = try await Ditto.open(config: config)
try ditto.disableSyncWithV3()   // deprecated on this line, and required anyway
try ditto.sync.start()
```

This applies to both connect modes, is **irreversible**, and propagates to every peer it
meets (`sdk-release-4.14.6:cocoa/DittoSwift/Ditto.swift:501-513`). Call it before
`sync.start()`. It is the one place this skill emits a deprecated API, because the
alternative is a feature that does not work.

---

## Swift concurrency

This is where the three lines differ most, and where a difference is invisible until
runtime — or until the compiler refuses code that works on the next line up.

### `Sendable` conformances: v4 has none

**Executed.** Compiling the same v5-shaped source against 4.14.6 in Swift 6 language mode
fails with `error: sending 'ditto' risks causing data races` (and the same for
`ditto.store`). 5.0 *"Marked most public types as `Sendable`"*
(`5-0-capabilities/swift-specific-changelog.mdx:26`), so `Ditto` and `DittoStore` cross
isolation boundaries freely on both v5 lines
(`sdk-release-5.1.0:sdks/swift/DittoSwift/Ditto.swift:541`, `DittoStore.swift:719`).

The fix for 4.14.x is `@preconcurrency import DittoSwift`, verified to compile. Do **not**
write retroactive `extension Ditto: @unchecked Sendable {}` shims — on v5 they produce
`error: conformance of 'Ditto' to protocol 'Sendable' was already stated in the type's
module 'DittoSwift'`.

### `deliverOn:` is ignored on 5.0.x

`registerObserver(deliverOn:)` is honoured on 4.14.6 and 5.1.0 and **ignored on 5.0.3** —
**executed on all three lines**. On 5.0.3 the private `registerObserver` accepts the queue
and never references it
(`sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoStore.swift:688-702`); 5.1.0 wraps delivery
in `queue.async { … }`
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStore.swift:695-702`); 4.14.6 passes it to
the ObjC layer as `deliveryDispatchQueue:`.

The published symptom is stronger than "runs on the wrong queue":
`5-1-capabilities/swift-specific-changelog.mdx` describes #SDKS-3856 as *"resolving a
crash when used with Swift concurrency"*. Handler code that passes `deliverOn: .main` and
then touches main-actor state is correct on 4.14.6 and 5.1.0 and faults on 5.0.3.

**Write code that does not depend on it.** Hop explicitly inside the handler and the same
source is correct on all three lines — see [observers.md](observers.md).

### `@Sendable` closure aliases arrive in 5.1.0

`DittoStoreObservationHandler`, `DittoStoreObservationHandlerWithSignalNext` and
`DittoSignalNext` are plain closures at 5.0.3
(`sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoStoreObserver.swift:8-17`) and `@Sendable`
at 5.1.0 (`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStoreObserver.swift:16-27`). This
is the same ticket as the `deliverOn` fix, #SDKS-3856 — one change, not two.

So the axis is **v4-vs-v5 for type conformances** and **5.0-vs-5.1 for closure
annotations**. `5-0-capabilities/additional-improvements.mdx:37` advertises *"Full Swift 6
support with Sendable conformance"* for 5.0; the 5.1 handler fix contradicts it.

---

## Store, results and errors

| | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `store.observers` / `sync.subscriptions` | stored `Set` | **computed** | **computed** |
| `newAttachment(data:metadata:)` | absent (file path only) | present | present |
| `DittoAttachmentToken` as a public type | public | **not public** | **not public** |
| Attachment token in a query result | `DittoAttachmentToken` | `[String: Any]` | `[String: Any]` |
| `DiskUsage` / `DiskUsageItem` / `.exec` | present, deprecated | `DittoDiskUsage` / `DittoDiskUsageItem` / `.item` | same as 5.0 |
| `DiskUsageObserverHandle` (nested) | present | `DittoDiskUsageObserver` (standalone) | same as 5.0 |
| `DittoLogger.enabled` | deprecated | `DittoLogger.isEnabled` | same as 5.0 |
| `DittoHTTPListenConfig.webSocketSync` default | `true` | **`false`** | **`false`** |
| `DittoConnectionType.multicast` | absent | absent | **present** |
| Per-document size limit enforced | **no** | **no** | **yes, 5 242 880 bytes** |
| Use after the owning `Ditto` is released | `throws DittoError.useAfterCloseError` | **`fatalError`** | **`fatalError`** |

`DittoDiskUsageItem`'s *property* names are unchanged; only the type was renamed.

### The 5 MiB per-document limit is new in 5.1.0

**Executed.** 4.14.6 and 5.0.3 accept 5, 6, 8 and 16 MiB documents without complaint.
5.1.0 rejects a 5 MiB document:

```
DittoError.unknownError(message: "<dql> Query failed: `DQL Internal execution error:
  Insert failed: <store> Document `_id = \"oversized\"` size is 5243057 bytes and
  exceeds limit of 5242880 bytes`. …")
```

An app that writes documents this large works on 5.0.x and starts failing on 5.1.x. Note
the error case: this is `unknownError`, **not** `validationError(.sizeLimitExceeded)` —
match on the message, not the case. For why documents should be far smaller than the
limit anyway, see the `data-modeling` skill or <https://docs.ditto.com/key-concepts>.

### Use after the owning `Ditto` is released: v5 is strictly worse

`sdk/v4/release-notes/swift.mdx:20` (#SPO-960, 4.14.6): *"Registering a store observer or
executing a query after `Ditto` has been deallocated now throws a recoverable error
instead of crashing."* Confirmed at
`sdk-release-4.14.6:cocoa/DittoSwift/Store/DittoStore.swift:206-209`.

**That fix was not carried into v5.** At
`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStore.swift:230` the same guard is
`fatalError(…)`, repeated at `:285`, `:537`, `:626` and for `execute` at `:732`;
identical at `sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoStore.swift`. `DittoSync`,
`DittoPresence` and `DittoSmallPeerInfo` behave the same way.

On v5, dropping the last strong reference to `Ditto` and then touching `store`, `sync` or
`presence` is an **unrecoverable crash**, not a `throws` an app can catch. That is why
[`SKILL.md`](../SKILL.md) promotes the ownership rule into its always-loaded body.

### Deprecated error cases in 5.1.0

The `CBOR` enum and `DittoError.StoreErrorReason.invalidDocumentStructure(cbor:)` /
`.nonStringKeyInDocument(key:)` are deprecated in 5.1.0 and *no longer produced*
(#SDKS-4009). Do not write recovery code for errors the SDK has stopped emitting.
`DittoError.transportError` / `TransportErrorReason` are deprecated on the same line.

---

## Presence and peers

| 4.14.x | v5 |
|---|---|
| `DittoPeer.peerKeyString` | `peerKey` |
| `DittoPeer.isConnectedToDittoCloud` | `isConnectedToDittoServer` |
| `DittoPeer.osV2` | `os` |
| `DittoConnection.peerKeyString1` / `2` | `peer1` / `peer2` |
| `ditto.observePeers` / `observePeersV2` | `presence.observe(didChangeHandler:)` |
| `DittoRemotePeer`, `DittoAddress`, `DittoConnectionPriority`, `approximateDistanceInMeters` | removed |

`DittoPeerOS.tvOS` is **deprecated but retained** in 5.1.0 so peers on older tvOS SDKs
stay identifiable in the presence graph (#SDKS-3944). An exhaustive `switch` still has to
handle it — and `.unknown(os:)`, where any unrecognised value lands.

---

## Combine

There has **never** been a DQL or store-query publisher in v5. Enumerating every public
publisher at `sdk-release-5.1.0:sdks/swift/DittoSwift/*+Combine.swift` yields exactly
four: `DittoAuthenticator.StatusPublisher`, `DittoDiskUsage.DiskUsagePublisher`,
`DittoPresence.GraphPublisher` and `DittoStore.FetchAttachmentPublisher`.

4.14.6 *did* have one — `LiveQueryPublisher` in
`cocoa/DittoSwift/Combine/DittoPendingCursorOperation+Combine.swift` — but it hung off
the deprecated collection API and was itself deprecated. It and `RemotePeersPublisher`
are gone by 5.1.0. Query publishers were removed, never carried forward.

The `@available` annotation on the surviving publishers is itself version-gated:
`@available(iOS 13, macOS 10.15, macCatalyst 13, tvOS 13, watchOS 6, *)` at 4.14.6 and
5.0.3, losing `tvOS 13` at 5.1.0.

---

## Fixes that skip a line

Newer is not uniformly better. Two fixes ship in 4.14.6 **and** 5.1.0 but **not** in any
5.0.x release:

| Fix | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| Uncaught exceptions in SDK callbacks re-raise with the original call stack instead of a `SIGABRT` attributed to Ditto (#SDKS-3483) | yes | **no** | yes |
| Use-after-deallocation throws instead of crashing (#SPO-960) | yes | **no** | **no** |

Other line-specific facts:

- **mDNS advertised and browsed with incorrect information before 4.14.3** (#NETW-883,
  `sdk/v4/release-notes/swift.mdx`) — the LAN-discovery failure mode below that patch.
- **Do not recommend 4.14.5**; the v4 release notes identify it as regressed
  (`sdk/v4/release-notes/swift.mdx:35`). Pin 4.14.6.
- **Custom `DITIdentityProvider` implementations stalled the SDK** on the first credential
  refresh until #SDKS-3623, fixed in 5.1.0 — a 5.0.x failure mode.

---

## On-disk store: upgrade, rollback and the persistence directory

All of the following was **executed** with `tests/swift-sdk/scripts/persistence-matrix.sh`
on macOS 27.0 / arm64.

### Default persistence directory

| Opened with | Default directory |
|---|---|
| 4.14.x `Ditto(identity:)` (deprecated) | `<Documents>/ditto` |
| 4.14.x `Ditto.open(config:)` | `<Application Support>/ditto-{databaseID}` |
| 5.0.x / 5.1.x `Ditto.open(config:)` | `<Application Support>/ditto-{databaseID}` |

"The default directory changed from `ditto` to `ditto-{databaseID}` in v5" is about the
**identity initializer**, not about `Ditto.open`. An app already using
`Ditto.open(config:)` on 4.14.x is already on the v5 default path — measured, both
versions reported the same absolute directory.

**An upgrading app does not silently get an empty database.** When
`persistenceDirectory` is `nil`, `DittoConfig.encode(to:)` also sends the v4 default path
as `legacy_persistence_directory`
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoConfig.swift:172-191`, byte-identical at
`sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoConfig.swift:171-179`), and Core checks
both, preferring the non-legacy path. Executed: a database written by 4.14.6's
`Ditto(identity:)` into `<Documents>/ditto` was found and read by 5.1.0 with no
`persistenceDirectory` set, and `absolutePersistenceDirectory` reported that legacy path.

Setting `persistenceDirectory` explicitly removes the ambiguity, and is what
[connect.md](connect.md) recommends.

### Upgrade and rollback

| Written by | Read by | Result |
|---|---|---|
| 4.14.6 | 5.0.3 | document and index present |
| 4.14.6 | 5.1.0 | document and index present |
| 5.1.0 | 5.0.3 | document and index present |
| 5.1.0 | 4.14.6 | document and index present |

This matches the published contract in
`snippets/common-release-notes/5-1-capabilities/upgrade-considerations.mdx`: 5.1 changes
the on-disk index format, and a downgrade must route through **5.0.2+ or 4.14.6+**, which
recognise the new format and revert it. During the downgrade a composite index is
replaced by one single-field index per key.

**Not verified here:** downgrading below 5.0.2 / 4.14.6, and the composite-index split —
the fixture creates a single-field index only. Composite indexes are a DQL feature; see
the `dql` skill or <https://docs.ditto.com/dql/indexing#migration>.

---

## The environment trap that affects every line

**Executed on 4.14.6, 5.0.3 and 5.1.0.** If `NO_COLOR=1` is in the process environment,
the SDK's Rust core panics during initialization, before any Ditto API returns:

```
thread '<unnamed>' panicked at crates/tracing-config/src/lib.rs:
called `Result::unwrap()` on an `Err` value: … [String("--disable-color"), String("1"),
Strings(["true", "false"])]
```

The core maps `NO_COLOR` onto a `--disable-color` flag that accepts only `true` or
`false`; `NO_COLOR=true` is fine and the conventional `NO_COLOR=1` is fatal. This matters
because **`swift test` exports `NO_COLOR=1` into the test process** — see
[testing.md](testing.md).
