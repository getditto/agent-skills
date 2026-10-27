# Versions and migration — Kotlin

> **Sources for this file.** <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4> (API migration)
> and <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-dql> (query migration — a separate guide),
> <https://docs.ditto.live/sdk/latest/v5-whats-new>, <https://docs.ditto.live/sdk/latest/release-notes/kotlin>,
> <https://docs.ditto.live/sdk/latest/compatibility/kotlin>, <https://docs.ditto.live/sdk/v4/install-guides/kotlin>. Facts marked
> **executed** were run against the real artifact at the named patch version (see
> `examples/minimal-app.md`); facts marked **javap/source-verified** were checked
> against the published artifact or `ditto` repo at `sdk-release-4.14.7` /
> `sdk-release-5.1.0`.
>
> This file is the **single source of truth** for version claims in this skill,
> including package coordinates per version line (`setup.md` shows only the v5 form).
> Any inline tag elsewhere must agree with it.

## Contents

- [Supported versions](#supported-versions)
- [Package coordinates per version line](#package-coordinates-per-version-line)
- [Capability availability matrix](#capability-availability-matrix)
- [CAP-19 v4 to v5 migration](#cap-19-v4-to-v5-migration)
  - [On-disk store migration](#on-disk-store-migration)
  - [Removed APIs](#removed-apis)
  - [New in v5](#new-in-v5)
  - [Migration checklist](#migration-checklist)

## Supported versions

| Ditto SDK | Package version | Verified on | Status |
|---|---|---|---|
| 5.1.x | 5.1.0 | 5.1.0 — executed (JVM, macOS arm64) | Current |
| 5.0.x | 5.0.3 | 5.0.3 — executed (JVM, macOS arm64) | Supported |
| 4.14.x | 4.14.7 | 4.14.7 — executed (Android emulator, API 35) | LTS |

**Kotlin toolchain:** docs say Kotlin 2.0+ (Ditto supports the four most recent stable
releases, N−4) and JDK 17 (<https://docs.ditto.live/sdk/latest/compatibility/kotlin>,
<https://docs.ditto.live/sdk/latest/install-guides/kotlin>). **The published artifacts set a higher floor for
5.1.x** (**[api-dump]** Maven Central POMs, `com/ditto/ditto-kotlin-jvm/<v>/`):

| Artifact | `kotlin-stdlib` | `kotlinx-coroutines-core` |
|---|---|---|
| `ditto-kotlin-jvm` / `-android` 5.1.0 | **2.3.21** | 1.9.0 |
| `ditto-kotlin-jvm` 5.0.3 | 2.1.0 | 1.10.1 |

The Kotlin compiler reads class metadata at most one minor version newer than itself
(N+1), so the practical floor is **KGP ≥ 2.2 for 5.1.0** and 2.0 for 5.0.3. The
executed-working pin is Kotlin Gradle plugin **2.3.21** with
`kotlinx-coroutines-core:1.10.2` (JVM). The harness also failed to compile 5.0.3 under
KGP 2.0.x (**executed**); the root cause was not isolated — a 2.0 compiler should read
2.1 metadata under the N+1 rule — so do not quote that failure as the floor.

**Android + AGP 9:** AGP 9 has built-in Kotlin support enabled by default — do
**not** apply the `org.jetbrains.kotlin.android` plugin (AGP fails the build if you
do). The v4 harness fixture builds this way (AGP 9.4.1, no KGP applied, **executed**).
**v5 on Android has not been executed** by this skill — the AGP 9 guidance applied to
`com.ditto:ditto-kotlin` is **[inference]** from the v4 build plus the install guide;
the 2.3.21 KGP pin above is JVM-verified only.

## Package coordinates per version line

| Line | Coordinate | Notes |
|---|---|---|
| 5.0.x / 5.1.x | `com.ditto:ditto-kotlin:<version>` | KMP root module; Gradle resolves the `-android` or `-jvm` variant from the consuming project |
| 5.0.x / 5.1.x, JVM only | `+ runtimeOnly("com.ditto:ditto-binaries:<version>:<classifier>")` | **Mandatory on JVM.** Classifiers published for 5.1.0 (**[api-dump]** Maven Central `com/ditto/ditto-binaries/5.1.0/`): `macos-arm64`, `linux-x64`, `linux-arm64`, `windows-x64` — there is **no `macos-x64`**, so Intel Macs cannot run the JVM target. Without it: `IllegalStateException: Unable to find binary 'libdittoall.dylib' …` (executed) |
| 4.14.x | `live.ditto:ditto:<version>` | AAR, **Android-only**. There is no 4.14.x JVM artifact (`live.ditto:ditto-jvm` stalled at `4.11.0-preview.1`); the `com.ditto:ditto-kotlin` coordinate does not exist for 4.14.x |

Android ABIs in both lines (verified from the published AARs): `arm64-v8a`,
`armeabi-v7a`, `x86`, `x86_64`.

## Capability availability matrix

| Capability | 4.14.x | 5.0.x | 5.1.x | Failure mode on older versions |
|---|---|---|---|---|
| DQL reads (`SELECT`) | ✓ | ✓ | ✓ | — |
| DQL mutations (`INSERT`/`UPDATE`/`DELETE`) | Only after `ditto.disableSyncWithV3()` (see below) | ✓ | ✓ | 4.14.x without the call: ``DittoError.StoreError: <dql> Unsupported feature: Encountered `INSERT` statement. … disable sync with V3 …`` (executed) |
| `dql_strict_mode` default | `true` (strict) | `false` | `false` | Under 4.14.x strict default, bare-object fields are stored as REGISTERs and dropped from undeclared reads — see the `data-modeling` skill or <https://docs.ditto.live/key-concepts> |
| `JOIN`, composite indexes, `RETURNING`, `ADVISE` | ✗ | ✗ | ✓ | `DittoException.StoreException` on parse |
| Data Streams | ✗ | Classes ship in the jar; preview status untested | Preview (opt-in annotation) | Docs name 5.1.0 as the floor; `@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)` required — see [preview.md](preview.md) |
| `observe()` / `collect()` Flow APIs | ✗ (callback `registerObserver` only) | ✓ | ✓ | Unresolved references on 4.14.x |
| `DittoFactory.create(DittoConfig)` | ✗ | ✓ | ✓ | v4 uses the `Ditto(deps, identity)` constructor |
| JVM target | ✗ | ✓ | ✓ | No artifact |
| `DittoTools` companion package | `live.ditto:ditto-tools-android` | `com.ditto:ditto-tools-android:6.x` (requires ditto-kotlin ≥ 5.0.1) | `com.ditto:ditto-tools-android:6.x` | Old coordinate tracks the v4 namespace |

## CAP-19 v4 to v5 migration

### Package and namespace

`live.ditto.*` → `com.ditto.kotlin.*` (transports live in
`com.ditto.kotlin.transports.*`; DittoTools 6 in `com.ditto.tools.*`). Replace imports
by package family (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Initialization and identity

v4 mixed everything into a `Ditto(dependencies, identity)` constructor; v5 is a
non-suspend factory call on an immutable config:

```kotlin
// 4.14.x (executed on Android, 4.14.7)
val deps = DefaultAndroidDittoDependencies(context)        // live.ditto.android package
val ditto = Ditto(deps, DittoIdentity.OfflinePlayground(deps, appId = "my-app"))
ditto.setOfflineOnlyLicenseToken(license)
ditto.disableSyncWithV3()   // REQUIRED before mutating DQL — see below
ditto.startSync()

// 5.x (executed on JVM, 5.1.0)
val ditto = DittoFactory.create(
    DittoConfig(
        databaseId = "my-app",
        connect = DittoConfig.Connect.SmallPeersOnly(),
        persistenceDirectory = dir.absolutePath,
    )
)
ditto.setOfflineOnlyLicenseToken(license)
ditto.sync.start()
```

v4 quirks verified against the 4.14.7 artifact (javap): every `DittoIdentity`
subclass except `Manual` takes the `DittoDependencies` instance as its **first**
constructor argument; `DefaultAndroidDittoDependencies` lives in package
`live.ditto.android`, not `live.ditto`. Identity-to-config mapping table:
[connect.md](connect.md#v4--v5-identity-mapping-414x-reference).

`disableSyncWithV3()` (4.14.x): mutating DQL is gated on the store's CRDT version ≥ V6,
which requires opting out of the legacy V3 sync protocol (source-verified:
`ffi/src/store/dql/ffi_access.rs` at `sdk-release-4.14.7`). Without the call,
`SELECT` and store observers work but every `INSERT`/`UPDATE`/`DELETE` throws
``DittoError.StoreError: <dql> Unsupported feature: Encountered `INSERT` statement.
Mutating DQL statements require that your application is updated to the latest
version. Please configure your app to disable sync with V3 to use DQL`` (executed,
4.14.7 Android). The call is **removed** in v5 — delete it during migration; the
protocol flag no longer exists.

`DQL_STRICT_MODE`: v4 defaults to strict (`true`), v5 defaults to lenient (`false`) and
the workaround is removed. **If the v4 app relied on strict-mode semantics**, set
`ALTER SYSTEM SET DQL_STRICT_MODE = true` via `store.execute` *before* `sync.start()`
when migrating, then plan the lenient migration mesh-wide
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). The type-inference semantics are owned by the
`data-modeling` skill — <https://docs.ditto.live/key-concepts>.

### Authentication

`DittoAuthenticationCallback` interface → `auth.expirationHandler = { ditto,
timeUntilExpiration -> … }` **property assignment of a suspend lambda** (no
`setExpirationHandler()` method exists; wrapping the body in `launch { }` breaks
ordering). Full detail: [connect.md](connect.md).

### Sync

`ditto.startSync()`/`stopSync()`/`isSyncActive` → `ditto.sync.start()`/`stop()`/
`isActive`. `find().subscribe()` is removed — `ditto.sync.registerSubscription(query,
args?)` only. Subscriptions reject `LIMIT`/`ORDER BY` with
`<dql> Unsupported feature: Limit or Order by`. See [sync.md](sync.md).

### Query model

The legacy collection API (`ditto.store["col"].find/upsert/…`) is removed; all access
is DQL through `ditto.store.execute`. The query-side delta (type inference, `DOCUMENTS`
vs `COLLECTION`, strict mode) is a separate guide:
<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-dql>, and semantics are owned by the `dql` skill —
<https://docs.ditto.live/dql/dql>. Kotlin call shapes: [store.md](store.md).

### Observers

Callback → `suspend` handler; `DittoSignalNext` removed (back-pressure is automatic);
`DittoLiveQuery`/`DittoLiveQueryEvent` removed. New `observe()` Flow and `collect()`
shapes. Full detail and the threading correction (Android handlers start on the main
thread) — [observers.md](observers.md).

### On-disk store migration

What is documented (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, "Default Persistence
Directory"):

- v5's default directory name includes the database ID: `ditto-{databaseId}` instead
  of v4's `ditto`. **This applies only to databases newly created by v5.**
- "v5 does not migrate existing databases to the new structure." An upgraded app
  opening the same directory keeps the v4 layout.
- You only need to set `persistenceDirectory` if v4 used a *custom* directory; to keep
  using it, pass the same path explicitly (the guide's sample resolves
  `context.filesDir.resolve("ditto")`).

What is **not** covered by the docs and was not executed here: whether the on-disk
binary format is converted in place on first v5 open, whether rollback to the v4 build
is safe afterwards, migration duration on a large store, and interruption behavior.
Treat an in-place 4.14.x → 5.x upgrade of a shipped fleet as needing a staged rollout
and a tested wipe-and-resync fallback until Ditto support confirms the behavior for
your store size. (Also recall `disableSyncWithV3()` above: a 4.14.x store that never
made the V6 switch behaves differently again — get the fleet onto `false`/V6 *before*
the v5 upgrade.)

### Removed APIs

| Removed in v5 | Replacement |
|---|---|
| `Ditto(dependencies, identity)` constructor, `Ditto.open(DittoAndroidConfig)` | `DittoFactory.create(DittoConfig(...))` (not suspend) |
| `DittoIdentity.*` (all five subclasses) | `DittoConfig.Connect.Server(url)` / `.SmallPeersOnly(privateKey?)` + `auth` APIs |
| `DefaultAndroidDittoDependencies`, `AndroidDittoDependencies`, `DittoDependencies`, `DittoBase` | none — config carries everything; Android `Context` via `DittoInitializer` (AndroidX Startup) |
| `DittoAndroidConfig(context, …)` | `DittoConfig(databaseId, connect, …)` — no `Context` param; `Connect.Server` takes `String`, not `URI` |
| `startSync()` / `stopSync()` / `isSyncActive` | `ditto.sync.start()` / `stop()` / `isActive` |
| `disableSyncWithV3()`, `runGarbageCollection()`, `getTransportDiagnostics()` | none — removed outright |
| `DQL_STRICT_MODE = false` workaround | v5 default; only set `= true` to preserve v4 behavior |
| Legacy collection API (`find`, `upsert`, `observeLocal`, `DittoLiveQuery`, `DittoPendingCursorOperation`…) | DQL via `store.execute`; observers via `registerObserver`/`observe`/`collect` |
| `DittoSignalNext`, `DittoSignalNextCallback`, `DittoChangeHandler*` | automatic back-pressure via `suspend` handlers |
| Non-suspend observer callbacks | `suspend` handlers — [observers.md](observers.md) |
| `DittoDiffer()` user-constructed | `(result, diff)` observer overloads |
| `presence.observe(handler)` → `DittoPresenceObserver` | `presence.observe()` → `Flow<DittoPresenceGraph>` |
| `ditto.callback` (transport conditions callback) | `ditto.transportCondition: Flow<DittoTransportConditionEvent>` |
| `DittoError` sealed class | `DittoException` sealed class — [errors.md](errors.md) |
| `java.io.Closeable` | `DittoResource` (extends `AutoCloseable`) |
| `peerKeyString`, `isConnectedToDittoCloud` | `peerKey`, `isConnectedToDittoServer` |
| `DiskUsage`, `DiskUsageItem`, `FileSystemType` | `DittoDiskUsage`, `DittoDiskUsageItem`, `DittoFileSystemType` |
| `ditto.sdkVersion` (instance property) | `Ditto.VERSION` (companion const). Note the v4 value is platform-tagged — `AndJ4.14.7_7506fa2fd0` observed on Android — while v5 returns the plain semver (`5.1.0`, executed) |
| `DittoTransportConfig` mutable data class | immutable, via `updateTransportConfig { … }` DSL — [transports.md](transports.md) |
| `enableAllPeerToPeer()` | per-transport DSL blocks |
| `DittoConfigConnect.Server(url: URI)` | `DittoConfig.Connect.Server(url: String)` |

### New in v5

- `DittoFactory.create(DittoConfig)`; immutable `val` config; `persistenceDirectory:
  String?` (was `File?`).
- `store.observe()` (Flow) and `store.collect()` (fully serialized) alongside
  `registerObserver()`.
- `presence.observe(): Flow<DittoPresenceGraph>`; `transportCondition` Flow.
- `@Serializable` reified argument binding and `DittoCborSerializable.Dictionary`
  result values (`.stringOrNull` etc. — `as` casts now throw).
- JVM/server target (`-jvm` variant + `ditto-binaries` classifier), KMP layout.
- 5.1.x adds: JOINs, composite indexes, `RETURNING`, `ADVISE`, Data Streams (preview).
- `com.ditto:ditto-tools-android:6.x` replaces `live.ditto:ditto-tools-android`.

### Migration checklist

Condensed from <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4> (which has the full list):

- [ ] `live.ditto.*` → `com.ditto.kotlin.*`; coordinate `live.ditto:ditto` →
      `com.ditto:ditto-kotlin`; raise `minSdk` to 24 if lower; Kotlin plugin to ≥ 2.2
      for 5.1.0 (its artifacts depend on `kotlin-stdlib` 2.3.21 — see *Kotlin
      toolchain* above; 2.3.21 is the executed pin).
- [ ] `Ditto(deps, identity)` → `DittoFactory.create(DittoConfig(databaseId, connect))`;
      delete the dependencies/identity types.
- [ ] Delete `disableSyncWithV3()`, `runGarbageCollection()`,
      `getTransportDiagnostics()`, `updateTransportConfig` websocket additions.
- [ ] Decide strict mode: rely on the v5 lenient default, or set
      `ALTER SYSTEM SET DQL_STRICT_MODE = true` before `sync.start()` to preserve v4
      behavior during the transition.
- [ ] `startSync()` → `ditto.sync.start()`; subscriptions `SELECT *` only (drop
      `LIMIT`/`ORDER BY`).
- [ ] Observers → suspend handlers or `observe()`/`collect()`; replace
      `runOnUiThread` with `withContext`; keep extraction inside the handler.
- [ ] `catch (e: DittoError)` → `catch (e: DittoException)`; result values are
      `DittoCborSerializable.Dictionary` — replace `as` casts with typed accessors.
- [ ] `expirationHandler` is a **property** assigned a suspend lambda.
- [ ] Set `persistenceDirectory` explicitly only if v4 used a custom directory.
- [ ] Smoke-test a release build with minification on (`NoSuchMethodError` —
      [testing.md](testing.md)).
