# Ditto Kotlin SDK Skill

## Contents

- [Scope](#scope)
- [Supported versions](#supported-versions)
- [Capability map](#capability-map)
- [Verification](#verification)
- [Installation](#installation)
- [Maintenance](#maintenance)

Agent skill for writing and reviewing Ditto **Kotlin** SDK code.

## Scope

Covers `com.ditto:ditto-kotlin` (v5) and `live.ditto:ditto` (4.14.x, Android-only) —
Gradle setup, connecting, authentication, transports, subscriptions, DQL execution,
observers with coroutines/Flow, attachments, presence, observability, error handling,
testing, and v4 → v5 migration. Structured against the twenty capability IDs defined
in [`docs/SDK-SKILL-TEMPLATE.md`](../../docs/SDK-SKILL-TEMPLATE.md).

Deliberately **out of scope** — these have their own skills:

- DQL syntax and semantics → `write-dql`
- CRDT type selection and document structure → `data-modeling`
- Subscription semantics and mesh propagation → `sync-subscriptions`
- Transport strategy and mesh formation → `ditto-mesh-networking`

## Supported versions

| Ditto SDK | Package version | Status |
|---|---|---|
| 5.2.x | 5.2.0 | Current GA — executed (JVM, Android) |
| 5.1.x | 5.1.0 | Supported — executed |
| 5.0.x | 5.0.3 | Supported — executed |
| 4.14.x | 4.14.7 | LTS — executed (Android; no JVM artifact exists for this line) |

## Capability map

**Targets vocabulary for this SDK:** `android | jvm | both`. `jvm` exists only on
5.x — 4.14.x shipped no JVM artifact, so for v4 rows read `both` as "android"
([`references/versions.md`](references/versions.md#package-coordinates-per-version-line)).

| ID | Capability | Support | Evidence | Targets |
|----|-----------|---------|----------|---------|
| CAP-01 | Prerequisites, toolchain, package install | yes | executed | both |
| CAP-02 | Platform permissions, entitlements, build config | yes | docs-sample | android |
| CAP-03 | Connecting: config, opening, persistence directory | yes | executed | both |
| CAP-04 | Authentication and identity | yes | executed | both |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | yes | executed | both |
| CAP-06 | Customizing transports | yes | source | both |
| CAP-07 | Sync subscriptions and sync scopes | yes | executed | both |
| CAP-08 | Querying the store: executing DQL | yes | executed | both |
| CAP-09 | Transactions | yes | docs-sample | both |
| CAP-10 | Indexing | yes | docs-sample | both |
| CAP-11 | Observers, diffing and back-pressure | yes | executed | both |
| CAP-12 | Attachments | yes | source | both |
| CAP-13 | Presence graph and connection requests | partial | docs-sample | both |
| CAP-14 | Sync status and local commit tracking | yes | docs-sample | both |
| CAP-15 | Logging, diagnostics and stats | yes | executed | both |
| CAP-16 | Error handling | yes | executed | both |
| CAP-17 | Device storage management and eviction | yes | inference | both |
| CAP-18 | Testing | yes | executed | both |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | executed | both |
| CAP-20 | Preview and platform-specific APIs | preview | executed | both |

Rows that are not `Support: yes`:

- **CAP-13 `partial`** — presence graph, peer metadata and `presence.observe()` are
  documented for Kotlin and are single-device testable; the
  `DittoPresence.ConnectionRequestHandler` only fires when a second peer connects, and
  no two-peer run was executed — the handler samples are docs-sourced only
  ([`references/presence.md`](references/presence.md)).
- **CAP-20 `preview`** — Data Streams is opt-in preview: 5.1.0+ (docs floor; executed
  on 5.0.3, 5.1.0 and 5.2.0 on the JVM), requires
  `@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)` and NGN, and the docs warn
  "breaking changes without notice". Multicast is beta (5.1.0). The opt-in mechanism
  and stability warning are quoted in [`references/preview.md`](references/preview.md);
  the implementation guide is [`references/data-streams.md`](references/data-streams.md).

Evidence notes (spec §7 requires the tier's extra information inline for
`source`/`inference`):

- **CAP-06 `source`** — the `updateTransportConfig { }` DSL block names
  (`peerToPeer { bluetoothLe { } lan { } wifiAware { } }`, `connect { }`,
  `listen { tcp { } http { } }`, `global { }`, `interfaceIp`, `Global.syncGroup:
  UInt`) are not fully shown in Kotlin docs samples; verified against
  `sdks/kotlin/api/ditto-kotlin/src/commonMain/kotlin/com/ditto/kotlin/transports/DittoTransportConfig.kt`
  at `sdk-release-5.1.0`.
- **CAP-17 `inference`** — `sdk/latest/sync/device-storage-management.mdx` publishes no
  Kotlin sample; the EVICT statement is documented in `dql/evict.mdx`, and the Kotlin
  call shape is the `execute(query, arguments)` overload in
  `commonMain/com/ditto/kotlin/DittoStore.kt` of the published `sdk-release-5.1.0`
  sources jar. The composition was not executed.
- **CAP-12 `source`** — the fetch sample's v5 signatures (`executeRaw` returns the
  closeable result; `fetchAttachment(token: DittoAttachmentToken, …)` vs the
  `tokenMap: Map<String, Any>` overload) verified against
  `sdks/kotlin/api/ditto-kotlin/src/commonMain/kotlin/com/ditto/kotlin/DittoStore.kt`
  at `sdk-release-5.1.0` and compile-verified against the published 5.1.0 jar; the
  fetch *lifecycle* (progress events, `Deleted` race) was not executed end-to-end.
- **CAP-02 / CAP-09 / CAP-10 / CAP-14 `docs-sample`** — working
  Kotlin samples exist on the cited doc pages; they were not re-executed here.
- **CAP-20 `executed`** covers Data Streams through the two-peer JVM fixture
  (`DataStreamsTest`, 10 tests, plus the 5.2.0-only `systemParameters` test); the
  Android `Os.setenv` form and multicast are docs-sourced.
- **CAP-04 `executed`** covers offline-license activation; the cloud
  `expirationHandler`/`login` round-trip needs a Ditto Cloud app and is docs-sourced.
- **CAP-15 `executed`** covers logger enable/disable behavior observed during the
  minimal-app runs; `exportToFile` and disk-usage APIs are docs-sourced.
- **CAP-19 `executed`** covers building and running both version lines; the on-disk
  store migration subsection is doc-sourced plus an explicit not-verified statement.

## Verification

**Executed against:**

- 5.1.0 (JVM, macOS arm64, OpenJDK 17.0.20.1, Gradle 9.8.2, Kotlin plugin 2.3.21):
  the full minimal app — create, offline license, `sync.start()`, subscription,
  observer initial + change delivery, INSERT, read-back, clean shutdown.
- 5.0.3 (JVM, same host): same program.
- 4.14.7 (Android emulator, API 35 arm64, AGP 9.4.1; re-run on a Pixel 10a / Android
  17): same flow as an Android app, including the `disableSyncWithV3()` requirement
  and its exact failure string.
- **5.2.0, 5.1.0 and 5.0.3 on Android** (Pixel 10a, Android 17, AGP 9.4.1 built-in Kotlin,
  `compileSdk` 36): the same flow as an Android app, plus two on-device probes — the
  `registerObserver` handler runs on `main`, and an `observe()` transform under
  `.flowOn(Dispatchers.IO)` also runs on `main`. A `compileSdk` 35 build fails
  `CheckAarMetadata` (executed).
- **5.2.0** (JVM, same host, and in CI on Linux x64): the minimal app and all four
  tests green; the Android v5 leg on the Pixel 10a with both probes unchanged. Its
  public API was diffed against 5.1.0 from the published sources jar: nothing the skill
  documents was removed; the additions are listed in
  [`references/versions.md`](references/versions.md#new-in-520). The GA sources are
  identical to `5.2.0-rc.2`'s, which was executed the same way before GA.
- JUnit pattern (5.0.3, 5.1.0 and 5.2.0, same JVM host):
  [`tests/kotlin-sdk/minimal-app/src/test/kotlin/DittoStoreTest.kt`](../../tests/kotlin-sdk/minimal-app/src/test/kotlin/DittoStoreTest.kt)
  — `insertThenReadBack`, `observerReportsTheWrite`, `observerReportsTheWriteUnderRunTest`
  and `flowOnDoesNotReachTheObserveTransform`, 4 tests green on macOS arm64 and in CI on
  Linux x64 (`gradle test -PdittoVersion=<v>`). The plain observer test runs under
  `runBlocking`: Ditto delivers on real FFI threads, so `runTest`'s virtual time expires
  first (executed failure); the `runTest` form waits under `withContext(Dispatchers.Default)`.
- Executed failure modes: missing `ditto-binaries` classifier on JVM; plain re-INSERT
  FAIL-conflict `UnknownException`; v4 INSERT without `disableSyncWithV3()`.
  Transcripts: [`examples/minimal-app.md`](examples/minimal-app.md).
- **Data Streams, two peers in one JVM** (5.0.3, 5.1.0 and 5.2.0, same results; NGN via
  `DITTO_NETWORK_ENABLE_NGN` on the test task, TCP loopback listener, LAN off):
  bytes round-trip both ways on one reliable stream; `sendAndForget` delivers; the
  monitoring `send` reaches `Sent`; `closeSync()` is `ClosedByRemote` on the other side;
  reliability mismatch `Rejected(ConnectionRejected)`; invalid topics `Err(InvalidTopic)`;
  second bind `Err(TopicAlreadyBound)`; a borrowed candidate is unusable after its callback
  while a `take()`n one works; closing the acceptor leaves open streams alive and new
  connects fail; arguments travel both ways; the receive callback is off the main thread.
  Two defects recorded: acceptor-side `arguments()` throws when none were sent, and
  `topic()` returns garbage on acceptor and streams. 5.2.0 only: NGN enabled through
  `DittoConfig.systemParameters` carries a stream
  ([`references/data-streams.md`](references/data-streams.md)).

**Verified from source** (`github.com/getditto/ditto` at the named tags):

- `sdk-release-5.1.0` and `sdk-release-5.0.3`: observer back-pressure mechanics
  (`InternalDittoStore.kt` — `signalNext` after handler return, result closed in
  `finally` first; `observe()` = `callbackFlow { … send(…) }.buffer(Channel.RENDEZVOUS)`),
  exception-in-handler closes the observer, per-platform callback dispatchers
  (`Ditto.android.kt` `MainScope()` vs `Ditto.jvm.kt` `Dispatchers.Default`),
  cancellation closing the native observer, the transport-config DSL surface.
- `kotlinx-coroutines-core` `native/src/Dispatchers.kt` @ 1.9.0 (the coroutines
  version Ditto 5.1.0 builds against, per its `libs.versions.toml`) and @ 1.10.2 (the
  version the harness executed): `Dispatchers.IO` on Kotlin/Native (iOS) is a
  public `actual val` backed by `DefaultIoScheduler` (2048-thread pool,
  `limitedParallelism(64)`) in both — present and off-main, backing the skill's
  KMP-wide "use `Dispatchers.IO`, never main" guidance.
- `sdk-release-4.14.7`: the `crdt_version < V6` gate behind "disable sync with V3"
  (`ffi/src/store/dql/ffi_access.rs`); the 4.14.7 AAR (javap) for identity constructor
  shapes and the `live.ditto.android` package layout.

- Published 5.1.0 artifacts (`ditto-kotlin-5.1.0-sources.jar`, `ditto-internal-jvm-5.1.0.jar`
  bytecode): `collect()` registers an observer with no context switch and the FFI
  callback launches every handler on the SDK scope, so an `observe()` transform runs on
  that scope and `.flowOn()` does not reach it — executed as the `flowOn` probe test
  ([`references/concurrency.md`](references/concurrency.md#why-flowon-does-not-move-the-observe-transform)).
  `sync.subscriptions` / `store.observers` are delegated live views, not snapshots.

**Not verified:** the runtime-permissions helper and foreground service on Android (the
harness app is offline-only and declares neither); two-peer mesh sync (no second device
run); attachments fetch lifecycle; transactions; Data Streams on Android devices and over
multi-hop routes (JVM loopback only); ProGuard/R8
release-build behavior; in-place on-disk store migration semantics on a shipped 4.14.x
store; cloud authentication round-trip.

**Last verified:** 2026-10-28 (JVM legs in CI; all three Android legs on a Pixel 10a).

## Installation

```bash
# Claude Code
/plugin marketplace add getditto/agent-skills
/plugin install ditto-kotlin@ditto-plugins
```

For other agent tools, see the repository [README](../../README.md).

## Maintenance

When the SDK ships a new minor version:

1. Re-read `sdk/latest/release-notes/kotlin.mdx` for API changes.
2. Update `references/versions.md` first — it is the source of truth for version claims.
3. Re-run `examples/minimal-app.md` against the new version and update **Verification**.
4. Re-check the capability map: a `partial`/`preview` row may have changed.
