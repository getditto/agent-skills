#!/usr/bin/env python3
"""Compile and exercise the canonical starter model against a resolved macOS SDK.

After building the generated app for macOS:
  python3 tests/swift-sdk/scripts/test-starter.py 5.1.0 --frameworks <DerivedData>/Build/Products/Debug
Requires DITTO_OFFLINE_LICENSE; optionally reads the repository's gitignored .env.
Never prints configuration values or the SDK's potentially sensitive diagnostics.
"""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def environment():
    result = dict(os.environ)
    config = ROOT / ".env"
    if config.exists():
        for line in config.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.partition("=")
            if separator and key in ("DITTO_OFFLINE_LICENSE", "DITTO_DATABASE_ID") and not result.get(key):
                value = value.strip()
                if len(value) >= 2 and value[0] in ("'", '"') and value[-1] == value[0]:
                    value = value[1:-1]
                result[key] = value
    result.pop("NO_COLOR", None)  # Ditto's Rust core rejects SwiftPM's NO_COLOR=1.
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", choices=("4.14.6", "5.0.3", "5.1.0"))
    parser.add_argument("--frameworks", type=Path, required=True,
                        help="macOS build products directory containing the resolved .frameworks")
    args = parser.parse_args()
    env = environment()
    if not env.get("DITTO_OFFLINE_LICENSE"):
        parser.exit(1, "DITTO_OFFLINE_LICENSE is required (environment or repository .env).\n")
    frameworks = args.frameworks.resolve()
    if not (frameworks / "DittoSwift.framework").is_dir():
        parser.error("--frameworks must contain a macOS DittoSwift.framework")

    with tempfile.TemporaryDirectory(prefix="ditto-starter-runtime-") as temporary:
        work = Path(temporary)
        runtime = work / "Frameworks"
        runtime.mkdir()
        for source in frameworks.glob("*.framework"):
            target = runtime / source.name
            shutil.copytree(source, target, symlinks=True)
            executable = target / "Versions/A" / source.stem
            subprocess.run(["codesign", "--force", "--sign", "-", str(executable)],
                           check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        command = ["swiftc", "-swift-version", "6", "-parse-as-library", "-D", "DITTO_STARTER_TESTING",
                   "-F", str(frameworks), "-framework", "DittoSwift",
                   "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks"]
        if args.version.startswith("4."):
            command += ["-D", "DITTO_V4"]
        command += [str(ROOT / "skills/swift-sdk/assets/swiftui-starter/StarterApp.swift"),
                    str(Path(__file__).with_name("StarterRuntimeProbe.swift")), "-o", str(work / "Probe")]
        compiled = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if compiled.returncode:
            print(compiled.stderr)
            return compiled.returncode
        (work / "LocalConfig.plist").write_bytes(plistlib.dumps({
            "DatabaseID": env.get("DITTO_DATABASE_ID") or "00000000-0000-0000-0000-000000000000",
            "OfflineLicense": env["DITTO_OFFLINE_LICENSE"],
        }))
        # Loader paths refer only to private copies, never mutate Xcode's artifact cache.
        env["DYLD_FRAMEWORK_PATH"] = str(runtime)
        try:
            result = subprocess.run([str(work / "Probe"), str(work / "LocalConfig.plist"),
                                     str(work / "Store"), args.version], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            print(f"FAIL {args.version}: starter runtime timed out")
            return 1
        # SDK logs can include authentication information; emit only our fixed-format checks.
        for line in result.stdout.splitlines():
            if line.startswith(("CHECK ", "PASS ", "FAIL ")):
                print(line)
        if result.returncode:
            print(f"FAIL {args.version}: starter runtime exited {result.returncode}")
            return 1
        if "PASS canonical starter runtime" not in result.stdout.splitlines():
            print(f"FAIL {args.version}: completion marker missing")
            return 1
        print(f"PASS SDK {args.version}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
