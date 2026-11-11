# Error handling

## CAP-16 Errors

Source: [installation troubleshooting](https://docs.ditto.live/sdk/latest/install-guides/c-sharp),
[SDK troubleshooting](https://docs.ditto.live/sdk/latest/deployment/troubleshooting)
and the real-package fixtures.

| Symptom | Diagnose and respond |
|---|---|
| Native abort: invalid boolean `--disable-color` | Agent/CI may set `NO_COLOR=1`; normalize to `true` in the launcher or remove it from the child environment; see [diagnostics](observability.md#native-startup-in-agent-and-ci-environments) |
| DllNotFoundException for dittoffi | Verify selected RID, native DLL and transitive native package in the startup executable's output |
| BadImageFormatException | Match process/native architecture; net48 must not prefer 32-bit |
| Compile error for DittoSDK.Store on v4 | v4 keeps those types in the root namespace; establish package version first |
| IDisposable error for v4 observer | Cancel explicitly; v4 observer does not implement IDisposable |
| Invalid DQL task failure | Await/catch the task; verify query and bound values without logging credentials |
| Observer stops updating | Check explicit cancellation, handle ownership, signalNext, callback exceptions and UI dispatch |
| Permission denied | Show an actionable state; do not start sync assuming the prompt succeeded |
| Store already open / locked | Check duplicate instances and directory selection |
| MAUI Xcode/workload version error | Install a supported pairing; do not ship a validation bypass as the fix |

Catch narrowly where the application can recover. Top-level UI actions may catch
Exception to render an error state, but service failures should remain observable.
Do not retry syntax errors or rejected credentials forever. Explicitly catch callback
exceptions and complete any awaiting TaskCompletionSource with an error so tests do
not hang. Cancellation of a waiter does not cancel underlying native work.
