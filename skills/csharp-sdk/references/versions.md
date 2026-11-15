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
| 5.0.3 / 5.0.4 | `TransactionAsync` can hang while completing or while the instance is disposed (DEVX-918, documented in the 5.1.0 C# release notes and fixed there). The commit/rollback probe reproduces it on macOS ARM64 and is killed by the 45-second watchdog, so the 5.0.4 suite skips it explicitly; other tested APIs pass. **Use 5.1.0 or later for apps that use transactions.** 5.0.x also rejects UPDATE statements that reference the document's own fields. |
| 5.1.0 | Real core/starter fixture executed, including transactions, observers and TCP peers. |
| 5.2.0 | Primary starter/API baseline; real core/starter tests executed. Public C# Data Streams API absent. |

The shipped .NET 8 asset can be consumed by later compatible runtimes. The .NET Standard
asset does not mean every OS/CPU, Xamarin target or WebAssembly host is supported.
Windows native package inspected: win-x64; desktop macOS: osx-arm64. Mobile native
packages are separate. See the official compatibility table for OS minimums and
[setup](setup.md) for target selection.

## v4 to v5 code changes

**Migrate with Ditto's tested migration prompt.** The C# v4→v5 migration guide publishes
an [AI Agent Prompt](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4#ai-agent-prompt) written and tested for coding agents. Read it from that page
(the Ditto docs MCP server serves it as `/sdk/latest/migration-guides/c-sharp-v4.mdx`)
and follow it, including its ten-step checklist:

1. Update the `Ditto` package to 5.x.
2. Fix namespace imports (`DittoSDK.Auth`, `.Exceptions`, `.Store`, `.Sync`,
   `.Transport`, `.Logging`, `.DiskUsage`).
3. Replace `new Ditto(identity, path)` with `Ditto.OpenAsync(new DittoConfig(...))`.
4. Move to `ditto.Sync.Start()/Stop()`, remove `DisableSyncWithV3()`, and set strict mode
   (below) before `Sync.Start()`.
5. Replace `IDittoAuthenticationDelegate` with `Auth.ExpirationHandler` and `LoginAsync`.
6. Replace the Collection API with DQL through `ExecuteAsync`.
7. Replace live queries and collection subscriptions with `RegisterObserver` and
   `Sync.RegisterSubscription`.
8. Replace `Store.Write()` with `TransactionAsync`.
9. Update renamed properties and types (presence, disk usage, `Ditto.Version`).
10. Verify: zero build errors, strict mode correct, auth before first sync, observers
    receive initial data, no leaks.

Use the prompt itself as the source of each API mapping; this list is only its outline.
This skill adds the following, each observed against the published packages:

- **Async handlers must catch.** The prompt's async observer and back-pressure examples
  (`async result => ...`, `async (result, signalNext) => { await ...; signalNext(); }`)
  do not catch. Both run as async void inside the SDK, so an exception ends the process
  and the next result is never signalled. Wrap the body in try/catch and call
  `signalNext()` from `finally` ([observers](observers.md)).
- **"Async" calls finish synchronously.** v5 `OpenAsync`/`ExecuteAsync` complete on the
  calling thread, so a missing `await` still runs the statement (the result is just
  never observed or disposed). From UI code run them via `Task.Run`
  ([concurrency](concurrency.md)).
- **Transactions need 5.1.0 or later** (DEVX-918), and 5.0.x rejects UPDATEs that read
  the document's own fields ([store](store.md)).
- Cancel v4 observers explicitly; on v5 cancel, then dispose handles, and never touch a
  handle after `Dispose()`. Do not add IDisposable assumptions to v4 types solely
  because v5 implements it.

**DQL strict mode changes default (breaking).** v4 defaults to `DQL_STRICT_MODE=true`
(objects are registers, replaced whole); v5 defaults to `false` (objects are maps,
merged field by field). An app that relied on the v4 default must set strict mode back
to `true` before sync starts or any query runs, or objects silently merge instead of
being replaced, which can look like data loss
([migration guide](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4#dql-strict-mode-behavior-change)).
On 5.2.0 and later, set it when opening:
`new DittoConfig(...) { SystemParameters = new Dictionary<string, object> { ["DQL_STRICT_MODE"] = true } }`.
On 5.0.x and 5.1.x, run `ALTER SYSTEM SET DQL_STRICT_MODE = true` through `ExecuteAsync`
after `OpenAsync` and before `Sync.Start()`. An app that already set `false` in v4 needs
no change. Both forms were run against 5.2.0 (and `ALTER SYSTEM` against 5.0.4); the
parameter name is case-insensitive in both. Keeping `true` matches Ditto's migration
prompt. The data-modeling skill instead moves every peer to `false` before upgrading;
pick one per mesh, and contact Ditto support before switching an existing mesh to
`false`, as the migration guide advises. The
4.14.7 test fixture runs with strict mode **off**, so its results do not cover v4's
default behavior.

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
