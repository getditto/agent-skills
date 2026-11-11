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
