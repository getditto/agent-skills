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
Tests/SwiftSDKSkillTests/              93 @Test declarations (3 parameterized)
scripts/
  run.sh                               build, verify the pin, sign, run the tests,
                                       and assert the minimal app's output
  build-platforms.sh                   compile for every supported Apple platform
  persistence-matrix.sh                upgrade, rollback, direct version pairs, and the
                                       default/legacy directory fallbacks — all asserted
```

## Prerequisites

- macOS on Apple silicon, Xcode 16 or later (verified on Xcode 27 / Swift 6.4).
  5.1.0 ships no `x86_64` slice, so an Intel Mac cannot run the 5.1.0 legs.
- `DITTO_OFFLINE_LICENSE` in the gitignored repo-root `.env` — copy `.env-sample`.
  Everything here runs offline-only and the SDK will not accept work without it.
- Optional: `DITTO_DATABASE_ID`, and `DITTO_URL` + `DITTO_TOKEN` to additionally exercise
  the server-authentication path. Without those, the one server test skips itself and
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

`scripts/run.sh` also clears `.build/out` and `Package.resolved` between versions and
then **verifies** that every resolved artifact URL carries the requested version, because
a stale build directory otherwise keeps the previous version's framework. The suite's
`the build is pinned to the version it claims` case is the in-process backstop.
`build-platforms.sh` uses a per-version `-derivedDataPath` for the same reason — reusing
one fails with *"cannot load underlying module for 'DittoSwift'"* — and
`persistence-matrix.sh` passes `--expect-version` to each probe so a degenerate
same-version pair cannot masquerade as a cross-version one.

The runner discovers the single built `.xctest` product: native SwiftPM and Swift
Build name it differently. `python3 test_runner.py` checks both naming conventions,
missing/ambiguous products, and platform-runner startup without an existing `.build`.

**Every script asserts.** `PersistenceProbe read` exits non-zero unless the document, its
field and the index survived; `run.sh --app` greps the minimal app's output rather than
trusting its exit code; and `build-platforms.sh` prints compiler diagnostics on failure
instead of discarding them.

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

## Proving the harness can fail

Each guard below has been checked by deliberately breaking the thing it guards. If you
change one, re-run its negative control — in a scratch copy, or with a `trap` scoped to
the single file you edited.

| Guard | Break it by | Expected |
|---|---|---|
| Platform matrix compiles `UIPatterns` | a type error inside the `#if canImport(UIKit)` region | an iOS leg fails and the run stops |
| …and the AppKit region | a type error inside `#if canImport(AppKit)` | the macOS leg fails and the run stops |
| Persistence legs assert | reading a document that was never written | probe exits 1 with three `FAIL:` lines |
| …and run the right SDK | `--expect-version` naming another version | `FAIL: expected SDK X, running Y` |
| …and open where they claim | `--expect-directory` naming another path | `FAIL: expected directory X, got Y` |
| Cancellation is real | deleting `observer.cancel()` (test setup, so this proves the assertion is live, not that the SDK is pinned) | `cancelStopsDelivery` fails on `isCancelled` — the delivery-count assertion after it is a positive control, not separately falsifiable |
| `ObserverBridge.cancel()` ends the stream | deleting `continuation.finish()` from it | `cancelReleasesASuspendedConsumer` fails in ~6s (bounded, not a hang) |
| Bounded stream coalesces | forcing `.unbounded` | `bufferingPolicyDecidesWhatSurvives(latestOnly: true)` fails |
| …and an unbounded one does not | forcing `.bufferingNewest(1)` | `bufferingPolicyDecidesWhatSurvives(latestOnly: false)` fails |
| The login deadline releases its caller | restoring the task-group shape in `Deadline.swift` | `neverCompletingBodyTimesOut` fails (in ~8s, not a hang) |
| …and honours cancellation | deleting `withTaskCancellationHandler` | `cancellationReleasesTheCaller` fails: blocked 31.9s of a 30s deadline, reports `timedOut` |
| …exactly once | deleting `guard !finished` from `Gate` | the run aborts: `tried to resume its continuation more than once` |
| The pasted copy keeps up | drifting `Gate` in `MinimalApp.swift` | `validate-sdk-skills.py` reports it has drifted from `Deadline.Gate` |
| `onTermination` cancels | deleting the `onTermination` assignment | `terminationCancelsObserver` fails |
| …and does not fire when a consumer just stops reading | `finish()`ing right after the `break` (test setup, as above) | `onTerminationFiresOnFinishOnly` fails |
| Identity is not positional | returning `""` from `Car.identity(of:)` | `carIdentityHandlesNonStringIDs` fails |
| Re-authentication retries | `throw error` on every attempt instead of the last | `rethrowsAfterTheLastAttempt` and `cancellationAbandonsRemainingAttempts` fail |
| …with growing backoff | `backoff *= 1` | `backoffGrows` fails: reported delays `[0.01, 0.01, 0.01, nil]` |
| …and stops on a permanent failure | `isRetryable` ignored | `nonRetryableStopsAtOnce` fails |
| …and does not run when already cancelled | delete `Task.checkCancellation()` | `alreadyCancelledRunsNothing` fails |
| …and gives up when cancelled | `try?` around the backoff sleep | `cancellationAbandonsRemainingAttempts` fails: 10 attempts and a `Boom`, not 1 and a `CancellationError` |
| SE-0338 moves nonisolated async work off the caller's main actor | marking the probe `@MainActor` | `nonisolatedAsyncLeavesTheCallersActor` fails; the separate Ditto open timing is diagnostic |
| `Deadline.value` releases a caller whose work cannot be cancelled | rebuilding it on `withThrowingTaskGroup` | `valueBoundsNonCancellableWork` fails in ~10s (the group shape hangs; this test polls so it cannot) |
| A half-failed `start()` leaves nothing behind | deleting the rollback `defer` in `DittoAppModel.start()` | `partialStartRollsBack` fails 3 assertions, including `retry registered 2 subscriptions` |
| Minimal app is checked | making it write `Honda` | `run.sh --app` exits 1 |

## What is not covered

Radio behaviour. This is one offline process, so BLE, AWDL, mDNS discovery, multi-peer
convergence, connection requests and `DittoConnectionType` values other than the local
peer's are out of reach, and the skill documents them from SDK source instead.

Nothing here runs on `x86_64`, and no test downgrades below 5.0.2 / 4.14.6.
