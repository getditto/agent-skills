#!/usr/bin/env python3
"""Run real NuGet fixtures. Environment overrides the repository's optional .env."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]


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
    for version in (["4.14.7", "5.0.4", "5.1.0", "5.2.0"] if args.all else [args.version]):
        result = subprocess.run(["dotnet", "test", str(ROOT / "tests/csharp-sdk/Core"),
                        "-p:DittoVersion=" + version, "-p:TestTargetFramework=" + args.framework, "--artifacts-path",
                        str(ROOT / "tests/csharp-sdk/artifacts" / (version + "-" + args.framework)),
                        "--blame-hang-timeout", "45s", "--blame-hang-dump-type", "none",
                        "--logger", "console;verbosity=normal"],
                       env=environment(version), text=True, capture_output=True, timeout=300)
        output = result.stdout + result.stderr
        log = ROOT / "tests/csharp-sdk/artifacts" / (version + "-" + args.framework) / "runtime.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(output)
        # Native trace lines can contain application data. Keep them in ignored local
        # artifacts, not the CI transcript; report test/compile diagnostics only.
        for line in output.splitlines():
            if line.lstrip().startswith(("Passed ", "Failed ", "Skipped ", "Passed:", "Skipped:", "Failed:", "Total tests:", "Test Run", "Total time:")) or line.startswith("[xUnit.net") or ("error " in line and ".csproj" in line):
                print(line)
        if result.returncode:
            print("Full local diagnostics (review before sharing): " + str(log))
            raise SystemExit(result.returncode)
