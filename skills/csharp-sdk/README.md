# Ditto C# / .NET SDK skill

Tool-agnostic guidance for NuGet **Ditto** with Console, Windows Forms (including
.NET Framework 4.8), .NET MAUI, Uno and Avalonia starters. Browser/WebAssembly targets
are excluded. Uno and Avalonia starters are desktop apps; mobile extensions need
separate integration and validation.

## Scope and versions

The skill owns C# syntax, package/native deployment, async patterns, UI dispatch and
lifetimes. Concept skills own DQL, modeling and sync semantics; every hand-off has a
public-documentation fallback so this skill can be installed independently.

5.2.0 is the knowledge baseline. New-project generation resolves the latest stable v5
NuGet release and pins the result; exact fixture pins remain reproducible. Maintenance
of 4.14.x, 5.0.x and 5.1.x is covered in [versions](references/versions.md).

## Capability map

**Targets vocabulary for this SDK:** `desktop | mobile | all`. `desktop` is Console,
WinForms, Avalonia and Uno Skia; `mobile` is MAUI Android/iOS/Mac Catalyst; `all` is both.

Support describes the SDK surface, not the breadth of executed tests. Evidence below
is bounded by the verification notes: desktop core execution does not certify radios,
server behavior, mobile deployment, or every framework's window lifecycle.

| ID | Capability | Support | Evidence | Targets |
|----|-----------|---------|----------|---------|
| CAP-01 | Prerequisites, toolchain, package install | yes | executed | all |
| CAP-02 | Platform permissions, entitlements, build config | yes | docs-sample | all |
| CAP-03 | Connecting: config, opening, persistence directory | yes | executed | all |
| CAP-04 | Authentication and identity | yes | docs-sample | all |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | yes | executed | all |
| CAP-06 | Customizing transports | yes | executed | all |
| CAP-07 | Sync subscriptions and sync scopes | yes | executed | all |
| CAP-08 | Querying the store: executing DQL | yes | executed | all |
| CAP-09 | Transactions | yes | executed | all |
| CAP-10 | Indexing | yes | executed | all |
| CAP-11 | Observers, diffing and back-pressure | yes | executed | all |
| CAP-12 | Attachments | yes | executed | all |
| CAP-13 | Presence graph and connection requests | yes | executed | all |
| CAP-14 | Sync status and local commit tracking | yes | docs-sample | all |
| CAP-15 | Logging, diagnostics and stats | yes | docs-sample | all |
| CAP-16 | Error handling | yes | executed | all |
| CAP-17 | Device storage management and eviction | yes | executed | all |
| CAP-18 | Testing | yes | executed | all |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | docs-sample | all |
| CAP-20 | Preview and platform-specific APIs | partial | api-dump | all |

- CAP-02: Native permissions are declared in the MAUI assets and the Android app
  compiles. Runtime denial/retry and radio operation need device testing. Desktop
  architecture/build settings are covered in each framework reference.
- CAP-04: Offline license setup executes in every core run; the server login and
  expiration delegate compile in the starter. Credentialed cloud behavior is not verified.
- CAP-09: Commit/rollback executes on 5.1.0 and 5.2.0. On 5.0.4 it is explicitly
  skipped: it hangs (DEVX-918, fixed in 5.1.0), so it is not a passing case.
- CAP-11: Observers, Task and manual back-pressure execute. DittoDiffer is documented
  from the API only.
- CAP-12: Attachment create, fetch, copy and fetcher Stop execute.
- CAP-13: TCP replication, Presence.Observe/Stop and SetPeerMetadata execute;
  connection-request authorization is documented but not exercised.
  See [presence](references/presence.md).
- CAP-16: Invalid DQL and the starter's validation/permission failures execute; typed
  Ditto exception hierarchies are documented from the API.
- 4.14.7 runs the core store/observer/persistence tests only; peer, attachment,
  transaction, starter and snippet tests are v5-only.
- CAP-14: Local result ownership and subscription handles execute; Big Peer sync
  status/local-commit durability requires a separate server integration run.
- CAP-15: SDK-version assertions execute. Log export and disk-usage observations are
  documented from the public API and documentation, without a runtime claim.
- CAP-19: Each exact package compiles/runs and same-version persistence executes.
  Cross-version on-disk upgrades/downgrades have not been verified.
- CAP-20: Published NuGet Ditto 5.2.0 public types/members have no Data Streams
  entry point. Platform permission helpers and configuration exist; no preview opt-in
  is invented. The reproducible assembly check is ApiSurfaceTests.cs in the harness,
  with the package pinned to 5.2.0. See [preview](references/preview.md).

## Verification

**Executed against:** Ditto 4.14.7, 5.0.4, 5.1.0 and 5.2.0 on macOS ARM64,
.NET 10. The exact canonical starter service is compiled into the v5 suite. Tests cover
CRUD, parameter binding/serialization, observers/back-pressure, cancellation, transactions
where verified, indexing/eviction, attachments, TCP replication/presence, startup rollback,
field-preserving edits and persistence. The published generated Console app executes
CRUD and process-restart persistence. See the [harness](https://github.com/getditto/agent-skills/blob/main/tests/csharp-sdk/README.md)
for counts, commands and remaining gates.

**CI evidence:** [run 43640358320](https://github.com/getditto/agent-skills/actions/runs/43640358320)
passed all 19 jobs: the Windows/Linux/macOS core matrix, desktop generation/runtime,
Windows net48 native smoke and four MAUI build targets with matching toolchains.
Both suites (modern and C# 7.3 starter copies) also pass on .NET 11 with Ditto 5.2.0
on macOS ARM64.

**App evaluation:** projects-and-tasks apps built from this skill with .NET 11
frameworks passed native smoke tests; Console, Avalonia and MAUI macOS UI flows were
exercised. Starter pins remain reproducible baselines.

**Verified from source:** public NuGet 5.2.0 managed assemblies/native assets and the
public C# [installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp),
[release notes](https://docs.ditto.live/sdk/latest/release-notes/c-sharp) and topical
pages linked from the references. Source inspection informed investigation; runtime
claims rely on the published package fixtures, not an unpublished branch.

**Not verified:** destination Windows/Linux GUI interaction, physical-device radios/
background behavior, server authentication renewal/durability, cross-version store
migration, traditional packages.config runtime, and behavior across all agent hosts.
Observed app-to-app replication does not establish server durability or a transport path.

**Last verified:** 2026-11-15.

## Installation and quick start

See [installation](https://github.com/getditto/agent-skills/blob/main/docs/install-csharp.md) for scoped host packages. The skill
contains its templates/scripts and works without this repository's tests or other skills.

```bash
/plugin marketplace add getditto/agent-skills
/plugin install ditto-csharp@ditto-plugins
```

Read [project generation](references/project-generation.md), then select
[Console](references/console.md), [WinForms](references/winforms.md),
[MAUI](references/maui.md), [Uno](references/uno.md) or [Avalonia](references/avalonia.md).
The [minimal app](examples/minimal-app.md) is byte-checked against its executable fixture.

## Maintenance

Resolve the new package, inspect its actual exported/native assets, update
[versions](references/versions.md), run the core/version and generated-project matrix,
and revise evidence rather than silently broadening support. Keep template common
sources synchronized with the tested canonical adapter. Revisit the Data Streams
exception when C# gains a public surface. Test release artifacts on destination devices.
