#!/usr/bin/env python3
"""Create a self-contained native Ditto app with a resolved stable NuGet version."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request

SKILL = Path(__file__).resolve().parents[1]


def resolve_version():
    with urllib.request.urlopen("https://api.nuget.org/v3-flatcontainer/ditto/index.json", timeout=20) as response:
        versions = json.load(response)["versions"]
    stable = [v for v in versions if re.fullmatch(r"\d+\.\d+\.\d+", v)]
    # These starters use the v5 API. A new major needs an explicit compatibility review.
    stable = [v for v in stable if v.startswith("5.")]
    if not stable:
        raise ValueError("No stable Ditto v5 package was found.")
    return max(stable, key=lambda v: tuple(map(int, v.split("."))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["console", "winforms", "maui", "uno", "avalonia"])
    parser.add_argument("output", type=Path)
    parser.add_argument("--name", default="DittoTasks")
    parser.add_argument("--sdk-version", help="Exact stable v5 pin; otherwise resolve NuGet")
    parser.add_argument("--framework", choices=["net48", "net481", "net10.0-windows"], help="WinForms only")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", args.name):
        parser.error("Name must be a C# identifier starting with a letter.")
    if args.framework and args.kind != "winforms":
        parser.error("--framework is currently a WinForms option.")
    destination = args.output.resolve()
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        parser.error("Output must be absent or empty; existing projects are never overwritten.")
    if not shutil.which("dotnet"):
        parser.error("Install the .NET 10 SDK and the target's required workloads first.")
    version = args.sdk_version or resolve_version()
    if not re.fullmatch(r"5\.\d+\.\d+", version):
        parser.error("Select an exact stable v5 version; prereleases and v4 need separate adaptation.")
    print(f"Creating {args.kind} with Ditto {version}. Knowledge baseline: 5.2.0.")
    if tuple(map(int, version.split("."))) > (5, 2, 0):
        print("Read the newer release notes and validate this generated app before relying on it.")
    with tempfile.TemporaryDirectory(prefix="ditto-template-hive-") as temporary:
        hive = str(Path(temporary).resolve())
        subprocess.run(["dotnet", "new", "install", str(SKILL / "assets/templates"),
                        "--debug:custom-hive", hive], check=True, timeout=60)
        command = ["dotnet", "new", "ditto-" + args.kind, "-n", args.name,
                   "-o", str(destination), "--ditto-version", version, "--debug:custom-hive", hive]
        if args.framework:
            command += ["--framework", args.framework]
        subprocess.run(command, check=True, timeout=60)
    print("Generated: " + str(destination))
    print("Configure appsettings.json (or desktop environment variables), then follow the framework reference to build and run.")


if __name__ == "__main__":
    main()
