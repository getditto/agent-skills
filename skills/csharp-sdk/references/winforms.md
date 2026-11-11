# Windows Forms, including .NET Framework

Source: [C# .NET Framework setup](https://docs.ditto.live/sdk/latest/install-guides/c-sharp#net-framework-48-setup),
[Microsoft C# language versions](https://learn.microsoft.com/dotnet/csharp/language-reference/language-versioning).

## Generate

Use ditto-winforms with `--framework net48`, net481 or net10.0-windows.
The legacy starter uses C# 7.3, an explicit STAThread entry point, ordinary classes,
classic using blocks, x64 and Prefer32Bit=false. It does not emit records, top-level
statements, await using, nullable-reference syntax or ApplicationConfiguration.Initialize
into a legacy project. All variants call the actual async v5 SDK.

On Windows, after setting appsettings.json:

```bash
dotnet build
```

Run the produced .exe for net48/net481. Use `dotnet run` for the modern target.
Reference assemblies allow cross-compilation on another OS; that is not Windows runtime
verification. Test startup, UI actions and native DLL loading on Windows itself.

## Existing projects

Preserve the user's project format. A traditional csproj with packages.config should
remain traditional unless migration is requested. Install Ditto on the startup .exe
as well as any consuming class library. Check Ditto.Native.Win restore and the generated
.targets import; native payloads do not reliably cross Framework ProjectReference chains.
For PackageReference, set RuntimeIdentifier=win-x64 on the startup project. Do not mix
native libraries from different Ditto releases or "fix" missing DLLs with unversioned copies.

Ditto 5.0.1 introduced netstandard2.0 support for net48/481; 5.0.0 does not have it.
The 5.0.2 release fixed packages.config native resolution. Prefer the current stable
compatible release; the baseline starter uses 5.2.0. If assembly binding redirects are
needed in an existing Framework app, resolve the actual dependency conflict and verify
its output rather than adding blanket redirects from another application.

## UI and ownership

The form dispatches snapshots with Control.BeginInvoke after its handle exists.
The view model never retains native query items. Bound rows are application DTOs.
An async FormClosing handler cancels the first close, waits for StopAsync, then closes
once teardown completes. Reject queued dispatches while closing or after disposal.
Use async void only for framework event handlers, with failures handled by an awaited
Task-returning method. Do not block the WinForms synchronization context with Result.

A startup .exe/native-loading regression belongs in the Windows CI leg. A macOS build
of net48 alone cannot establish that packages.config, UI or DLL resolution runs correctly.
