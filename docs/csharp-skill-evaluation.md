# C# skill forward evaluation

Five independent platform evaluations build a projects-and-tasks application from the
frozen C# skill at commit `04c0efc38eb034181346287989830961ccdea776`. The application
requirements include project/task editing, relationships, due dates, status/phase,
project managers, descriptions/notes, and PDF/image/audio attachments backed by Ditto.

## Method

Evaluators receive the raw application brief, the skill's bundled references/assets,
current package version metadata and local credential configuration. They may use
framework knowledge, official template code and compiler/runtime feedback. They may
not consult external SDK/framework documentation, existing repository fixtures or
another evaluator's implementation. Any assembly inspection needed to recover missing
API information must be logged. Parent repairs are recorded separately from first-pass
results. The frozen snapshot is retained unchanged for audit.

Each application has repositories/services/view models, a native UI (or terminal UI),
an isolated real-SDK smoke harness, and instructions for running it on supported hosts.
The five evaluations are Console, WinForms (net48 and modern variants), MAUI, Uno and
Avalonia. The evaluated modern target is .NET 11, newer than the original starter's
.NET 10 baseline. WinForms remains Windows-only; MAUI has no official Linux desktop
host. Linux coverage comes from Console, Uno and Avalonia.

## Toolchain and verification boundaries

The official release feed resolved .NET SDK 11.0.100/runtime 11.0.0. NuGet resolved
Ditto 5.2.0, MAUI 11.0.0, Avalonia 12.1.6 and Uno.Sdk 7.0.5. The SDK and workloads
are installed in the evaluation workspace, preserving machine-global installations.
Legacy WinForms remains .NET Framework 4.8/C# 7.3 as explicitly requested.

The existing C# core fixture passes all 20 tests on .NET 11 with Ditto 5.2.0.
This is separate from application-specific acceptance. Earlier .NET 10 starter CI
[run 42951049915](https://github.com/getditto/agent-skills/actions/runs/42951049915)
passed its Windows/Linux/macOS core and generated-app jobs, net48 native smoke, and
all four MAUI build targets. Neither result establishes GUI interaction or physical
radio behavior in these newly generated apps.

## Results

| Application | Independent real-SDK smoke | Framework/build evidence |
|---|---:|---|
| Console TUI | 20 passed | Spectre.Console 0.57.2; macOS ARM64 and Windows/Linux publish |
| WinForms | 25 passed in portable harness | net48/C# 7.3 and net11.0-windows Release builds, native Windows payloads inspected |
| MAUI | 21 passed in portable harness | Catalyst/iOS simulator/Android builds; Windows GUI compiler requires Windows |
| Uno | 26 passed | Uno.Sdk 7.0.5 native desktop, macOS/Windows/Linux publish |
| Avalonia | 14 passed | Avalonia 12.1.6, macOS/Windows/Linux publish |

These are completed independent runs after compiler/runtime-driven corrections, not
first-attempt successes. No evaluator reported needing external API documentation or
assembly inspection. GUI/picker integration and the application architecture still
required agent engineering beyond the bundled starter. Source archives omit credentials,
native stores and build outputs; the original snapshot remains unchanged.

The Console terminal UI was exercised through a real POSIX terminal: CRUD, pane navigation,
PDF import/list/export and byte equality. Parent native UI checks exercised Avalonia task
creation, persistence, filtering, native attachment picker and native export. MAUI displayed
the same project/task/attachment from a separate store; a MAUI edit appeared in Avalonia's
live list. MAUI fetched the attachment and opened its native share popover, which was
closed without an external share. These observations establish app-to-app replication,
not a specific transport or server durability.

## Findings and corrections

1. All five evaluators encountered a native process abort with inherited `NO_COLOR=1`.
   Ditto 5.2.0's tracing parser expects a boolean string for its derived `--disable-color`
   option. Setting `NO_COLOR=true` in the parent/child launch environment resolved it.
   A managed Environment.SetEnvironmentVariable call alone did not affect the native
   parser on this host. Diagnostics/error references now document the verified remedy.
2. Uno reproduced CopyToPath failure for an existing export destination. Guidance now
   stages into a new sibling file before replacing an approved destination, retaining
   existing contents through failed fetches. The canonical real-SDK attachment test
   verifies this behavior across all four SDK matrix lines.
3. NewAttachmentAsync returns a disposable native handle. Attachment guidance now
   explicitly retains it through the awaited INSERT and disposes it afterward.
4. A new .NET 11 SDK initially selected older Apple workload manifests. Updating the
   workload set paired Apple 27.2.11039 with Xcode 27.2. Framework migration also required
   minimum Apple OS 17 and current UIKit scene configuration. MAUI guidance records
   these observed migration steps without recommending disabled Xcode validation.
5. Parent review found MAUI whole-record updates overwrote unrelated incoming fields and
   resurrected deleted records. Field-diff updates, original editor baselines, stale-edit
   rejection and selection reconciliation fixed these cases. MAUI's expanded real-SDK
   harness passes 29 assertions. Architecture guidance now explains the baseline/creation
   distinction; local transactions do not enforce distributed foreign keys.
6. Parent review found a MAUI export cache path derived from synchronized IDs. The app
   now generates a local directory and sanitizes filenames; a regression preserves an
   outside sentinel for absolute/traversal IDs. Attachment guidance covers this boundary.
7. Native UI review corrected Avalonia/MAUI contrast, disabled actions, selection and
   accessibility labels. These are application corrections, not new Ditto API claims.

After the attachment regression, the canonical .NET 10 matrix passes 4.14.7 (10), 5.0.4
(19 plus one explicit known transaction skip), 5.1.0 (20) and 5.2.0 (20). The .NET 11 /
5.2.0 run passes 20. Structural, packaging and source-synchronization checks also pass.

## Remaining verification boundaries

Windows/Linux GUI execution for the new apps is pending destination-machine testing;
publishing and native asset inspection are not runtime evidence. WinForms is Windows-only,
including modern .NET, and MAUI has no official Linux desktop target. Linux options are
Console, Avalonia and Uno. Physical mobile devices, permission denial/retry, background
execution, large/interrupted transfers, shutdown during an active platform fetch and
release trimming/AOT remain separate acceptance work. This evaluation does not certify
all AI agent hosts/models or production server authentication/durability.

## Final post-review acceptance

Expanded application regression suites pass Console28, WinForms29, MAUI29, Uno30 and
Avalonia22 assertions (138 total). They additionally cover stale changed/unchanged
edits after deletion, preexisting attachment destinations, failed replacement preserving
bytes and staging cleanup. Console terminal interaction passed again after repairs, and
published artifacts were refreshed from final sources. These counts are distinct from
the independent results above.

Uno's initial screen revealed cramped high-DPI sizing and sidebar contrast issues.
Source fixes compile and native smoke passes, but complete post-repair interaction is
pending: the native UI connection stopped finding windows for all three running apps.
No claim of verified final Uno layout or a proven Uno startup defect follows from that
provider failure. An invalid UI PNG fixture also means its byte-identical export check
establishes binary transfer, not image rendering; final smoke PNG fixtures are valid.
