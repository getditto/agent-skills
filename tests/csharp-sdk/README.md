# C# / .NET skill verification

The fixtures use real NuGet packages and native Ditto stores. No SDK mock establishes
API or persistence correctness. Requires Python 3.9+, .NET 10 SDK and a valid offline
license in the environment or repository `.env`; environment values win. Optionally
set `DITTO_DATABASE_ID` to the database bound to the license. Tests never need cloud
credentials. Raw native traces are kept in ignored `artifacts/<version>-<tfm>/runtime.log`;
the runner prints test diagnostics only. Review raw logs for application data before sharing.

## Run locally

From the repository root:

```bash
python3 tests/csharp-sdk/scripts/run.py --all
python3 tests/csharp-sdk/scripts/run.py 5.2.0 --framework net8.0
python3 tests/csharp-sdk/scripts/verify-minimal.py
python3 tests/csharp-sdk/scripts/verify-package.py
python3 tests/csharp-sdk/scripts/verify-starters.py --runtime
python3 -m unittest discover -s tests/csharp-sdk -p 'test_*.py' -v
python3 scripts/validate-sdk-skills.py
python3 scripts/package-sdk-plugin.py --plugin ditto-csharp --check
```

The net8 run additionally needs the .NET 8 runtime. Fixed matrix pins are 4.14.7,
5.0.4, 5.1.0 and 5.2.0; generated projects resolve current stable v5 by default.
Core tests link the exact canonical starter sources and the modern async-enumeration
adapter. Sync-checking embedded template copies and byte-checking the minimal program
prevent tests from validating a different implementation than customers receive.

The core suite covers parameterized CRUD, POCO/record conversion, explicit GUID/time/
decimal representations, integer/null/nested/array values, observer lifetime, manual
and Task-based back-pressure, async enumerable cancellation, indexing/eviction,
transactions, same-version reopen, attachment bytes, TCP replication/presence and
starter rollback/retry/field-preserving edits. Public-API assertions guard the Data
Streams absence claim. Timeouts fail rather than treating a hung native host as success.

**Known skip:** the commit/rollback transaction probe hangs on macOS ARM64 with 5.0.3
and 5.0.4. The regular 5.0.4 matrix explicitly skips it (on all hosts until investigated).
Other versions execute it. The 45-second blame watchdog remains enabled; to reproduce
the 5.0.x failure, remove the `DITTO_50` skip in `StoreTests.cs` and filter that test.
Do not infer a root cause or general transaction-support guarantee from this observation.

## Generated projects and native deployment

The generator verifier uses an isolated `dotnet new` hive and temporary output outside
the source tree. Desktop checks compile Console/Avalonia/Uno, publish Console, and,
with `--runtime`, exercise its CLI through two processes to prove persistence. It checks
CRUD observations and field-preserving edits, with deadlines and a nonzero-exit check.
A negative control verifies that WebAssembly is rejected by the project target.

```bash
# Windows x64: desktop projects plus net48/net481/net10.0-windows WinForms
python tests/csharp-sdk/scripts/verify-starters.py --platform windows --runtime
dotnet build tests/csharp-sdk/LegacySmoke
# Run the built LegacySmoke.exe on Windows with DITTO_OFFLINE_LICENSE configured.

# Hosts with matching workloads/toolchains; these are build gates, not device tests
python3 tests/csharp-sdk/scripts/verify-starters.py --platform android
python3 tests/csharp-sdk/scripts/verify-starters.py --platform apple --apple-target ios
python3 tests/csharp-sdk/scripts/verify-starters.py --platform apple --apple-target maccatalyst
```

The net48 executable links the real shared service with C# 7.3, loads the native DLL,
writes and awaits an observer, then deletes and shuts down. It complements Framework
reference-assembly cross-compilation, which cannot verify native loading on Windows.
Traditional packages.config and GUI interaction still require separate validation.

To update shared code, edit the canonical files under the skill's `assets/common`,
run `python3 tests/csharp-sdk/scripts/sync-starters.py`, then run the affected SDK and
starter checks. Build artifacts and local stores must never enter plugin archives.

## Recorded evidence (2026-11-10)

| Gate | Result on this checkout |
|---|---|
| Real core matrix, macOS ARM64, .NET 10 | 4.14.7: 10 passed; 5.0.4: 19 passed, 1 explicit transaction skip; 5.1.0 and 5.2.0: 20 passed each |
| .NET 8 with Ditto 5.2.0 | Passed |
| Generated Console, Avalonia, Uno desktop | Build passed |
| Published Console | CRUD, observer updates and process-restart persistence passed |
| net48 WinForms | Cross-compile passed; Windows execution pending |
| MAUI Android | Build passed; device behavior pending |
| MAUI Mac Catalyst | Exploratory compile passed only with Xcode-version validation overridden; not counted as supported-toolchain validation |
| MAUI iOS / Windows | CI gates supplied; not yet executed locally |
| Cloud, radios/background execution, GUI interaction | Not verified |
| Cross-version on-disk upgrade/downgrade | Not verified; same-version reopen only |
| Live-agent use of installed skill | Cases supplied; not executed |

Local Apple workload 26.2 requires Xcode 26.2; installed Xcode 27.2 is incompatible
with its normal validation. CI selects the matching toolchain and must fail if it is
missing. Do not turn off validation as a customer build recommendation. Check current
runner images/toolchain availability when updating the pinned fixture.

## Manual acceptance before claiming broader platform support

Install a generated release artifact on the intended OS/device. Create, rename, toggle
and delete tasks; restart and check persistence. Deny then grant permissions, verify UI
updates arrive on the UI thread, close during an in-flight write, and reopen. Use two
physical devices for radio replication; disconnect the network and repeat. Verify cloud
login renewal and Big Peer durability independently with dedicated test credentials.
For AOT/trimming, test the actual release build and serializer metadata on target.

Agent evaluation cases are in [the shared catalog](../skill-context/cases.json). Run
through the existing context harness or a real supported agent host; report host/model,
which references loaded, generated artifact and build/runtime result. Static packaging
and context-budget checks do not certify every AI agent's behavior.
