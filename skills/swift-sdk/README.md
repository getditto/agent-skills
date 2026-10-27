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

- DQL syntax and semantics → `write-dql`
- CRDT type selection and document structure → `data-modeling`
- Subscription semantics and mesh propagation → `sync-subscriptions`
- Transport strategy and mesh formation → `ditto-mesh-networking`
- The v4 → v5 migration *procedure* → the published guides at
  <https://docs.ditto.live/sdk/latest/migration-guides/swift-v4> and
  <https://docs.ditto.live/sdk/latest/migration-guides/swift-dql>. This skill owns the
  version-gated *facts* and the on-disk behaviour, in
  [`references/versions.md`](references/versions.md), and recommends the same API forms
  those guides do.

## Supported versions

| Ditto SDK | Verified patch | Status |
|---|---|---|
| 5.2.x | 5.2.0-rc.2 | Release candidate. Additive over 5.1.x — store encryption, `systemParameters`, `deleteStore`. Pin exactly; 5.2.0 GA is published but not yet verified. |
| 5.1.x | 5.1.0 | Default. Emitted when the project's version cannot be determined. |
| 5.0.x | 5.0.3 | Supported. `deliverOn:` is ignored on this line. |
| 4.14.x | 4.14.6 | **LTS** — v4 receives 18 months of long-term support, extending to Dec 2027 (`sdk/latest/v5-whats-new.mdx:266`). No 5.x line is designated LTS anywhere. Do not pin 4.14.5; the release notes identify it as regressed. |

4.12.x and 4.13.x are **not** documented lines. A project on either is told that this
skill's verified code targets 4.14.6, 5.0.3, 5.1.0 or 5.2.0-rc.2.

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
| CAP-20 | Preview and platform-specific APIs | preview | api-dump | all |

Rows that are not `Support: yes`:

- **CAP-03 `preview`** — on **4.14.x only**, introduced in **4.12.0**: `DittoConfig`,
  `Ditto.open(config:)`, `Ditto.openSync(config:)` and `Ditto.config` are labelled
  *(Preview)* in the release notes (`sdk/v4/release-notes/swift.mdx:419,421,427`). There
  is no opt-in flag — using the type is the opt-in. They are GA on 5.0.x and later. The
  skill recommends them on all three lines because the alternative,
  `Ditto(identity:persistenceDirectory:)`, is deprecated on 4.14.x and removed in v5.
  **Stability:** the preview label means "this is the shape v5 standardizes on", which is
  what shipped; it does not mean the API is unstable.
- **CAP-04 `preview`** — on **4.14.x only**, introduced in **4.12.0**:
  `DittoAuthenticationExpirationHandler`, `DittoAuthenticationProvider` and
  `DittoAuthenticator.expirationHandler` are labelled *(Preview)*
  (`sdk/v4/release-notes/swift.mdx:423,425,429`). `DittoAuthenticator` itself is not
  preview and predates 4.14. There is no opt-in flag — using the API is the opt-in.
  **Stability:** these are the v5 replacement for `DittoAuthenticationDelegate`, and are
  GA on 5.0.x and later.
- **CAP-13 `partial`** — the presence graph, peer metadata and observation are covered and
  executed. The connection-request path (`presence.connectionRequestHandler`) needs a
  second peer and is documented from the public guide at
  `sdk/latest/sync/handling-connection-requests.mdx`.
- **CAP-20 `preview`** — everything this capability covers is preview or beta.
  `DittoConfigExperimental.passphrase` (encryption at rest) is experimental: the SDK's
  public API documentation says it *"should not be used in production applications as it
  may be changed or removed at any time"*; the opt-in is passing a non-`nil`
  `passphrase`. `DittoMulticastBetaConfig` / `DittoPeerToPeer.multicastBeta` are **new in
  5.1.0**, disabled by default, iOS and macOS only, and need Apple's
  `com.apple.developer.networking.multicast` entitlement
  (`5-1-capabilities/swift-specific-changelog.mdx:4-5`); contact Ditto before deploying
  them in production (`5-1-capabilities/common-capabilities.mdx:201-203`). The opt-in is
  `config.peerToPeer.multicastBeta.isEnabled = true`. **Data Streams is not exposed by the
  Swift SDK** — `sdk/latest/sync/data-streams.mdx` carries Kotlin samples only; for large
  payloads use an attachment.

`Evidence: docs-sample` on CAP-02 cites `sdk/latest/install-guides/swift.mdx`. Paths
beginning `sdk/` or `snippets/` are pages of the published documentation at
<https://docs.ditto.live>; a bare `<N>-<N>-capabilities/<file>.mdx` abbreviates
`snippets/common-release-notes/<N>-<N>-capabilities/…`.

## Verification

**Executed against:** Ditto **4.14.6**, **5.0.3** and **5.1.0** on Apple silicon. The code
samples and both examples are compiled for macOS, iOS Simulator, iOS device and Mac
Catalyst on all three versions, and the minimal app is run in CI. Contributors: see
[`tests/swift-sdk/README.md`](../../tests/swift-sdk/README.md).

**Not covered by automated tests:**

- Multi-peer behaviour — BLE, AWDL, mDNS discovery, remote presence and connection
  requests.
- Intel (`x86_64`) hosts, and tvOS / visionOS.
- Encryption at rest and the 5.1 multicast beta.
- UI-level behaviour of the SwiftUI, UIKit and AppKit samples; they are compiled, and
  their store and observer logic is exercised at runtime.

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
