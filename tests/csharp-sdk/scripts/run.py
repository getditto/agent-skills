#!/usr/bin/env python3
"""Run real NuGet fixtures. Environment overrides the repository's optional .env."""
import argparse
import os
import re
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
# Native trace lines ("2026-11-14T13:04:47.039621-06:00  INFO ...") can contain application
# data, so they stay in the local runtime.log and never reach the CI transcript.
NATIVE_TRACE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")


def environment(version):
    env = os.environ.copy()
    path = ROOT / ".env"
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line.startswith("export "):
                line = line[7:]
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            env.setdefault(key.strip(), value)
    if not env.get("DITTO_OFFLINE_LICENSE"):
        raise SystemExit("DITTO_OFFLINE_LICENSE is required (environment or repository .env).")
    if not env.get("DITTO_DATABASE_ID"):
        env.pop("DITTO_DATABASE_ID", None)
    env["DITTO_CSHARP_VERSION"] = version
    env["RUST_LOG"] = "error"
    env.pop("NO_COLOR", None)
    return env


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", default="5.2.0")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--framework", choices=["net8.0", "net10.0", "net11.0"], default="net10.0")
    args = parser.parse_args()
    runs = []
    for version in (["4.14.7", "5.0.4", "5.1.0", "5.2.0"] if args.all else [args.version]):
        runs.append((version, "Core", version + "-" + args.framework))
        # The WinForms starter's C# 7.3 copy uses v5 APIs; run the same starter tests on it.
        if not version.startswith("4."):
            runs.append((version, "LegacyStarterTests", version + "-" + args.framework + "-legacy"))
    for version, project, label in runs:
        print("== " + project + " / Ditto " + version)
        result = subprocess.run(["dotnet", "test", str(ROOT / "tests/csharp-sdk" / project),
                        "-p:DittoVersion=" + version, "-p:TestTargetFramework=" + args.framework, "--artifacts-path",
                        str(ROOT / "tests/csharp-sdk/artifacts" / label),
                        "--blame-hang-timeout", "45s", "--blame-hang-dump-type", "none",
                        "--logger", "console;verbosity=normal",
                        # Test names, assertion messages and stack traces only; CI uploads these on failure.
                        "--logger", "trx;LogFileName=" + label + ".trx",
                        "--results-directory", str(ROOT / "tests/csharp-sdk/artifacts/results")],
                       env=environment(version), text=True, capture_output=True, timeout=300)
        output = result.stdout + result.stderr
        log = ROOT / "tests/csharp-sdk/artifacts" / label / "runtime.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(output)
        # Native trace lines can contain application data. Keep them in ignored local
        # artifacts, not the CI transcript; report test/compile diagnostics only.
        failure_lines = 0
        for line in output.splitlines():
            stripped = line.lstrip()
            if stripped.startswith(("Passed ", "Failed ", "Skipped ", "Passed:", "Skipped:", "Failed:", "Total tests:", "Test Run", "Total time:")) or line.startswith("[xUnit.net") or ("error " in line and ".csproj" in line):
                print(line)
                # A failed test's message and stack trace follow it; keep those (capped).
                failure_lines = 60 if stripped.startswith("Failed ") else 0
            elif failure_lines and not NATIVE_TRACE.match(stripped):
                print(line)
                failure_lines -= 1
        if result.returncode:
            print("Full local diagnostics (review before sharing): " + str(log))
            raise SystemExit(result.returncode)
