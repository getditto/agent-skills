# Ditto Swift SDK Skill

## Contents

- [Scope](#scope)
- [Supported versions](#supported-versions)
- [Capability map](#capability-map)
- [Verification](#verification)
- [Getting started and installation](#getting-started-and-installation)
- [Maintenance](#maintenance)

Agent skill for writing and reviewing Ditto **Swift** SDK code — iOS, iPadOS,
macOS (AppKit) and Mac Catalyst, with SwiftUI, UIKit and AppKit.

## Scope

Covers the SwiftPM package `https://github.com/getditto/DittoSwiftPackage` (product
`DittoSwift`) — connecting, authentication, transports, subscriptions, DQL execution,
observers and `DittoDiffer`, attachments, presence, observability, error handling,
testing, and the 4.14.x → 5.x delta. Structured against the twenty capability IDs defined
in [`docs/SDK-SKILL-TEMPLATE.md`](../../docs/SDK-SKILL-TEMPLATE.md).

Deliberately **out of scope** — these have their own skills:

- DQL syntax and semantics → `dql`
- CRDT type selection and document structure → `data-modeling`
- Subscription semantics and mesh propagation → `sync-subscriptions`
- Transport strategy and mesh formation → `ditto-mesh-networking`
- The v4 → v5 migration *procedure* → the published guides at
  <https://docs.ditto.live/sdk/latest/migration-guides/swift-v4> and
  <https://docs.ditto.live/sdk/latest/migration-guides/swift-dql>. This skill owns the
  version-gated *facts* and the measured on-disk behaviour, in
  [`references/versions.md`](references/versions.md), and recommends the same API forms
  those guides do.

## Supported versions

| Ditto SDK | Verified patch | Status |
|---|---|---|
| 5.1.x | 5.1.0 | Default. Emitted when the project's version cannot be determined. |
| 5.0.x | 5.0.3 | Supported. `deliverOn:` is ignored on this line (#SDKS-3856). |
| 4.14.x | 4.14.6 | **LTS** — v4 receives 18 months of long-term support, extending to Dec 2027 (`sdk/latest/v5-whats-new.mdx:266`). No 5.x line is designated LTS anywhere. Do not pin 4.14.5; the release notes identify it as regressed. |

4.12.x and 4.13.x are **not** documented lines. A project on either is told that this
skill's verified code targets 4.14.6, 5.0.3 or 5.1.0.

## Capability map

**Targets vocabulary for this SDK:** `ios | macos | all`. `ios` covers iOS, iPadOS and
the iOS Simulator; `macos` covers macOS (AppKit); Mac Catalyst is called out in the
relevant reference rather than given its own token, because every capability that works
on iOS works on Catalyst. tvOS, visionOS and watchOS are not targets on any supported
line — see [`references/preview.md`](references/preview.md#platform-exclusions).

| ID | Capability | Support | Evidence | Targets |
|----|-----------|---------|----------|---------|
| CAP-01 | Prerequisites, toolchain, package install | yes | executed | all |
| CAP-02 | Platform permissions, entitlements, build config | yes | docs-sample | all |
| CAP-03 | Connecting: config, opening, persistence directory | preview | executed | all |
| CAP-04 | Authentication and identity | preview | executed | all |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | yes | executed | all |
| CAP-06 | Customizing transports | yes | executed | all |
| CAP-07 | Sync subscriptions and sync scopes | yes | executed | all |
| CAP-08 | Querying the store: executing DQL | yes | executed | all |
| CAP-09 | Transactions | yes | executed | all |
| CAP-10 | Indexing | yes | executed | all |
| CAP-11 | Observers, diffing and back-pressure | yes | executed | all |
| CAP-12 | Attachments | yes | executed | all |
| CAP-13 | Presence graph and connection requests | partial | executed | all |
| CAP-14 | Sync status and local commit tracking | yes | executed | all |
| CAP-15 | Logging, diagnostics and stats | yes | executed | all |
| CAP-16 | Error handling | yes | executed | all |
| CAP-17 | Device storage management and eviction | yes | executed | all |
| CAP-18 | Testing | yes | executed | all |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | executed | all |
| CAP-20 | Preview and platform-specific APIs | preview | source | all |

Rows that are not `Support: yes`:

- **CAP-03 `preview`** — on **4.14.x only**, and introduced in **4.12.0**: `DittoConfig`,
  `Ditto.open(config:)`, `Ditto.openSync(config:)` and `Ditto.config` are labelled
  *(Preview)* (`sdk/v4/release-notes/swift.mdx:419,421,427`, and the SDK's
  own doc comments at `sdk-release-4.14.6:cocoa/DittoSwift/DittoConfig.swift:14` for the
  type and `Ditto.swift:142` for `Ditto.config`; `Ditto.open`/`openSync` carry no
  in-source preview marker).
  There is no opt-in flag — using the type is the opt-in. They are GA on 5.0.x and
  5.1.x. The skill recommends them on all three lines because the only alternative,
  `Ditto(identity:persistenceDirectory:)`, is deprecated on 4.14.x and removed in v5.
  **Warning carried by the SDK:** the preview label means "this is what v5 standardizes
  on", which is what shipped; it does not mean the API is unstable.
- **CAP-04 `preview`** — on **4.14.x only**, and introduced in **4.12.0**:
  `DittoAuthenticationExpirationHandler`, `DittoAuthenticationProvider` and
  `DittoAuthenticator.expirationHandler` are labelled *(Preview)*
  (`sdk/v4/release-notes/swift.mdx:423,425,429`, and the SDK's own doc
  comments at `sdk-release-4.14.6:cocoa/DittoSwift/DittoAuthenticator.swift:11,56` and
  `DittoAuthenticationProvider.swift:9`). The `DittoAuthenticator` type itself is **not**
  labelled preview and predates 4.14. There is no opt-in flag — using the API is the
  opt-in. **Warning carried by the SDK:** these are *"a modern, Swift-native alternative
  to the phased out `DittoAuthenticationDelegate` protocol in v5"*, i.e. preview here
  means "this is the v5 shape", which is what shipped; all are GA on 5.0.x and 5.1.x.
- **CAP-13 `partial`** — the graph, peer metadata and observation are fully available and
  executed against a running SDK. The **connection-request path**
  (`presence.connectionRequestHandler`) could not be executed: it requires a second peer,
  and the fixture is a single offline process. It is read from SDK source at
  `sdk-release-5.1.0:sdks/swift/DittoSwift/DittoPresence.swift` and from the published
  documentation.
- **CAP-20 `preview`** — everything this capability covers is preview or beta by
  definition. `DittoConfigExperimental.passphrase` carries the SDK's own warning:
  *"Experimental functionality should not be used in production applications as it may be
  changed or removed at any time, and may not have the same security features"*
  (`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoConfig.swift:62-70`); the opt-in is
  passing a non-`nil` `passphrase`. `DittoMulticastBetaConfig` /
  `DittoPeerToPeer.multicastBeta` are **new in 5.1.0**, disabled by default, iOS and
  macOS only, require Apple's restricted `com.apple.developer.networking.multicast`
  entitlement, and the source says they *"should only be used in coordination with Ditto
  support"* (`DittoTransportConfig.swift:60-72`); the opt-in is
  `config.peerToPeer.multicastBeta.isEnabled = true`. **Data Streams is not exposed by
  the Swift SDK at all** — `sdk/latest/sync/data-streams.mdx` carries Kotlin samples
  only, and no Swift release note announces it; the nearest alternative for large
  payloads is an attachment.

`Evidence: source` on CAP-20 cites
`sdk-release-5.1.0:sdks/swift/DittoSwift/{DittoConfig,DittoConfigExperimental,DittoExperimental,DittoTransportConfig}.swift`;
`Evidence: docs-sample` on CAP-02 cites `sdk/latest/install-guides/swift.mdx` and
`sdk/latest/install-guides/flutter.mdx:98-124` for the macOS entitlements.

## Verification

**Executed against:** Ditto **4.14.6**, **5.0.3** and **5.1.0**, on macOS 27.0 / arm64
with Apple Swift 6.4 (swiftlang-6.4.0.34.1). The fixture is
[`tests/swift-sdk/`](../../tests/swift-sdk), and its README explains how to run it.

- **93 current `@Test` declarations** (`scripts/run.sh --all`), including three
  parameterized declarations. The earlier recorded run reported 92 tests in 14 suites;
  that historical total is not a fresh run of the current 93 declarations. Tests that
  do not apply to a line are skipped rather than silently passed:

  | Line | Skipped |
  |---|---|
  | 4.14.6 | the two v5-only attachment tests, and `isActivated` (4.14.x has only the deprecated `activated`) |
  | 5.0.3, 5.1.0 | `disableSyncWithV3` (no v3 sync to disable) and `useAfterCloseError` (v5 calls `fatalError` on that path instead) |

  Tests needing `DITTO_URL` + `DITTO_TOKEN` are `.enabled(if:)` and report as skipped
  without them, which is how CI runs; the reported total is unchanged. **`DITTO_OFFLINE_LICENSE`
  is different — it is required, not optional.** Without it 66 tests *fail* rather than
  skip (measured: 66 failed, 21 passed, 3 skipped), because `TestPeer.open()` cannot
  activate an instance. The skip
  discipline above is about version and server gating, not about missing configuration.

  Counts here are from `grep -c '@Test'` and the harness's own summary line. An earlier
  revision claimed 77 and carried a per-line breakdown that no run produced.

  Coverage: opening and activation, persistence-directory exclusivity (matching the
  error case, not merely "something threw") and reuse, sync start/stop, subscriptions and
  their computed collection, sync scopes via `ALTER SYSTEM`, DQL execution and argument
  binding, numeric decoding widths, transactions including rollback and read-only
  rejection, indexing, `ADVISE` and `ADVISE AND PROVISION` (and their parse error before
  5.1), eviction, observer delivery, cancellation against an uncancelled positive
  control, `signalNext` coalescing, `DittoDiffer` statefulness, `deliverOn:` behaviour
  per line, the recommended observer bridge (bounded buffering under each policy,
  `onTermination` teardown, and that a single consumer never observes a growing store
  shrink), `Car` identity for non-`String` `_id`s, the login deadline that bounds a
  non-cancellable completion handler and releases it on cancellation, attachments,
  presence, logging, disk usage, small-peer and presence metadata limits, system queries,
  the bounded retry the expiration handler needs (including that cancellation abandons
  the remaining attempts), the rollback that keeps a half-failed `start()` from
  double-registering a subscription, that a boolean round-trips as a plain `Bool` rather
  than an `NSNumber`, and the documented error cases.

  It also settles where `Ditto.open` runs, because the skill got that wrong in both
  directions before measuring it. `ExecutorTests` asserts that SE-0338 holds in this
  build configuration — a nonisolated `async` function leaves the caller's actor, no
  clock involved — and that `Ditto.openSync` on the main actor stalls the main queue for
  its whole duration, which is structural rather than a timing race. `await Ditto.open`
  stalls it *less than an idle control window* on the same machine.

  The load-bearing ones carry a **negative control**: the table in
  [`tests/swift-sdk/README.md`](../../tests/swift-sdk/README.md) names twenty-five guards,
  how to break each and what should then fail. It does not cover every assertion above —
  where a claim rests on structure rather than on a measurement, this file says so under
  "Not verified".
- **`examples/minimal-app.md`** is compiled and run on all three lines in both offline
  and server modes, the latter against a real Ditto Server. The run is **checked**: the
  harness fails unless the output names the expected version and reports the observed
  write.
- **`examples/swiftui-app.md`** — the two-screen SwiftUI app, including the per-selection
  observer — is **compiled** on all twelve platform/version legs, and is byte-identical to
  the fixture source that gets compiled. It is **not executed**: no test drives a real
  SwiftUI view. The pieces it composes are (observer bridge, bounded buffer,
  `onTermination`, cancel-releases-a-suspended-consumer).
- **Platform compile matrix** (`scripts/build-platforms.sh --all`): macOS, iOS Simulator,
  iOS device and Mac Catalyst × all three versions — 12 builds, including the SwiftUI,
  UIKit and AppKit samples in `Sources/UIPatterns/`. Verified non-vacuous by introducing
  a type error into those sources and confirming the matrix fails.
- **Cross-version on-disk behaviour** (`scripts/persistence-matrix.sh`): 10 read legs —
  each writer/reader pair run **directly** as well as chained, plus the default-directory
  and v4 legacy-directory fallbacks. The reader exits non-zero unless the document, its
  field and the index survive, and unless it is running the SDK the leg claims — both
  verified by negative control.

**How to read the citations.** Paths beginning `sdk/` or `snippets/` are pages of the
published documentation at <https://docs.ditto.live>, at the path shown. A bare
`<N>-<N>-capabilities/<file>.mdx` is the same documentation, abbreviated from
`snippets/common-release-notes/<N>-<N>-capabilities/…` — the release-notes set for that
minor version. `sdk-release-<version>:<path>` is a tag in Ditto's SDK repository.

**Verified from source:** the aggregate `fatalError` paths, the `deliverOn:` mechanism,
the `@Sendable` typealias change, the Combine publisher inventory, the `preview` labels,
the attachment-token visibility change, and the transport-config setter's fatal path —
all at `sdk-release-4.14.6`, `sdk-release-5.0.3` and `sdk-release-5.1.0` in the `ditto`
repository, at the Swift source path that exists at each tag.

**Not verified — no test covers these:**

- **Radio behaviour.** BLE, AWDL, mDNS discovery, multi-peer convergence,
  `DittoConnectionType` values other than the local peer's, and connection requests need
  two devices. The fixture is one offline process.
- **Intel (`x86_64`).** Every run was on Apple silicon. 5.1.0 ships no `x86_64` slice at
  all, so nothing here is evidence about Intel hosts.
- **tvOS and visionOS.** No slice ships on any line for visionOS; tvOS binaries exist at
  4.14.6 and 5.0.3 but support is withdrawn, and this skill claims none.
- **Downgrades below 5.0.2 / 4.14.6**, and the composite-index split a 5.1 downgrade
  performs — the fixture creates single-field indexes only.
- **DittoSwiftTools.** A separate package; its version coupling is reported from the
  documentation, not executed, and its two sources conflict on tvOS.
- **Encryption at rest** (`DittoConfigExperimental.passphrase`) and the **5.1 multicast
  beta** — both preview, and the multicast beta needs an Apple-granted entitlement.
- **`DittoError.storeError(.queryError)`.** Every malformed statement tried came back as
  `.queryInvalid`; the case is read from SDK source, not observed.
- **The `@Sendable` closure-alias change in 5.1.0** and **4.14.x's Swift 6 compile
  failure without `@preconcurrency import`.** Both are compile-time properties, and the
  fixture compiles one source tree for all three lines, so neither can be asserted
  there. Both were reproduced by hand; the skill marks them `source`.
- **The `NO_COLOR=1` panic.** Reproduced by hand on all three lines; the harness clears
  the variable rather than asserting the panic.
- **Most transport struct defaults.** The live-versus-constructed comparison table and
  `webSocketSync` are asserted; the remaining struct defaults (ports, retry interval,
  sync group, routing hint) are read from `DittoTransportConfig.swift`.
- **The server-teardown auth race.** No ordering reliably avoids it: a sequence measured
  at 0 aborts in 11 runs later aborted a test process anyway. `references/connect.md`
  describes it as an SDK defect with a workaround (do not release the instance), not as
  something fixed. There is deliberately no test — running one triggers the race often
  enough to abort the whole suite.
- **`DittoDiffer.moves` replayed into `NSTableView`.** The permutation-versus-sequential
  mismatch documented in `references/observers.md` is reasoned from both frameworks'
  contracts and a measured `DittoDiffer` output; the AppKit sample avoids the question by
  using a diffable data source, so the broken form is not exercised.
- **The UIKit, AppKit and SwiftUI samples' runtime behaviour.** They are compiled on
  every platform and version, and the observer bridge underneath them is tested, but no
  test drives a real table view or a real SwiftUI view. In particular, that the
  per-selection observer in `examples/swiftui-app.md` cancels on `.onDisappear` is
  argued from the observer-lifetime rules, not asserted by a UI test.
- **Code signing.** That disabling it produces a `dyld` "unsigned library" abort at launch
  is reproduced by hand and read from the shipped XCFramework, not asserted here: the
  fixture is a SwiftPM package, and the failure is a property of an Xcode app target.
- **The SwiftUI composition root.** `DittoLoader` (its idempotence across suspension, the
  off-main-actor release, and `retry()` awaiting that release), `DittoAppModel`,
  `CarListView`, `AuthCoordinator` and `TokenStore` are **compile-only**: no test
  constructs them. `Retry` and `Deadline` — the primitives `AuthCoordinator` composes —
  are tested directly, but the wiring between them is not.
- **The authentication status surface.** `auth.status`, `isAuthenticated`, `userID`,
  `observeStatus(_:)`, `DittoAuthenticator.StatusPublisher`,
  `Notification.Name.dittoAuthenticationStatusDidChange` and `logout(cleanup:)` are
  documented in `references/connect.md` from SDK source; no test touches any of them.
- **The server-authentication leg in CI.** It runs only where `DITTO_URL` and
  `DITTO_TOKEN` are set, which is a local developer's machine. CI leaves both unset, so
  every claim about `.server` connect, login and the expiration handler is verified by
  local runs recorded here, not by a green check on a pull request.
- **How long `await Ditto.open` occupies a cooperative-pool thread.** That it does *not*
  block the main thread **is** measured — see the Coverage note above — but the pool cost
  is printed, not asserted, because an upper bound in the low milliseconds measures
  machine load. This suite has shipped two assertions that did exactly that.
- **That a `Task` per delivery actually reorders.** A `Task` per delivery has **no
  ordering guarantee at all** — that is a statement about what the concurrency model
  promises, not about how often it misbehaves, and code relying on it is wrong even
  where it happens to work. `ObserverBridge`'s single-consumer loop is ordered by
  construction, and a test pins that a growing store is never observed shrinking, but
  substituting the anti-pattern still passes that test (measured 3 of 3, then 10 of 10):
  `AsyncStream` serialises yields, so a single-process fixture does not provoke the
  reordering. Do not read the passing test as evidence the anti-pattern is safe.

**Last verified:** 2026-09-18.

## Getting started and installation

[Create an app](references/getting-started.md), [check deliverables](references/project-deliverables.md),
or [troubleshoot](references/troubleshooting.md). See the [installation guide](../../docs/install-swift.md)
for all hosts and standalone packages.

## Maintenance

For a new SDK minor, read the official Swift release notes and SDK source, then
update [version guidance](references/versions.md), fixture pins, capability evidence
and example transcripts. Repeat the relevant fixture/platform/persistence checks;
record exact patches and distinguish execution, compilation and source inspection.
For starter generation and host packaging, see [the installation guide](../../docs/install-swift.md).
