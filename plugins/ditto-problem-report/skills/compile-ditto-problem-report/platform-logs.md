# Platform log-gathering reference

Read this file when the user does not know where their Ditto SDK / app / OS logs are. Use it to give the user platform-specific instructions, then proceed with the report using whatever they can supply.

Ditto SDK log verbosity is configured per-platform; bumping it to DEBUG (or TRACE) before reproducing the issue dramatically improves the report's diagnostic value.

---

## Ditto SDK log levels

All Ditto SDKs expose a global logger that emits to the platform's native log sink. The level should be raised before reproducing the issue.

| SDK                  | Set level (example)                                              | Output sink                                |
| -------------------- | ---------------------------------------------------------------- | ------------------------------------------ |
| Swift (iOS / macOS)  | `DittoLogger.minimumLogLevel = .debug`                           | Apple unified log (`com.ditto.ios`)        |
| Kotlin / Java        | `DittoLogger.setMinimumLogLevel(LogLevel.DEBUG)`                 | Android Logcat (tag prefix `ditto:`)       |
| JS / TS / React Native | `Logger.minimumLogLevel = 'debug'`                              | `console.*` (browser DevTools / Node stderr) |
| C++                  | `Logger::set_minimum_log_level(LogLevel::Debug)`                 | stdout / stderr                            |
| Rust                 | `ditto::Logger::set_minimum_log_level(LogLevel::Debug)`          | stdout via `tracing`                       |
| Go                   | `ditto.SetMinimumLogLevel(ditto.LogLevelDebug)`                  | stdout / stderr                            |
| .NET / MAUI          | `DittoLogger.MinimumLogLevel = LogLevel.Debug`                   | stdout / `Debug` listener                  |
| Flutter / Dart       | `Ditto.setMinimumLogLevel(LogLevel.debug)`                       | `print` / native log sink                  |

For the most diagnostic value, also enable file logging where supported:

- Swift: `try DittoLogger.setLogFileURL(url)`
- Kotlin: `DittoLogger.setLogFileURL(...)`
- C++: `Logger::set_log_file(path)`
- Other SDKs: see <https://docs.ditto.com> for the current API.

---

## Android

**adb logcat capture:**
```bash
# Live, filtered to Ditto + your app's tag, with timestamps:
adb -s <serial> logcat -v threadtime ditto:V <your-app-tag>:V *:S

# Dump existing buffer to a file:
adb -s <serial> logcat -d -v threadtime > ditto-android-logcat.txt
```

**Bug report (verbose system snapshot, recommended for hard cases):**
```bash
adb -s <serial> bugreport ditto-android-bugreport.zip
```

**OS / device info:**
```bash
adb -s <serial> shell getprop ro.build.version.release   # OS version
adb -s <serial> shell getprop ro.product.model           # Device model
```

---

## iOS / macOS

**Console.app** — filter by subsystem `live.ditto` (or `com.ditto.*`) for SDK logs. Use **File → Save** to export.

**Command line:**
```bash
# Last hour of Ditto SDK logs:
log show --predicate 'subsystem CONTAINS "ditto"' --info --debug --last 1h > ditto-apple.log

# Capture a sysdiagnose for serious issues (large, ~200 MB):
sudo sysdiagnose -f /tmp
```

**iOS device logs from a Mac:** Xcode → Window → Devices and Simulators → select device → **View Device Logs**.

**OS version:** `sw_vers -productVersion` (macOS); `Settings → General → About → Software Version` (iOS).

---

## Linux

**journald-managed apps:**
```bash
journalctl -u <service-name> --since "1 hour ago" > app-journal.log
```

**Stdout/stderr capture:** if the Ditto-using app prints to stdout, run with `2>&1 | tee ditto.log`. The Ditto CLI and Ditto Server log to stdout by default.

**OS info:**
```bash
uname -a
cat /etc/os-release
```

---

## Windows

**Event Viewer** — `eventvwr.msc` → Windows Logs → Application. Filter by your app's source name. Right-click → Save All Events As… (`.evtx`).

**PowerShell capture:**
```powershell
Get-WinEvent -ProviderName <YourApp> | Out-File ditto-windows.log
```

**OS info:**
```powershell
Get-ComputerInfo | Select-Object OsName, OsVersion, OsArchitecture
```

---

## JS / Web / Node

**Browser:** open DevTools → Console → right-click → **Save as…** for a `.log` file. Also useful: Network tab → export HAR if WebSocket traffic to Big Peer is relevant.

**Node:** redirect:
```bash
node app.js > ditto-node.log 2>&1
```

Set `DEBUG=ditto:*` (if the app uses the `debug` library) for additional diagnostic output.

---

## Big Peer

For Big Peer (cloud) issues, in addition to client logs, include:

- **Ditto Database ID (App ID)** (from the Ditto portal) — this field is captured in the report header; do not duplicate it here, but ensure it is set there before filing.
- **Region / cluster** if multi-region.
- **Approximate UTC time window** of the failure (start / end).
- **Portal diagnostics** — screenshots of the dashboard's Sync, Logs, or Vitals tabs around the failure window.
- **HTTP API responses** if the issue involves the Big Peer HTTP API — include the full response body and headers (status code, `x-request-id` if present).

---

## What if the user can't capture logs?

Proceed with the report anyway. Note "logs unavailable" in the Attachments section and capture as much detail as possible about timing, frequency, and observable behaviour. Many Ditto issues can be diagnosed from a precise reproduction recipe alone.
