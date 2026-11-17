# Ditto Rust SDK Skill

## Contents

- [Scope](#scope)
- [Supported versions](#supported-versions)
- [Capability map](#capability-map)
- [Verification](#verification)
- [Installation](#installation)
- [Maintenance](#maintenance)

Agent skill for writing and reviewing Ditto **Rust** SDK code (`dittolive-ditto`).

## Scope

Covers the `dittolive-ditto` crate: Cargo and toolchain setup, the native-library build,
opening and licensing, DQL store access, transactions, sync, observers bridged into
Tokio, attachments, presence, transports, logging, support bundles, error handling,
testing, and 4.14.x → 5.x migration. Structured against the twenty capability IDs in
`docs/SDK-SKILL-TEMPLATE.md` of the agent-skills repository.

Deliberately **out of scope** — these have their own skills:

- DQL syntax and semantics → `write-dql`
- CRDT type selection and document structure → `data-modeling`
- Subscription semantics and mesh propagation → `sync-subscriptions`
- Transport strategy and mesh formation → `ditto-mesh-networking`
- Data Streams semantics → `data-streams`

## Supported versions

For new apps check crates.io for the latest stable release; **5.2.0 is this skill's
knowledge baseline**, not a permanent dependency recommendation.

| Ditto SDK | Crate version | Status |
|---|---|---|
| 5.2.x | 5.2.0 | Latest known baseline: executed (macOS arm64; Linux x86_64 full suite) |
| 5.1.x | 5.1.0 | Supported: executed (macOS arm64) |
| 5.0.x | 5.0.4 | Supported: executed (macOS arm64) |
| 4.14.x | 4.14.7 | LTS: v4 fixture executed (macOS arm64) |

## Capability map

**Targets vocabulary for this SDK:** `all`. The Rust SDK ships one library per target
triple with one API; target availability (Linux x86_64/aarch64, macOS aarch64) is in
[`references/setup.md`](references/setup.md#supported-targets), not per row.

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
| CAP-13 | Presence graph and connection requests | yes | source | all |
| CAP-14 | Sync status and local commit tracking | yes | executed | all |
| CAP-15 | Logging, diagnostics and stats | yes | executed | all |
| CAP-16 | Error handling | yes | executed | all |
| CAP-17 | Device storage management and eviction | yes | executed | all |
| CAP-18 | Testing | yes | executed | all |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | executed | all |
| CAP-20 | Preview and platform-specific APIs | preview | source | all |

Rows that are not `Support: yes`:

- **CAP-20 `preview`** — Data Streams is opt-in through the Cargo feature
  `preview-datastreams`, present in 5.0.4, 5.1.0 and 5.2.0; the crate's `preview` module
  states preview APIs carry "no semver guarantees". Multicast transport is a private
  beta from 5.1.0 (`TransportConfig.peer_to_peer.multicast_beta`), to be enabled only with
  Ditto support. Neither was executed ([`references/preview.md`](references/preview.md)).

Evidence notes (spec §7 requires the path and ref inline for `source`/`inference`):

- **CAP-13 `source`** — graph read, observer registration, peer metadata and handler
  installation are executed on one peer; the connection-request handler only fires when
  a second peer connects, so its call semantics (10 s deny timeout, the async variant's
  single shared runtime) come from `src/presence/mod.rs` in the published
  `dittolive-ditto` 5.2.0 crate.
- **CAP-20 `source`** — `Cargo.toml` features and `src/preview/mod.rs` /
  `examples/datastreams.rs` of the published `dittolive-ditto` 5.2.0 crate;
  `src/transport/transport_config.rs` of the 5.1.0 crate for multicast.
- **CAP-02 `executed`** covers the build configuration that matters for Rust: the toolchain
  pin, the Linux link flag, the offline-library recipe and target availability (HTTP
  probes of `software.ditto.live`). Linux Bluetooth host setup is documentation-sourced.
- **CAP-04 `executed`** covers offline licenses and the Server-mode expiration handler's
  first call and thread; a real cloud login was not executed (no credentials in CI).
- **CAP-14 `executed`** covers `QueryResult::commit_id()` and querying and observing
  `system:data_sync_info`; its per-peer `synced_up_to_local_commit_id` needs a second
  peer and is documentation-sourced ([`references/sync.md`](references/sync.md)).
- **CAP-12 `executed`** covers local create → insert → select → fetch; peer-to-peer
  attachment transfer was not executed.
- **CAP-19 `executed`** covers the 4.14.7 API and its DQL-mutation error, and a 4.14.7
  store opened, migrated, read and written by 5.2.0 (explicit directory, macOS arm64).

## Verification

**Executed against** (2026-11-15):

- **5.2.0, 5.1.0, 5.0.4** on macOS 27.2.1 arm64, rustc 1.91.0, through
  `tests/rust-sdk/scripts/run-fixture.sh`: the minimal app (transcripts in
  [`examples/minimal-app.md`](examples/minimal-app.md)), 27 behavior probes, 9
  async-semantics probes, 5 Tokio-pattern tests and 6 reference-sample tests. Every Rust
  block in this skill except the `SKILL.md` excerpt and three marked wrong-form fragments
  is generated from those files. `cargo clippy --all-targets -- -D warnings` is clean.
- **5.2.0 on Linux x86_64** (Docker, `rust:1.91.0-bookworm`, emulated): the same suite,
  after the link fix. **On Linux aarch64** (Docker, native): the link failure without the
  fix, a successful link with it, and a support-bundle program; not the full suite.
- **4.14.7** on macOS arm64 and Linux x86_64 (with the link fix): `DittoConfig` +
  `Ditto::open`, the `_v2` DQL methods, the `disable_sync_with_v3` error text, and the
  compiled builder sample.
- **CI:** `.github/workflows/rust-skill-tests.yml` runs the same suite on Ubuntu x86_64 for
  5.0.4, 5.1.0 and 5.2.0 plus the 4.14.7 fixture; it had not yet run on GitHub when this
  evidence was recorded.
- **Toolchains**: 5.2.0 builds on rustc 1.91.0, 1.94.0, 1.96.0 and 1.97.0; 4.14.7–5.2.0
  fail on 1.98.0 and 1.99.1 with E0690.
- **Support bundles** (5.2.0): generation, fetch, archive entries, rate limit; dial9
  trace present after 75 s, absent before 60 s.

**Verified from source** (published crates on crates.io, and `github.com/getditto/ditto`
at `sdk-release-5.2.0`): callback bounds, the expiration-handler dispatcher, the
connection-request runtime, `make_continuation`'s panic on a dropped receiver, the
`Any` downcast in transaction completion, dial9 environment variables
(`crates/dittoffi/src/runtime.rs`), support-bundle sources, and the v4 legacy-directory
fallback.

**Not verified:** two-peer sync, attachment transfer between peers, connection-request
handling, Data Streams, multicast, Linux Bluetooth, a real cloud login, `CRASH` bundles,
Portal-requested bundles, CPU profiling at dial9 level 2, 5.0.4/5.1.0 on Linux, and the
full suite on Linux aarch64.

## Installation

```bash
# Claude Code
/plugin marketplace add getditto/agent-skills
/plugin install ditto-rust@ditto-plugins
```

For other agent tools, see the agent-skills repository README.

## Maintenance

When the SDK ships a new minor version:

1. Re-read <https://docs.ditto.live/sdk/latest/release-notes-hub/rust> for API changes.
2. Update `references/versions.md` first: it owns every version claim.
3. Run `tests/rust-sdk/scripts/run-fixture.sh <version>`; fix the fixture, then run
   `python3 scripts/sync-snippets.py`.
4. Re-check the toolchain window (E0690), the Linux link flag and the target table.
5. Re-check the capability map: a `partial`/`preview` row may have changed.
