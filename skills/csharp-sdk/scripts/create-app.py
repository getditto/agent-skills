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
# Release-note floors for the targets these starters build.
MINIMUM_VERSIONS = {
    # 5.2.0 fixed the .NET 10 Android startup abort with Xamarin.Kotlin 2.x
    # ("Built-in class kotlin.Any is not found"), plus armeabi-v7a and permission crashes.
    "maui": ((5, 2, 0), ".NET 10 MAUI on Android requires Ditto 5.2.0 or later."),
    # 5.0.1 added the netstandard2.0 asset that .NET Framework needs.
    "net48": ((5, 0, 1), ".NET Framework requires Ditto 5.0.1 or later."),
    "net481": ((5, 0, 1), ".NET Framework requires Ditto 5.0.1 or later."),
}


def resolve_version():
    with urllib.request.urlopen("https://api.nuget.org/v3-flatcontainer/ditto/index.json", timeout=20) as response:
        versions = json.load(response)["versions"]
    stable = [v for v in versions if re.fullmatch(r"\d+\.\d+\.\d+", v)]
    # These starters use the v5 API. A new major needs an explicit compatibility review.
    stable = [v for v in stable if v.startswith("5.")]
    if not stable:
        raise ValueError("No stable Ditto v5 package was found.")
    return max(stable, key=lambda v: tuple(map(int, v.split("."))))


WINFORMS_FRAMEWORKS = {"net48", "net481", "net10.0-windows"}
MAUI_FRAMEWORKS = {"net10.0", "net11.0"}
# Apple targets build only with the Xcode their workload's Apple packs were made for.
MAUI_XCODE = {
    "net10.0": "Apple targets need Xcode 26.x; with Xcode 27 or later, use --framework net11.0.",
    "net11.0": "Apple targets need Xcode 27 or later and the .NET 11 SDK with the MAUI workload.",
}


def maui_framework_for_active_sdk():
    """net11.0 when the active SDK (which honours global.json) is .NET 11 or later, else net10.0."""
    try:
        active = subprocess.run(["dotnet", "--version"], capture_output=True, text=True,
                                check=True, timeout=60).stdout.strip()
        major = int(active.split(".")[0])
    except (OSError, subprocess.SubprocessError, ValueError):
        return "net10.0"
    return "net11.0" if major >= 11 else "net10.0"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["console", "winforms", "maui", "uno", "avalonia"])
    parser.add_argument("output", type=Path)
    parser.add_argument("--name", default="DittoTasks")
    parser.add_argument("--sdk-version", help="Exact stable v5 pin; otherwise resolve NuGet")
    parser.add_argument("--framework", choices=sorted(WINFORMS_FRAMEWORKS | MAUI_FRAMEWORKS),
                        help="WinForms: net48 (default), net481, net10.0-windows. "
                             "MAUI: net10.0 or net11.0 (default: matches the active .NET SDK).")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", args.name):
        parser.error("Name must be a C# identifier starting with a letter.")
    if args.name.lower() == "ditto":
        parser.error("Name must not be 'Ditto': a project named after the Ditto package cannot restore it (NU1108).")
    if args.framework and not (
            (args.kind == "winforms" and args.framework in WINFORMS_FRAMEWORKS)
            or (args.kind == "maui" and args.framework in MAUI_FRAMEWORKS)):
        parser.error(f"--framework {args.framework} is not an option for the {args.kind} starter.")
    destination = args.output.resolve()
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        parser.error("Output must be absent or empty; existing projects are never overwritten.")
    if not shutil.which("dotnet"):
        parser.error("Install the .NET 10 SDK and the target's required workloads first.")
    version = args.sdk_version or resolve_version()
    if not re.fullmatch(r"5\.\d+\.\d+", version):
        parser.error("Select an exact stable v5 version; prereleases and v4 need separate adaptation.")
    # The WinForms template defaults to net48 when --framework is omitted.
    target = (args.framework or "net48") if args.kind == "winforms" else args.kind
    minimum = MINIMUM_VERSIONS.get(target)
    if minimum and tuple(map(int, version.split("."))) < minimum[0]:
        parser.error(f"Ditto {version} is too old for this starter: {minimum[1]}")
    if args.kind == "maui" and not args.framework:
        args.framework = maui_framework_for_active_sdk()
    if args.kind == "maui":
        print(f"MAUI {args.framework}: " + MAUI_XCODE[args.framework], flush=True)
    print(f"Creating {args.kind} with Ditto {version}. Knowledge baseline: 5.2.0.", flush=True)
    if tuple(map(int, version.split("."))) > (5, 2, 0):
        print("Read the newer release notes and validate this generated app before relying on it.", flush=True)
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
