# Version and target matrix

## CAP-19 API and on-disk migration

Sources: [C# v4 migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4),
[C# DQL migration](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-dql),
[C# releases](https://docs.ditto.live/sdk/latest/release-notes/c-sharp),
[5.2.0 package](https://www.nuget.org/packages/Ditto/5.2.0).
Last package/API inspection: 2026-11-10.

| Version | Guidance/evidence |
|---|---|
| 4.14.7 | Real core fixture executed. OpenAsync(DittoConfig) is available, avoiding deprecated identity construction. Store types are in DittoSDK; store observers are not IDisposable. DisableSyncWithV3 and DQL strict-mode setup are used by the fixture. |
| 5.0.0 | Does not ship the netstandard2.0 asset required by the net48 integration. |
| 5.0.1 | Introduces netstandard2.0/net48 support; do not infer packages.config fixes from this version. |
| 5.0.2 | Release notes document the packages.config native-resolution fix. |
| 5.0.3 / 5.0.4 | A transaction commit/rollback probe hangs on macOS ARM64 and is killed by the 45-second test-host watchdog. The normal 5.0.4 compatibility suite explicitly skips that probe; other tested APIs pass. Do not label those transactions runtime-verified. |
| 5.1.0 | Real core/starter fixture executed, including transactions, observers and TCP peers. |
| 5.2.0 | Primary starter/API baseline; real core/starter tests executed. Public C# Data Streams API absent. |

The shipped .NET 8 asset can be consumed by later compatible runtimes. The .NET Standard
asset does not mean every OS/CPU, Xamarin target or WebAssembly host is supported.
Windows native package inspected: win-x64; desktop macOS: osx-arm64. Mobile native
packages are separate. See the official compatibility table for OS minimums and
[setup](setup.md) for target selection.

## v4 to v5 code changes

Use config-based OpenAsync when available on the selected v4 patch. Replace deprecated
collection queries/mutations with Store.ExecuteAsync DQL; v5 removes identity-based
construction and legacy collections. v5 store/sync/auth types have subnamespaces.
Use Sync.Start/Stop/RegisterSubscription in v5 instead of copying old instance-level
sync methods. Cancel v4 observers explicitly; on v5 cancel then dispose handles.
Do not add System.IDisposable assumptions to v4 types solely because v5 implements it.

The fixtures compile version-specific code; passing on one version does not prove the
same source builds against the others. The new-app templates target v5; v4 applications
get version-aware integration guidance, not a template that silently upgrades them.

## Storage migration

Opening an existing store is a separate compatibility concern from compiling new code.
Use the release migration documentation, preserve the real persistence directory and
back up user data before a planned migration. Do not assume rollback to an older SDK
is safe because an upgrade opened successfully. The current fixture proves same-version
close/reopen; it does not establish every cross-version upgrade/downgrade pair.
No untested downgrade matrix is presented as supported by this skill.
