# Logging, diagnostics and stats — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/deployment/logging.mdx`,
> `sdk/latest/deployment/device-observability-and-ditto-logs.mdx`,
> `sdk/latest/deployment/getting-system-information.mdx`,
> `sdk/latest/deployment/integrate-ditto-tools-for-kotlin-swift-and-c-net-in-15-minutes.mdx`,
> and the LOGGING / DISK USAGE blocks in `sdk/latest/migration-guides/<lang>-v4.mdx`.
>
> **Known gap:** `logging.mdx` documents rotation policy and contains **no code samples
> in any language**, and disk usage has no standalone page at all. Expect to source the
> APIs here from the published API reference or the SDK source, and mark the affected
> rows `undocumented` with the path and ref you verified against.

## CAP-15 Logging, diagnostics and stats

### Logging

<!--
  - Enabling/disabling the logger and setting the minimum level.
  - The available levels and what each actually emits.
  - Routing logs to a file, and exporting them for support.
  - Subscribing to log events programmatically to forward into an app logger.
  - Whether logger configuration is global/static or per-instance. If static, say so --
    it surprises people who create more than one instance in tests.
  - Rotation defaults and the configuration knobs, from logging.mdx.
-->

TODO

### Disk usage

<!--
  - Reading current disk usage, and observing it over time.
  - What the reported items mean and which are the ones worth alerting on.
-->

TODO

### Small peer info / telemetry

<!--
  - Enabling it, attaching custom metadata, and its size limits.
  - Where the data goes and what consumes it.
-->

TODO

### System information

<!--
  - Retrieving SDK version and system info from this language.
  - The DQL/SHOW route where there is no host-language API.
-->

TODO

### Ditto Tools

<!--
  - Whether a Ditto Tools package exists for this language, how to add it, and which
    tools it provides. Mark not-available where there is none.
  - Any OpenTelemetry / instrumentation hook the SDK exposes.
-->

TODO
