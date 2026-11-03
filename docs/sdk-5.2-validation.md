# SDK 5.2.0 skill validation

Validated on 2026-11-03 on macOS arm64. This is a record of the 5.2.0 knowledge
baseline; it is not a recommendation to keep new applications pinned to that release.
Swift/SwiftPM and Kotlin/Maven instructions resolve the latest stable release when
generating a new app, record the selected version, and check newer release notes.

## Scope and source review

All seven canonical skills currently on `main` were reviewed. This PR is based on
`main` and excludes PR #36’s unmerged JavaScript and shared native-configuration
skills, plugins and test fixtures:

| Skills | 5.2.0 coverage |
|---|---|
| `swift-sdk`, `kotlin-sdk` | Raw-key encryption, store deletion/lifetimes, startup parameters, binding fixes, diagnostics, NGN names, latest stable dependency selection |
| `write-dql` | Four-version compatibility tables, DELETE/EVICT USE IDS effects, planner correctness fixes, diagnostics and startup configuration |
| `data-modeling`, `sync-subscriptions`, `ditto-mesh-networking` | Document-size enforcement during replication, observer behavior, transport changes and diagnostics |
| `data-streams` | New startup parameter names and invalid NGN combination; preview status retained |

Primary sources: [Swift/common release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/swift),
[Kotlin release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/kotlin),
[Node release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/javascript-nodejs),
[encryption](https://docs.ditto.live/sdk/latest/sync/encryption-at-rest),
[virtual collections](https://docs.ditto.live/dql/virtual-collections), and
[support bundles](https://docs.ditto.live/sdk/latest/deployment/support-bundles).
Language references also cite the published 5.2.0 API documentation.

**Swift API discrepancy:** the release notes advertise `Ditto.close()`, but the
published 5.2.0 public Swift interface does not expose it. An explicit compile probe
confirmed the missing member. Guidance uses release of the final strong reference;
the encryption test verifies that deletion fails while open and succeeds after release.

## Executed validation

Commands are relative to the repository root unless a working directory is named.
Licensed tests load the existing local `.env`; no credentials or generated stores
belong in committed artifacts. The independent port reruns the DQL matrix, Swift
and Kotlin runtime suites, Apple/Android builds, generated starter checks, Python
checks, packaging and dependency validation. The unchanged data-modeling harness
retains its earlier six-case execution from this update.

| Check | Command / method | Result |
|---|---|---|
| DQL matrix | `cd tests/dql && npm test` | 258 outcomes on each of 4.14.6, 5.0.3, 5.1.0 and 5.2.0; 1,032 total, no unexpected failures |
| DQL 5.2 regressions | Included in `test:v52`: `node runner/sdk52.mjs` | Startup override, DELETE/EVICT read-back, mixed index ordering, full documents, general projection-alias ordering, constant-left span, multi-property ANY, diagnostics, local support capture and invalid NGN combination pass |
| Scoped JOINs | `DITTO_SDK_VERSION=5.2.0 node tests/skill-context/check-scoped-joins.mjs` with `NO_COLOR` unset | Pass |
| Swift runtime | `tests/swift-sdk/scripts/run.sh 5.2.0 --app --offline` | 110 tests in 18 suites pass; minimal-app transcript verified |
| Swift platform fixture | `tests/swift-sdk/scripts/build-platforms.sh 5.2.0` | macOS, iOS Simulator, iOS device and Mac Catalyst compile |
| Generated Swift app | Generator with default `--sdk-version latest`; build generated project and run `tests/swift-sdk/scripts/test-starter.py` | Live SwiftPM tags resolved 5.2.0; macOS canonical starter runtime probe passes 6 checks; macOS, iOS Simulator and Catalyst builds pass |
| Kotlin JVM | In `tests/kotlin-sdk/minimal-app`: `./gradlew test run -PdittoVersion=5.2.0` with `NO_COLOR` unset | 19 tests pass; minimal-app transcript verified |
| Kotlin Android | In `tests/kotlin-sdk/android-app`: `./gradlew assembleDebug -PdittoLine=v5 -PdittoVersion=5.2.0 -PdittoAbi=arm64-v8a` | Compilation succeeds |
| Data modeling | In `tests/data-modeling`: `npm run run && npm run score`, using the configured model command | All 6 cases pass with 100% finding recall (27/27), no anti-findings and no skipped cases |
| Function semantics | Included in each DQL version script: `runner/functions.mjs` | 73 representative cases per version, 292 total; exact alphabetical-index coverage check |
| Sync degradation | Included in `test:v52`: `runner/sync-degradation52.mjs` | Two local 5.2.0 peers each hold a valid 3 MiB field; the over-limit merge is rejected on both peers, the intended degradation is reported, and another document continues syncing |
| Generator/packaging checks | `python3 -m unittest discover -s tests/swift-sdk -p 'test_*.py'` | 21 tests pass, including stable-release sorting, prerelease exclusion, lookup failure, explicit pins, newer-version generation and default CLI resolution/failure |
| Context guard | `python3 tests/skill-context/test_contract.py` | 5 negative-control tests pass |
| Structure and metadata | `scripts/validate-sdk-skills.py`; SDK plugin packaging `--check`; JSON/frontmatter/link checks; `git diff --check` | Pass; SDK entry-point length warnings remain for Swift and Kotlin |
| Independent release packaging | Build release manifest and both SDK installation archives | Exactly seven released skills; Swift and Kotlin archives build without PR #36 |
| Dependency age/integrity | `python3 scripts/check-dependency-age.py` | 149 npm versions, 7 Actions and 15 Maven pins pass |
| Maven resolution | Read Maven Central metadata and request matching native artifact | Highest stable release is 5.2.0; matching macOS arm64 binary is available |

The DQL matrix has 205/222/252/252 successful queries and 53/36/6/6 expected
unsupported-query failures respectively. Expected failures are explicit version gates,
not failed validation. Fixed SDK versions in test fixtures keep this evidence reproducible.

## Evidence limits

- Apple device and Kotlin Android results above are compile evidence; this change
  did not rerun physical-device or emulator runtime checks.
- Data Streams runtime tests use two local peers over TCP loopback. BLE, AWDL,
  Wi-Fi Aware recovery and physical multicast behavior remain release-note evidence.
- Document-size degradation and independent-document progress were executed over TCP
  loopback. Eviction/re-sync recovery and production migration/rollback workflows remain
  source-reviewed. Local encryption, reopen, wrong-key rejection and deletion were
  executed on disposable stores. Android Keystore wrapping was not integration-tested.
- The projection-alias test verifies general ordering. The specific sort-before-fetch
  planner fix is supported by release notes; this harness has no reproducer for that plan.
- Claims attached to older executed runs retain their original version labels;
  this update does not relabel historical evidence as a new 5.2.0 execution.

The follow-up [adversarial review](sdk-5.2-review.md) records unanimous reviewer
agreement, the resulting corrections, and negative controls for the added tests.
