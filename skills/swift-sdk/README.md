# Ditto Swift SDK Skill

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
  <https://docs.ditto.com/sdk/latest/migration-guides/swift-v4> and
  <https://docs.ditto.com/sdk/latest/migration-guides/swift-dql>. This skill owns the
  version-gated *facts* and the measured on-disk behaviour, in
  [`references/versions.md`](references/versions.md), and recommends the same API forms
  those guides do.

## Supported versions

| Ditto SDK | Verified patch | Status |
|---|---|---|
| 5.1.x | 5.1.0 | Default. Emitted when the project's version cannot be determined. |
| 5.0.x | 5.0.3 | Supported. `deliverOn:` is ignored on this line (#SDKS-3856). |
| 4.14.x | 4.14.6 | **LTS.** Do not pin 4.14.5 — the release notes identify it as regressed. |

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

- **CAP-03 `preview`** — on **4.14.x only**, `DittoConfig`, `Ditto.open(config:)`,
  `Ditto.openSync(config:)` and `Ditto.config` are labelled *(Preview)*
  (`sdk/v4/release-notes/swift.mdx:419,421,427`, and the SDK's own doc comments at
  `sdk-release-4.14.6:cocoa/DittoSwift/DittoConfig.swift:14` and `Ditto.swift:142`).
  There is no opt-in flag — using the type is the opt-in. They are GA on 5.0.x and
  5.1.x. The skill recommends them on all three lines because the only alternative,
  `Ditto(identity:persistenceDirectory:)`, is deprecated on 4.14.x and removed in v5.
  **Warning carried by the SDK:** the preview label means "this is what v5 standardizes
  on", which is what shipped; it does not mean the API is unstable.
- **CAP-04 `preview`** — on **4.14.x only**, `DittoAuthenticator`,
  `DittoAuthenticationProvider`, `DittoAuthenticationExpirationHandler` and
  `DittoAuthenticator.expirationHandler` are labelled *(Preview)*
  (`sdk/v4/release-notes/swift.mdx:423,425,429`). No opt-in flag. GA on 5.0.x and 5.1.x.
  They replace the phased-out `DittoAuthenticationDelegate`.
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
[`tests/swift-sdk/`](../../tests/swift-sdk/):

- **64 tests** pass on each of the three version lines
  (`tests/swift-sdk/scripts/run.sh --all`), covering opening and activation, persistence
  directory exclusivity and reuse, sync start/stop, subscriptions and their computed
  collection, sync scopes via `ALTER SYSTEM`, DQL execution and argument binding, numeric
  decoding widths, transactions including rollback and read-only rejection, indexing,
  eviction, observer delivery and cancellation, `signalNext` coalescing, `DittoDiffer`
  statefulness, `deliverOn:` behaviour per line, attachments, presence, logging, disk
  usage, small-peer metadata, and the documented error cases.
- **`examples/minimal-app.md`** is compiled and run on all three lines in both offline
  and server modes, against a real Ditto Server for the latter.
- **Platform compile matrix** (`tests/swift-sdk/scripts/build-platforms.sh --all`):
  macOS, iOS Simulator, iOS device and Mac Catalyst × all three versions — 12 builds,
  including the SwiftUI, UIKit and AppKit samples in `tests/swift-sdk/Sources/UIPatterns/`.
- **Cross-version on-disk behaviour**
  (`tests/swift-sdk/scripts/persistence-matrix.sh`): 4.14.6 → 5.0.3 → 5.1.0 upgrade,
  5.1.0 → 5.0.3 → 4.14.6 rollback, and the v4 legacy-persistence-directory fallback.

**Verified from source:** the aggregate `fatalError` paths, the `deliverOn:` mechanism,
the `@Sendable` typealias change, the Combine publisher inventory, the `preview` labels,
the attachment-token visibility change, and the transport-config setter's fatal path —
all at `sdk-release-4.14.6`, `sdk-release-5.0.3` and `sdk-release-5.1.0` in the `ditto`
repository, at the Swift source path that exists at each tag.

**Not verified:**

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

**Last verified:** 2026-09-17.

## Installation

```bash
# Claude Code
/plugin marketplace add getditto/agent-skills
/plugin install ditto-swift@ditto-plugins
```

For other agent tools, see the repository [README](../../README.md).

## Maintenance

When the SDK ships a new minor version:

1. Re-read `sdk/latest/release-notes/swift.mdx` and
   `snippets/common-release-notes/<version>-capabilities/swift-specific-changelog.mdx` —
   the changelog carries the ticket numbers and symptom wording the prose summary drops.
2. Update [`references/versions.md`](references/versions.md) first; it is the source of
   truth for every version claim in this skill.
3. Add the version to `tests/swift-sdk/scripts/run.sh --all`, re-run the fixture, the
   platform matrix and the persistence matrix, and update **Verification** and
   `examples/minimal-app.md` with the new transcripts.
4. Re-check the capability map: a `preview` row may have become `yes`, and a `partial`
   row may have been filled in.
