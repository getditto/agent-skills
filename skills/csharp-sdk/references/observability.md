# Diagnostics

## CAP-15 Logging, diagnostics and stats

Source: [logging](https://docs.ditto.live/sdk/latest/deployment/logging),
[system information](https://docs.ditto.live/sdk/latest/deployment/getting-system-information)
and published Ditto 5.2.0 APIs.

Use Ditto.Version to identify the loaded SDK; do not trust only a requested NuGet
version. Record TFM, OS/process architecture and runtime identifier when diagnosing
native loading. AbsolutePersistenceDirectory identifies the actual store location.

v5 logging types are in DittoSDK.Logging. DittoLogger.MinimumLogLevel and IsEnabled
control console logging. CustomLogCallback receives DittoLogLevel and string; catch
exceptions in custom callbacks. ExportToFileAsync(path) creates a support log export;
review logs for application data before sharing. File logging may differ from console
filtering, so disabling console output is not a data-retention policy.

Use Ditto.DiskUsage and the documented system collections for storage/diagnostics.
Read and dispose query results just as for business data; do not poll diagnostic
queries on every UI frame. Avoid displaying connection state as a claim of remote
write durability. A support bundle should identify the exact SDK and reproduction
without including authentication tokens.

## Native startup in agent and CI environments

Ditto 5.2.0's native tracing parser rejects `NO_COLOR=1` with an invalid boolean
`--disable-color` error and can abort before managed error handling runs. Independent
.NET 11 application evaluations reproduced this on macOS ARM64. Normalize the value
to `true` in the **launcher's child-process environment**, before starting the app,
or remove it from that child environment. Do not change machine-global settings.

```bash
NO_COLOR=true dotnet run --project YourApp.csproj
```

A programmatic launcher can set the child's environment without exposing credentials:

```python
import os
import subprocess
child_environment = os.environ.copy()
if "NO_COLOR" in child_environment:
    child_environment["NO_COLOR"] = "true"
subprocess.run(["dotnet", "run", "--project", "YourApp.csproj"],
               env=child_environment, check=True)
```

Setting Environment.SetEnvironmentVariable inside the managed app did **not** update
what the native parser read in the macOS/.NET 11 evaluation. Do not present that alone
as a verified remedy. The fixture runner removes NO_COLOR from its child environment.
A managed try/catch around OpenAsync cannot recover from a native process abort.
