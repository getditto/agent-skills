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

**Targets vocabulary for this SDK:** native, mobile

Support describes the SDK surface, not the breadth of executed tests. Evidence below
is bounded by the verification notes: desktop core execution does not certify radios,
server behavior, mobile deployment, or every framework's window lifecycle.

| ID | Capability | Support | Evidence | Targets |
|----|-----------|---------|----------|---------|
| CAP-01 | Prerequisites, toolchain, package install | yes | executed | native |
| CAP-02 | Platform permissions, entitlements, build config | yes | docs-sample | mobile |
| CAP-03 | Connecting: config, opening, persistence directory | yes | executed | native |
| CAP-04 | Authentication and identity | yes | docs-sample | native |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | yes | executed | native |
| CAP-06 | Customizing transports | yes | executed | native |
| CAP-07 | Sync subscriptions and sync scopes | yes | executed | native |
| CAP-08 | Querying the store: executing DQL | yes | executed | native |
| CAP-09 | Transactions | yes | executed | native |
| CAP-10 | Indexing | yes | executed | native |
| CAP-11 | Observers, diffing and back-pressure | yes | executed | native |
| CAP-12 | Attachments | yes | executed | native |
| CAP-13 | Presence graph and connection requests | yes | executed | native |
| CAP-14 | Sync status and local commit tracking | yes | docs-sample | native |
| CAP-15 | Logging, diagnostics and stats | yes | docs-sample | native |
| CAP-16 | Error handling | yes | executed | native |
| CAP-17 | Device storage management and eviction | yes | executed | native |
| CAP-18 | Testing | yes | executed | native |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | docs-sample | native |
| CAP-20 | Preview and platform-specific APIs | partial | api-dump | native |

- CAP-02: Native permissions are declared in the MAUI assets and the Android app
  compiles. Runtime denial/retry and radio operation need device testing. Desktop
  architecture/build settings are covered in each framework reference.
- CAP-04: Offline license setup executes in every core run; the server login and
  expiration delegate compile in the starter. Credentialed cloud behavior is not verified.
- CAP-09: Commit/rollback executes on 5.1.0 and 5.2.0. The 5.0.4 probe is explicitly
  skipped after a watchdog-terminated hang on macOS ARM64; it is not a passing case.
- CAP-13: TCP replication and presence execute; connection-request authorization is
  documented but not exercised. See [presence](references/presence.md).
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
CRUD and process-restart persistence. See the [harness](../../tests/csharp-sdk/README.md)
for counts, commands and remaining gates.

**Compile evidence:** generated Console, Avalonia and Uno desktop apps; net48 WinForms;
MAUI Android. A Mac Catalyst probe compiled only with Xcode version validation disabled
because the local workload expects Xcode 26.2 and the installed Xcode is 27.2. This is
not counted as supported Apple toolchain validation.

**Verified from source:** public NuGet 5.2.0 managed assemblies/native assets and the
public C# [installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp),
[release notes](https://docs.ditto.live/sdk/latest/release-notes/c-sharp) and topical
pages linked from the references. Source inspection informed investigation; runtime
claims rely on the published package fixtures, not an unpublished branch.

**Not verified:** Windows execution, graphical UI interaction, supported Apple builds,
physical-device radios/background behavior, cloud authentication/durability, cross-version
store migration, traditional packages.config runtime, and live-agent behavioral evaluations.
CI supplies repeatable platform gates; adding a workflow is not evidence that it ran.

**Last verified:** 2026-11-10.

## Installation and quick start

See [installation](../../docs/install-csharp.md) for scoped host packages. The skill
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
