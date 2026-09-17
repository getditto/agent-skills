# `tests/swift-sdk` — executable verification for `skills/swift-sdk`

Every claim in the Swift SDK skill marked **executed** was produced here. The same
sources build and run against Ditto **4.14.6**, **5.0.3** and **5.1.0**, and compile for
macOS, the iOS Simulator, an iOS device and Mac Catalyst.

```
Package.swift                          version pin read from $DITTO_SWIFT_VERSION
Sources/
  SkillSupport/                        env + disposable-instance helpers
  MinimalApp/                          the normative program in examples/minimal-app.md
  UIPatterns/                          SwiftUI, UIKit and AppKit samples, compile-checked
  PersistenceProbe/                    writes/reads a store for the cross-version matrix
Tests/SwiftSDKSkillTests/              64 Swift Testing cases
scripts/
  run.sh                               build, sign, run the tests (and the app)
  build-platforms.sh                   compile for every supported Apple platform
  persistence-matrix.sh                upgrade, rollback and legacy-directory fallback
```

## Prerequisites

- macOS on Apple silicon, Xcode 16 or later (verified on Xcode 27 / Swift 6.4).
  5.1.0 ships no `x86_64` slice, so an Intel Mac cannot run the 5.1.0 legs.
- `DITTO_OFFLINE_LICENSE` in the gitignored repo-root `.env` — copy `.env-sample`.
  Everything here runs offline-only and the SDK will not accept work without it.
- Optional: `DITTO_DATABASE_ID`, and `DITTO_URL` + `DITTO_TOKEN` to additionally exercise
  the server-authentication path. Without those, the two server tests skip themselves and
  the minimal app runs in offline mode.

Environment variables already set take precedence over `.env`, matching
`tests/lib/load-env.mjs`.

## Running

```bash
cd tests/swift-sdk

./scripts/run.sh 5.1.0                  # tests on one version
./scripts/run.sh --all                  # 4.14.6, 5.0.3 and 5.1.0 in sequence
./scripts/run.sh 5.1.0 --app            # tests, then the minimal app
./scripts/run.sh 5.1.0 --app --offline  # force the app's offline mode

./scripts/build-platforms.sh --all      # 12 builds: 3 versions x 4 platforms
./scripts/persistence-matrix.sh         # cross-version on-disk behaviour
```

Expect a few minutes on the first run of each version: the XCFramework is around 100 MB
per version and SwiftPM downloads it once.

## Why the runner is not just `swift test`

Two environment problems make the obvious command fail. Both are documented for users in
`skills/swift-sdk/references/testing.md`; `scripts/run.sh` works around them.

1. **`swift test` exports `NO_COLOR=1`.** Ditto's Rust core reads `NO_COLOR` as its
   `--disable-color` option, which accepts only `true` or `false`, so the process panics
   during initialization before any test runs. Reproduced on all three version lines.
   There is no flag that stops `swift test` setting it, so the runner drives SwiftPM's
   own `swiftpm-testing-helper` with the variable cleared.
2. **The published XCFramework is unsigned**, and SwiftPM copies it out of its artifact
   cache without signing. macOS will not load an unsigned library into the test host, so
   the runner ad-hoc signs it after building. Xcode app and test targets sign
   automatically; this is a command-line-only problem.

`scripts/run.sh` also clears `.build/out` between versions, because a stale build
directory otherwise keeps the previous version's framework and the run silently reports
the wrong line. `build-platforms.sh` uses a per-version `-derivedDataPath` for the same
reason — reusing one fails with *"cannot load underlying module for 'DittoSwift'"*.

## How the version pin works

`Package.swift` reads `DITTO_SWIFT_VERSION` when SwiftPM evaluates the manifest and pins
`getditto/DittoSwiftPackage` to it exactly. When the value starts with `4.`, the targets
also compile with `-DDITTO_V4`, which selects:

- `@preconcurrency import DittoSwift` — 4.14.x predates the `Sendable` conformances and
  Swift 6 language mode otherwise rejects the same source with *"sending 'ditto' risks
  causing data races"*.
- `ditto.disableSyncWithV3()` — 4.14.x rejects every mutating DQL statement until it is
  called.
- `ditto.activated` instead of `isActivated`, `diskUsage.exec` instead of
  `diskUsage.item`, and the file-path-only attachment API.

Tests that cannot exist on a line are disabled with a Swift Testing `.enabled(if:)` trait
**and** `#if` guards, because a trait is a runtime condition and the code still has to
compile.

## What is not covered

Radio behaviour. This is one offline process, so BLE, AWDL, mDNS discovery, multi-peer
convergence, connection requests and `DittoConnectionType` values other than the local
peer's are out of reach, and the skill documents them from SDK source instead.

Nothing here runs on `x86_64`, and no test downgrades below 5.0.2 / 4.14.6.
