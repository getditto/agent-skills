# Generating a runnable Gradle project — Kotlin

> Rules for producing a **complete, compilable** Android or JVM project with Ditto —
> the Kotlin analogue of a project generator. Every rule exists because the failure
> was observed (see [`errors.md`](errors.md)) or because the build genuinely cannot
> work otherwise. The reference implementations these rules describe are the JVM v5
> and Android harness projects, whose build files are in
> [reference-projects.md](reference-projects.md) — prefer copying them to typing from
> memory. The Android project builds either line
> (`-PdittoLine=v4|v5`) and pins AGP 9.5.0; its v5 leg was last run on a Pixel 10a
> (5.2.0, 5.1.0, 5.0.3) with AGP 9.4.1 at `compileSdk 36`.

## Mandatory rules, in order

1. **Determine the version line before writing any code.** Grep the existing build
   files: `com.ditto:ditto-kotlin` → v5; `live.ditto:ditto` → 4.14.x (Android-only).
   If neither exists, resolve the latest stable release from Maven Central as described
   in [setup.md](setup.md); 5.2.0 is the latest version this skill knows about. Never mix
   namespaces: v5 is `com.ditto.kotlin.*`, v4 is `live.ditto.*`.
2. **Use only coordinates from [`versions.md`](versions.md).** Do not invent
   artifacts. v5 JVM requires **two** dependencies — `com.ditto:ditto-kotlin` plus the
   `ditto-binaries` classifier artifact for the host — or the first
   `DittoFactory.create` throws `IllegalStateException: Unable to find binary
   'libdittoall.dylib' …` (executed).
3. **Pin the toolchain that is known to work:** JDK 17, `kotlinx-coroutines` 1.11.x,
   Android `minSdk` 24 / `compileSdk` 36 (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>;
   the 5.x AARs enforce the 36 floor through AAR metadata — a 35 build fails
   `CheckAarMetadata`, executed; the v4 leg still builds at 35).
   Kotlin Gradle plugin **≥ 2.2 for 5.1.0 and 5.2.0** — their artifacts depend on `kotlin-stdlib`
   2.3.21 and the compiler reads metadata at most one minor newer; security-updated JVM pin 2.4.21
   on JVM (see [`versions.md`](versions.md) § Kotlin toolchain). Android projects on
   AGP 9: use built-in Kotlin — applying `org.jetbrains.kotlin.android` fails the build
   (executed on both the v4 and the v5 Android legs).
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
   `ditto.auth?.expirationHandler = { d, _ -> d.auth?.login(token, DittoAuthenticationProvider.development()) }`.
   There is no `setExpirationHandler()`; do not wrap the body in `launch { }`.
8. **Android manifest:** no *transport* permission declarations of your own are
   needed (the SDK merges them); do not add a manual `DittoInitializer` entry. The
   one exception is `DefaultDittoForegroundService`: if you declare it, the app must
   also declare `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` and
   `POST_NOTIFICATIONS` ([`preview.md`](preview.md)). Add the runtime permission flow
   (`DittoSyncPermissions` → `ditto.refreshPermissions()`) where the app first
   needs P2P.
9. **Release builds need the keep rules** — emit `proguard-rules.pro` with
   `-keep class com.ditto.** { *; }` **and**
   `-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }`
   (TLS to Ditto Server breaks without the second) and wire them into the release
   build type, or the minified build crashes with `NoSuchMethodError … DittoFFI`.
   5.1.0's AARs bundle `consumer-rules.pro` for SDK internals (5.1.0 Kotlin changelog,
   #SDKS-2626), so the init crash may not reproduce there — the install guide still
   requires both rules; keep them.
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
- A "copy logs" affordance: `DittoLogger.exportToFile(path)`
  ([`observability.md`](observability.md)).
- Transport warnings: collect `ditto.transportCondition`
  ([`transports.md`](transports.md)) — this is where "BLE permission missing" shows up
  instead of failing.

## Testing the generated project

Point the author at [`testing.md`](testing.md): JVM unit tests run the real SDK with
`SmallPeersOnly` + a temp persistence directory; two-emulator P2P testing must ride a
shared `Connect.Server` WebSocket URL (the emulator supports no radios — only
WebSockets per <https://docs.ditto.live/sdk/latest/compatibility/kotlin>).

## Coming from the Swift SDK?

Common confusions when generating Kotlin after seeing **v4** Swift Ditto code (Swift v5
has the same `DittoConfig`/`sync`/DQL shape as Kotlin v5):

| Swift SDK (v4) | Kotlin SDK (v5) |
|---|---|
| `Ditto(identity:)` / `Ditto.open(config:)` | `DittoFactory.create(DittoConfig(...))` — not suspend |
| `ditto.store["cars"].findAll().observe()` | `ditto.store.observe("SELECT * FROM cars") { … }` (Flow) |
| Combine publishers / `.assign(to:)` | `Flow` + `stateIn(scope, SharingStarted…)` |
| `ditto.startSync()` | `ditto.sync.start()` |
| `try await ditto.store.execute(...)` | `ditto.store.execute(...)` — all of store is `suspend` |
| App ID (`appId`) | `databaseId` |

Everything else — DQL, subscriptions, presence concepts — is shared and owned by the
concept skills.
