# Generating a runnable Gradle project — Kotlin

> Rules for producing a **complete, compilable** Android or JVM project with Ditto —
> the Kotlin analogue of a project generator. Every rule exists because the failure
> was observed (see [`errors.md`](errors.md)) or because the build genuinely cannot
> work otherwise. The reference implementations these rules describe are
> [`../../../tests/kotlin-sdk/minimal-app/`](../../../tests/kotlin-sdk/minimal-app)
> (JVM, v5) and [`../../../tests/kotlin-sdk/android-app/`](../../../tests/kotlin-sdk/android-app)
> (Android, v4) — prefer copying them to typing from memory.

## Mandatory rules, in order

1. **Determine the version line before writing any code.** Grep the existing build
   files: `com.ditto:ditto-kotlin` → v5; `live.ditto:ditto` → 4.14.x (Android-only).
   If neither exists, generate for **5.1.x** and say you assumed it. Never mix
   namespaces: v5 is `com.ditto.kotlin.*`, v4 is `live.ditto.*`.
2. **Use only coordinates from [`versions.md`](versions.md).** Do not invent
   artifacts. v5 JVM requires **two** dependencies — `com.ditto:ditto-kotlin` plus the
   `ditto-binaries` classifier artifact for the host — or the first
   `DittoFactory.create` throws `IllegalStateException: Unable to find binary
   'libdittoall.dylib' …` (executed).
3. **Pin the toolchain that is known to work:** Kotlin Gradle plugin 2.3.x
   (executed: 2.3.21 — 2.0.x fails on the 5.x artifacts' stdlib metadata), JDK 17,
   `kotlinx-coroutines` 1.10.x, Android `minSdk` 24 / `compileSdk` 36.
4. **One `Ditto` instance, owned at application scope** (Android `Application`/DI
   singleton; JVM top-level). Never construct it in an Activity or per-request.
5. **The config is immutable and complete at construction:** `DittoConfig(databaseId,
   connect, persistenceDirectory?)`. There is no setter to forget. Copy the cloud URL
   verbatim from the portal (`Connect.Server(url: String)` — an `https://` URL, never
   `wss://`, never derived from the database ID).
6. **Observers are lifecycle-bound Flows by default:** expose
   `observe(…) { extract }.stateIn(viewModelScope, …)`; collect with
   `collectAsStateWithLifecycle()` in Compose. Generate `registerObserver` only when
   the consumer is imperative, and then always pair it with a visible `close()`.
   Extraction happens **inside** the lambda — see
   [`observers.md`](observers.md).
7. **Auth is a property assignment of a suspend lambda, set before `sync.start()`:**
   `ditto.auth?.expirationHandler = { d, _ -> d.auth?.login(token, .development()) }`.
   There is no `setExpirationHandler()`; do not wrap the body in `launch { }`.
8. **Android manifest:** no permission declarations of your own are needed (the SDK
   merges them); do not add a manual `DittoInitializer` entry. Add the runtime
   permission flow (`DittoSyncPermissions` → `ditto.refreshPermissions()`) where the
   app first needs P2P.
9. **Release builds need the keep rule** — emit `proguard-rules.pro` with
   `-keep class com.ditto.** { *; }` and wire it into the release build type, or the
   minified build crashes with `NoSuchMethodError … DittoFFI`.
10. **Generate a diagnostics surface.** A new project is not done until its author can
    see whether sync works — see below.
11. **Verify by building.** The deliverable is a project that compiles; run
    `gradle build` (or `installDebug`) before presenting it. The minimal-app
    transcripts show what a healthy first run prints.

## The diagnostics screen (generate it by default)

A single debug screen or JVM block that answers "is it working?" at a glance:

- `Ditto.VERSION` (v5) — v4 uses `ditto.sdkVersion` and prints a platform-tagged
  string like `AndJ4.14.7_7506fa2fd0`.
- `ditto.isActivated` and `ditto.sync.isActive`.
- Peer count: `ditto.presence.observe()` → `graph.remotePeers.size` collected into a
  `StateFlow`.
- Last sync timestamps: observe `SELECT * FROM system:data_sync_info`
  ([`sync.md`](sync.md)).
- A "copy logs" affordance: `DittoLog.exportToFile(path)`
  ([`observability.md`](observability.md)).
- Transport warnings: collect `ditto.transportCondition`
  ([`transports.md`](transports.md)) — this is where "BLE permission missing" shows up
  instead of failing.

## Testing the generated project

Point the author at [`testing.md`](testing.md): JVM unit tests run the real SDK with
`SmallPeersOnly` + a temp persistence directory; two-emulator P2P testing must ride a
shared `Connect.Server` WebSocket URL (the emulator supports no radios — only
WebSockets per `sdk/latest/compatibility/kotlin`).

## Coming from the Swift SDK?

Common confusions when generating Kotlin after seeing Swift Ditto code:

| Swift SDK | Kotlin SDK (v5) |
|---|---|
| `Ditto(identity:)` / `Ditto.open(config:)` | `DittoFactory.create(DittoConfig(...))` — not suspend |
| `ditto.store["cars"].findAll().observe()` | `ditto.store.observe("SELECT * FROM cars") { … }` (Flow) |
| Combine publishers / `.assign(to:)` | `Flow` + `stateIn(scope, SharingStarted…)` |
| `ditto.startSync()` | `ditto.sync.start()` |
| `try await ditto.store.execute(...)` | `ditto.store.execute(...)` — all of store is `suspend` |
| App ID (`appId`) | `databaseId` |

Everything else — DQL, subscriptions, presence concepts — is shared and owned by the
concept skills.
