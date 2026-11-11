# Console applications

The console starter targets .NET 10 and uses an explicit async Task<int> Main. A newer
compiler can also use top-level statements, but an existing net48 project needs its
own supported entry-point/language setup. Core SDK tests also exercise v4 compatibility;
the generated starter deliberately uses the v5 API.

After generation and configuration:

```bash
dotnet restore
dotnet run
```

Commands: `add TITLE`, `edit ID TITLE`, `done ID`, `reopen ID`, `delete ID`, `quit`.
Observer output includes document IDs. EOF and quit await StopAsync. Writes are
parameterized; editing a title preserves completion state. Keep the terminal open
long enough to observe updates; the minimal program instead uses an explicit delivery
completion signal and deadline.

Publish for the real host, for example:

```bash
dotnet publish -c Release -r win-x64 --self-contained false
```

Substitute osx-arm64, linux-x64 or linux-arm64 only for a supported destination. Run
the published binary there to prove native loading. The desktop starter leaves
trimming off; NativeAOT and single-file packaging are not implied by the baseline.

In a Generic Host/DI app, register an application-owned service and await startup in
the host lifecycle. Do not call OpenAsync().Result in a service factory. Await shutdown
before disposing the root service provider. For cancellation, stop accepting operations
and let in-flight native tasks finish before releasing the instance.

Source: [Ditto console quickstart](https://docs.ditto.live/sdk/latest/quickstarts/dotnet-console),
[published package](https://www.nuget.org/packages/Ditto/5.2.0).
