---
name: csharp-sdk
description: >
  Use ONLY for Ditto C#/.NET code (not other Ditto language SDKs or .NET
  WebAssembly): .cs, .csproj, packages.config, NuGet Ditto, DittoSDK,
  Ditto.OpenAsync, Store.RegisterObserver. Builds Console, WinForms (.NET Framework
  4.8 and modern .NET), MAUI, Uno and Avalonia apps; diagnoses native loading,
  callbacks, disposal and errors such as DittoPersistenceDirectoryLockedException,
  ExpirationHandlerMissingException and "Document references in mutation values".
  Covers 4.14.x through 5.2.0.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Ditto C# / .NET SDK

This guidance is derived from the shipping SDK and supersedes prior training on
Ditto C#: v5 uses `Ditto.OpenAsync(DittoConfig)` and DQL, not identity constructors
or collection `Find`/`Upsert` APIs. Never emit a deprecated API; establish the
project's Ditto version from its project, central package file and resolved assets
first; prefer non-deprecated APIs shared with v5 when maintaining v4.
Read only the reference needed for the task, not the complete capability map.

## What this skill does

Builds and reviews C# integrations with NuGet `Ditto`, including working project
starters, async programming, native deployment, UI dispatch and resource cleanup.
One skill covers Console, WinForms, MAUI, Uno and Avalonia on supported native targets.

## When to use this skill

Use for C# SDK syntax, .NET build configuration and framework integration.
For a new app, read [project generation](references/project-generation.md) and the
chosen framework reference. Inspect an existing project's framework, language version,
package management style and architecture before editing it.

**C# version:** use the newest C# the target framework supports: leave `LangVersion`
unset. Only the WinForms starter is C# 7.3 (it also builds for .NET Framework); the
examples here use C# 12. See [C# idioms](references/csharp-idioms.md).

| Topic | Skill if installed | Public fallback |
|---|---|---|
| DQL grammar and indexing strategy | `write-dql` | https://docs.ditto.live/dql/dql |
| CRDT/data model decisions | `data-modeling` | https://docs.ditto.live/key-concepts |
| Subscription semantics | `sync-subscriptions` | https://docs.ditto.live/sdk/latest/sync/syncing-data |
| Radio capabilities and mesh strategy | `ditto-mesh-networking` | https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations |

Do not infer native support from a UI framework's supported-platform list or NuGet's
computed target compatibility. **No .NET WebAssembly**: omit browser/WASM targets from
Uno/Avalonia projects. Windows native assets are x64; on 5.x, desktop macOS assets are
ARM64 only (4.14.x also ships osx-x64).

## Supported versions and packages

Package `Ditto`; v5 namespaces: `DittoSDK`, `.Store`, `.Sync`, `.Auth`, `.Exceptions`. [versions.md](references/versions.md) owns the compatibility
matrix, including v4 namespace differences and exact executed versions.

For a new app, resolve the latest stable compatible NuGet version, then pass that
exact version to the starter. **5.2.0 is the knowledge/test baseline, not a perpetual
latest-version claim.** Preserve existing pins unless upgrading. Read release notes
and compile/run the app when selecting a newer version; never silently use prereleases.

## Capability exceptions

The full twenty-row map and verification limits are in [README.md](README.md).

| ID | Capability | Support | What changes for you |
|---|---|---|---|
| CAP-20 | Preview and platform-specific APIs | partial | Native permissions/configuration exist; Data Streams are absent from the 5.2.0 public C# assembly. Do not translate another SDK's preview APIs. |

## Minimum viable app

The shape of it, inside an async method (`using DittoSDK;`):

<!-- snippet: skill-minimal -->
```csharp
var ditto = await Ditto.OpenAsync(new DittoConfig(databaseId,
    new DittoConfigConnect.SmallPeersOnly(), persistenceDirectory));
ditto.SetOfflineOnlyLicenseToken(offlineLicense);
var subscription = ditto.Sync.RegisterSubscription("SELECT * FROM cars");
var observer = ditto.Store.RegisterObserver("SELECT * FROM cars", result =>
{
    using (result) // copy what you need: items are invalid after disposal
        Console.WriteLine($"cars: {result.Items.Count}");
});
ditto.Sync.Start();
using (await ditto.Store.ExecuteAsync("INSERT INTO cars DOCUMENTS (:car)",
    new() {
        ["car"] = new Dictionary<string, object> { ["_id"] = "car1", ["make"] = "Toyota" } })) { }

// Shutdown: cancel handles, stop sync, then dispose. Never touch a handle after Dispose.
observer.Cancel();
observer.Dispose();
subscription.Cancel();
subscription.Dispose();
ditto.Sync.Stop();
ditto.Dispose();
```

[The complete minimal program](examples/minimal-app.md) adds configuration and a
deadline, and **awaits observer delivery** before shutting down.

## Concurrency and threading model

- Never block on `.Result`/`.Wait()`. v5 `OpenAsync`/`ExecuteAsync` complete
  synchronously, so from UI code run them via `Task.Run`.
- Store observers have `Action` and `Func<..., Task>` overloads. Choose the Task
  overload for asynchronous work, and catch inside it: an escaping exception ends the
  process in either form.
- Store observer and attachment callbacks run on Ditto native threads without a
  SynchronizationContext; the first `Presence.Observe` callback runs on the calling
  thread. Dispatch DTOs to the UI explicitly.
- With manual back-pressure, call `signalNext()` in `finally`; missing a signal stops
  subsequent delivery. Catch callback exceptions before they cross native boundaries.
- Execute transaction statements on `tx`, not the outer store; nested transactions
  and outer-store calls can deadlock. See [concurrency.md](references/concurrency.md).

## Object lifetimes and retention

Own one instance per persistence directory. Retain observers/subscriptions until the
owning screen or service stops. **Call `Cancel()` explicitly** on store observers and
subscriptions before disposing v5 handles; `using` alone does not stop observation.
Dispose query results; copy their data before disposing or handing work to another thread.
**Never touch a v5 observer or subscription after `Dispose()`:** even `IsCancelled`
crashes the process natively, with no managed exception. Read state first.
Attachment fetchers use `Stop()` for cancellation. See [lifetimes.md](references/lifetimes.md).

## Anti-patterns

- **AnyCPU + Prefer32Bit in legacy WinForms:** `BadImageFormatException`. Set x64 and
  `Prefer32Bit=false`; install Ditto on the startup executable as well as its library.
- **Missing native payload:** `DllNotFoundException`. Inspect the actual publish/output
  directory, selected runtime identifier and startup project's NuGet references.
- **Anonymous objects passed to ExecuteAsync:** wrong overload/compile failure. Its
  argument container is `Dictionary<string, object>`; observer overloads differ.
- **Native result retained by a view model:** disposed result access. Materialize DTOs
  inside the callback and dispose its result there.
- **UI collection updated directly in an observer:** cross-thread UI failure. Dispatch
  the copied snapshot through the host framework.
- **Modern syntax pasted into the C# 7.3 WinForms starter:** language-version errors.
  Follow its `Common/` code: ordinary classes, `using (...)` blocks, no nullable syntax.

## Version differences

For v4→v5, follow Ditto's tested [AI Agent Prompt](https://docs.ditto.live/sdk/latest/migration-guides/c-sharp-v4#ai-agent-prompt) (note the
`DQL_STRICT_MODE` default flip); [versions.md](references/versions.md) outlines its
checklist and adds verified cautions.

## References

Load a reference only when its topic is in play; each framework has its own dispatcher,
lifecycle and deployment constraints.

- [project-generation.md](references/project-generation.md): install self-contained local templates; select the native target and resolve the dependency first.
- [setup.md](references/setup.md): the startup executable must carry native assets; TFM compatibility alone is insufficient.
- [winforms.md](references/winforms.md): the C# 7.3 starter, net48, packages.config, binding and form shutdown.
- [maui.md](references/maui.md): initialize native transports before requesting permissions; do not ignore the returned permission result.
- [uno.md](references/uno.md): desktop starter omits WebAssembly; mobile integration needs its own permission and lifecycle verification.
- [avalonia.md](references/avalonia.md): dispatch collection changes and await cleanup before closing the desktop window.
- [console.md](references/console.md): explicit async entry point, CLI shutdown and native publish tests.
- [csharp-idioms.md](references/csharp-idioms.md): dictionaries, POCOs, records, JSON, LINQ and async streams without invented SDK overloads.
- [connect.md](references/connect.md): configuration, authentication, startup rollback and ownership.
- [store.md](references/store.md): dispose query results; bind values, transact through `tx`, manage indexes and eviction.
- [observers.md](references/observers.md): Task overloads, snapshot copying, diffing and manual back-pressure.
- [concurrency.md](references/concurrency.md): cancellation of a wait is not cancellation of native work.
- [lifetimes.md](references/lifetimes.md): cancellation and disposal have different jobs.
- [sync.md](references/sync.md): subscriptions outlive local queries; local commits do not establish remote durability.
- [transports.md](references/transports.md): transport builders and deterministic TCP tests.
- [attachments.md](references/attachments.md): metadata is string-valued; stop a pending fetch explicitly.
- [presence.md](references/presence.md): use current graph/metadata APIs and retain observation handles.
- [observability.md](references/observability.md): SDK version, logs, disk usage and diagnostic queries.
- [errors.md](references/errors.md): native loading, query, permission and callback failures.
- [anti-patterns.md](references/anti-patterns.md): concrete fixes for the default-code traps above.
- [testing.md](references/testing.md): real SDK fixtures, generated projects and honest evidence levels.
- [versions.md](references/versions.md): exact versions and migration boundaries.
- [preview.md](references/preview.md): do not invent a .NET Data Streams API.
- [best-practices.md](best-practices.md): application architecture and field-level updates.
- [minimal-app.md](examples/minimal-app.md): complete executable program.
