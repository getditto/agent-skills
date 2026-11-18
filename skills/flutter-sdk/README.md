# Ditto Flutter SDK Skill

## Contents

- [Scope](#scope)
- [Supported versions](#supported-versions)
- [Capability map](#capability-map)
- [Verification](#verification)
- [Installation](#installation)
- [Maintenance](#maintenance)

Agent skill for writing and reviewing Ditto **Flutter/Dart** SDK code. Human-facing; an
agent loads `SKILL.md` and only the references a task needs.

## Scope

Covers the `ditto_live` package on pub.dev, one package for iOS, Android, macOS, Windows,
Linux and Flutter Web: pubspec and platform setup, connecting, authentication,
transports, subscriptions, DQL execution, observers in a widget tree, attachments,
presence, logging, error handling, testing, and v4 to v5 migration. It is structured
against the twenty capability IDs of the repository's SDK skill template
(`docs/SDK-SKILL-TEMPLATE.md` in the agent-skills repository).

Deliberately **out of scope**; these have their own skills, and the references link the
public docs when a skill is not installed:

- DQL syntax and semantics → `write-dql`
- CRDT type selection and document structure → `data-modeling`
- Subscription semantics and mesh propagation → `sync-subscriptions`
- Transport strategy and mesh formation → `ditto-mesh-networking`
- Info.plist, entitlement and Android manifest declarations → `native-app-config`
  (shipped in the same plugin, so the links in `references/setup.md` resolve)
- Data Streams → `data-streams` (not in `ditto_live`)

## Supported versions

For new apps run `flutter pub add ditto_live`, which resolves the latest stable release;
**5.2.0 is this skill's knowledge baseline**, not a dependency recommendation. Every line
publishes `flutter: ">=3.19.0"`; use Flutter 3.24.5 or later. Everything below ran with
**Flutter 3.50.0 (Dart 3.14.0)**; debug builds unless marked.

| Line | Pin | macOS | iOS | Android | Windows | Linux | Web (Chrome) |
|---|---|---|---|---|---|---|---|
| 5.2.x | 5.2.0 | run (debug and release) | run (Simulator) | run (emulator, API 34); release APK built | run (CI) | run (CI) | run (DDC debug; dart2js release) |
| 5.1.x | 5.1.0 | run | run (Simulator, migration write phase) | APK built | not run | not run | run (DDC debug; dart2js release) |
| 5.0.x | 5.0.4 | run | Simulator build | APK built | not run | not run | run (DDC debug) |
| 4.14.x (LTS) | 4.14.7 | run (v4 fixture) | Simulator build | release APK built | not run | not run | not run |

"run" means the minimal app or probes executed and passed on that target (which ones:
[Verification](#verification)); "built" means `flutter build` only. No physical device was used for a passing run: iOS and
Android ran in the Simulator and the emulator only.

## Capability map

**Targets vocabulary for this SDK:** all | native | mobile | apple | android | web

`native` is iOS, Android, macOS, Windows and Linux; `mobile` is iOS and Android; `apple`
is iOS and macOS. Targets is the set of targets where a capability exists at all; a
reduced form on web does not change Support and is listed below the map.

| ID | Capability | Support | Evidence | Targets |
|----|-----------|---------|----------|---------|
| CAP-01 | Prerequisites, toolchain, package install | yes | executed | all |
| CAP-02 | Platform permissions, entitlements, build config | yes | executed | all |
| CAP-03 | Connecting: config, opening, persistence directory | yes | executed | all |
| CAP-04 | Authentication and identity | yes | executed | all |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | yes | executed | all |
| CAP-06 | Customizing transports | yes | executed | all |
| CAP-07 | Sync subscriptions and sync scopes | yes | executed | all |
| CAP-08 | Querying the store: executing DQL | yes | executed | all |
| CAP-09 | Transactions | yes | executed | all |
| CAP-10 | Indexing | yes | executed | all |
| CAP-11 | Observers, diffing and back-pressure | yes | executed | all |
| CAP-12 | Attachments | yes | executed | all |
| CAP-13 | Presence graph and connection requests | yes | executed | all |
| CAP-14 | Sync status and local commit tracking | partial | executed | all |
| CAP-15 | Logging, diagnostics and stats | partial | executed | all |
| CAP-16 | Error handling | yes | executed | all |
| CAP-17 | Device storage management and eviction | yes | executed | all |
| CAP-18 | Testing | yes | executed | all |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | executed | all |
| CAP-20 | Preview and platform-specific APIs | partial | executed | all |

Rows that are not `Support: yes`
([sync.md](references/sync.md#cap-14-sync-status),
[observability.md](references/observability.md#cap-15-logging-diagnostics-and-stats),
[preview.md](references/preview.md#cap-20-preview-apis)):

- **CAP-14 `partial`**: the Flutter SDK has no sync-status type, stream or callback. What
  exists is `QueryResult.commitID` (executed in CI on every 5.x line) and the DQL
  collection `system:data_sync_info`, whose `synced_up_to_local_commit_id` a writer
  compares with that commit. That query can hang on every released line while a peer
  connects and syncs (most often on 5.2.0 and 4.14.7; executed in a standalone two-peer
  app on macOS, not in CI): the native call never returns. The skill says to bound each
  poll with `.timeout()` and never await it on a path the UI waits for. Missing: per-document status, pending-upload counts and a
  callback on acknowledgement.
- **CAP-15 `partial`**: logging (`DittoLogger`, `customLogCallback`, `exportLogs`) is
  complete and executed. Missing: a disk-usage API. The `fs_*` keys of the DQL
  collection `system:system_info` stand in for it (executed in CI on macOS, Linux and
  Windows; empty for the first second or two after `Ditto.open`).
- **CAP-20 `partial`**: the preview APIs are `registerObserverV2` and
  `registerObserverWithSignalNext` (5.1.0+, executed on macOS and, signal-next, Chrome; marked
  `@experimental` from `package:meta`, so each use needs
  `// ignore: experimental_member_use`; their shape may change in any release) and
  `Store.experimentalSkipExecuteIsolateOffload` (5.1.0+; run by hand on 5.2.0 only, in a
  standalone app, not in the fixtures). Multicast (5.1.0+) is a private
  beta, off by default, not executed. Missing: Data Streams (not in `ditto_live` on any
  line) and supported encryption at rest (5.2.0 rejects `experimental.passphrase`; no key
  field exists).

Web degradations, which do not change Support ([web.md](references/web.md)):

- **CAP-03:** the store is in memory, survives `close()` within a page and is empty
  after a page load; `persistenceDirectory` has no effect.
- **CAP-06:** no peer-to-peer transport. Enabling one throws a `DittoException` from
  `sync.start()` on 5.2.0 and from `updateTransportConfig` on 5.0.4 and 5.1.0; sync is
  server-only (WebSocket, per the docs; no server run here).
- **CAP-08, CAP-11:** `execute` and observer decoding run on the UI thread; there is no
  worker isolate on web. Never build with `--wasm` on 5.1.0 or 5.2.0: every query result
  after the first repeats the first (an SDK defect, executed).
- **CAP-12:** bytes only: `newAttachment(path)` and `copyToPath` fail through their
  `Future`.
- **CAP-15:** `DittoLogger.exportLogs` throws `UnsupportedError` synchronously.
- **CAP-19:** no on-disk store on web, so only the API migration applies there.

Evidence notes. `executed` means the capability's core ran and passed on at least macOS
desktop (5.0.4, 5.1.0 and 5.2.0); where else it ran is in [Verification](#verification).
In brief: Linux and Windows (CI, 5.2.0) ran every native probe directory; the Android
emulator and the iOS Simulator (5.2.0) ran the minimal app and the store and observer
probes; Chrome ran the minimal app (CAP-03, CAP-05, CAP-07, CAP-08, CAP-11) and the web
probes (CAP-02, CAP-06, CAP-11, CAP-12, CAP-15, CAP-16, CAP-20). Where a row's web leg
did not run, the note says so and gives the source that shows the API exists on web
(`sdks/flutter/ditto_live/lib/src/bridge/wasm/`, the web bridge):

- **CAP-04 `executed`** covers the offline license (native and web), the
  missing-handler failure and a login refused by an unreachable server (macOS); a login
  round-trip against a Ditto server was not run. Web auth: not run;
  `bridge/wasm/auth.dart:38-57` @ `sdk-release-5.2.0` (login, logout).
- **CAP-07 `executed`** covers subscriptions (the minimal app on every target in the
  table, the subscription probes on macOS, Linux and Windows); sync scopes (`ALTER
  SYSTEM` through `execute`) were not run.
- **CAP-09 `executed`** on macOS, Linux, Windows, the Android emulator and the iOS
  Simulator (store probes). Not run on web; the web bridge implements it with
  `dittoffiStoreBeginTransactionAsyncThrows` and `dittoffiTransactionExecute`
  (`bridge/wasm/store.dart:441-491` @ `sdk-release-5.2.0`).
- **CAP-10 `executed`** (`CREATE INDEX IF NOT EXISTS`) on the same native targets as
  CAP-09. Not run on web; it is a DQL statement sent through the same `execute` call the
  web runs executed (`dittoffiTryExecStatement`, `bridge/wasm/store.dart:13` @
  `sdk-release-5.2.0`).
- **CAP-13 `executed`** covers two instances in one process over TCP loopback: presence,
  sync, and a connection-request handler that denies or throws (macOS on 5.0.4 to 5.2.0;
  Linux and Windows on 5.2.0). Not run on web, iOS or Android; the web bridge has the
  presence graph, observer and connection-request handler (`bridge/wasm/presence.dart:25-135`
  @ `sdk-release-5.2.0`).
- **CAP-14 `executed`**: `commitID` on macOS (5.0.4 to 5.2.0), Linux and Windows (5.2.0);
  `system:data_sync_info` in manual runs on macOS only. Not run on web; the web bridge
  reads the commit ID (`dittoffiQueryResultCommitId`, `bridge/wasm/store.dart:80-84` @
  `sdk-release-5.2.0`), and the collection is a DQL query through the same `execute`.
- **CAP-15 `executed`**: logging on macOS and web; `exportLogs` on macOS (on web, its
  synchronous `UnsupportedError`); the `system:system_info` disk keys on macOS, Linux
  and Windows, not on web.
- **CAP-17 `executed`** (`EVICT`) on the same native targets as CAP-09. Not run on web;
  a DQL statement through the same `execute` as CAP-10.
- **CAP-18 `executed`** covers widget tests with fakes on the host and
  `integration_test` on macOS, Linux, Windows, the Android emulator, the iOS Simulator
  and Chrome (`flutter drive`); Ditto itself does not load under a host `flutter test`.
- **CAP-19 `executed`** covers the 4.14.7 API in the v4 fixture on macOS and the 5.1.0 →
  5.2.0 default-directory upgrade on macOS and the iOS Simulator. An on-disk 4.14 → 5.x
  upgrade was not run, and 4.14.7 was not run on web. Its `pubspec.yaml` lists `web`
  among its platforms (`flutter/ditto_live/pubspec.yaml:74-80` @ `sdk-release-4.14.7`)
  and it ships a web bridge (`flutter/ditto_live/lib/src/core/wasm/` @
  `sdk-release-4.14.7`).

## Verification

**Executed against:** ditto_live 4.14.7, 5.0.4, 5.1.0 and 5.2.0, Flutter 3.50.0, on macOS
27.2.1 arm64 (Xcode 27.2, CocoaPods 1.17.0, Chrome 157 with ChromeDriver 157) and on
GitHub-hosted runners (ubuntu-24.04, windows-latest, macos-26 arm64). Per target:

- **macOS desktop:** the minimal app and every probe directory at or below each 5.x line
  (`integration_test`, debug), locally and in CI; a 5.2.0 release `.app` run directly;
  the 4.14.7 v4 fixture; the 5.1.0 → 5.2.0 default-directory migration.
- **iOS:** the iPhone 17 Pro Simulator (iOS 26.5) in CI on 5.2.0 and the migration's
  5.1.0 write phase; an iOS 27.1 Simulator locally; simulator builds on 4.14.7 and 5.0.4.
- **Android:** an API 34 x86_64 emulator in CI on 5.2.0; APK builds on every line,
  release manifests inspected with aapt2.
- **Windows and Linux:** CI only, 5.2.0 (Linux under `xvfb-run`).
- **Web:** headless Chrome: `flutter drive` debug (DDC) on 5.0.4, 5.1.0 and 5.2.0;
  release dart2js and `--wasm` bundles on 5.1.0 and 5.2.0.
- **Two peers:** two instances in one process over TCP loopback on macOS, 5.0.4 to 5.2.0.
- **By hand, not in CI:** hot restart (`flutter run`, macOS and Chrome), the
  `system:data_sync_info` sync-status probe and a standalone app that reproduced its hang
  on 4.14.7, 5.0.4, 5.1.0 and 5.2.0, and the host `flutter test` attempt.

Per-run results, commands and the SDK defects the probes assert are in the harness
README (`tests/flutter-sdk/README.md` in the agent-skills repository); the web probe
results per ID are in `tests/flutter-sdk/web-results/5.2.0.md`.

**Verified from source:** `sdks/flutter/ditto_live/` in the Ditto repository at
`sdk-release-4.14.7`, `sdk-release-5.1.0` and `sdk-release-5.2.0`, and the ditto_live 5.0.4
archive from pub.dev (there is no 5.0.4 release tag), for every claim marked "source" in
the references: isolates per call, retention, error mapping, the v4 identity API.

**Not verified:** a physical iOS or Android device; Bluetooth LE, LAN, AWDL, Wi-Fi Aware
or multicast between devices (radios are not exercised; all two-peer runs use TCP
loopback with peer-to-peer off); sync with a Ditto server, including a login round-trip
and web sync; Android runtime permission requests; Linux AArch64; Firefox, Safari and
Edge; an on-disk 4.14 → 5.x upgrade; app lifecycle callbacks on a device (driven through
the test binding only); hot restart beyond the manual macOS and Chrome runs.

**Last verified:** 2026-11-18.

## Installation

```bash
# Claude Code
/plugin marketplace add getditto/agent-skills
/plugin install ditto-flutter@ditto-plugins
```

The plugin ships this skill and `native-app-config`. For other agent tools, see the
agent-skills repository README.

## Maintenance

When `ditto_live` ships a new version:

1. Re-read `sdk/latest/release-notes/flutter.mdx` and the pub.dev changelog.
2. Update `references/versions.md` first; it is the source of truth for version claims.
3. Add the line to the harness pins, run the minimal app and the probes on it, and update
   **Supported versions** and **Verification**.
4. Re-check the capability map: a `partial` row may have changed.
