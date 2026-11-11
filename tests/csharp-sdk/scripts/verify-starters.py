#!/usr/bin/env python3
"""Generate/build installed templates; execute the published console's real CRUD flow."""
import argparse
import importlib.util
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / "skills/csharp-sdk"
spec = importlib.util.spec_from_file_location("csharp_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def command(args, cwd=None, env=None, timeout=300):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        # Build output contains no test credentials. Runtime is handled separately below.
        raise RuntimeError("Command failed: " + " ".join(args) + "\n" + result.stdout[-7000:] + result.stderr[-2000:])
    return result.stdout


class ConsoleApp:
    def __init__(self, dll, env):
        self.lines = queue.Queue()
        self.process = subprocess.Popen(["dotnet", str(dll)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, env=env)
        def read():
            for line in self.process.stdout:
                self.lines.put(line.strip())
            self.lines.put(None)
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()

    def send(self, text):
        self.process.stdin.write(text + "\n")
        self.process.stdin.flush()

    def until(self, predicate):
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            try:
                line = self.lines.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if line is None:
                raise AssertionError("Console exited before the expected observation.")
            if predicate(line):
                return line
        raise AssertionError("Console did not produce the expected observation within 20 seconds.")

    def close(self):
        try:
            if self.process.poll() is None:
                self.send("quit")
            assert self.process.wait(timeout=20) == 0
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.process.stdin.close()
            self.process.stdout.close()
            self.reader.join(timeout=2)


def console_runtime(dll, env, store_path):
    env = env.copy()
    env.pop("DITTO_URL", None)
    env.pop("DITTO_TOKEN", None)
    env.setdefault("DITTO_DATABASE_ID", "e807f150-cb5d-4aa5-bcef-cc90e8521b91")
    env["DITTO_PERSISTENCE_DIRECTORY"] = str(store_path)
    app = ConsoleApp(dll, env)
    try:
        app.until(lambda line: line.startswith("Commands:"))
        app.send("add Integration task")
        line = app.until(lambda line: line.endswith("[ ] Integration task"))
        document_id = line.split()[0]
        assert re.fullmatch(r"[0-9a-f-]{36}", document_id)
        app.send("done " + document_id)
        app.until(lambda line: line == document_id + " [x] Integration task")
        app.send("edit " + document_id + " Renamed task")
        app.until(lambda line: line == document_id + " [x] Renamed task")
    finally:
        app.close()
    reopened = ConsoleApp(dll, env)
    try:
        reopened.until(lambda line: line == document_id + " [x] Renamed task")
        reopened.send("reopen " + document_id)
        reopened.until(lambda line: line == document_id + " [ ] Renamed task")
        reopened.send("delete " + document_id)
        # A subsequent write is a positive control that observation continues after deletion.
        reopened.send("add After deletion")
        reopened.until(lambda line: line.endswith("[ ] After deletion"))
    finally:
        reopened.close()
    print("PASS published console CRUD, observer delivery and process-restart persistence")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["desktop", "windows", "android", "apple", "maui-windows"], default="desktop")
    parser.add_argument("--sdk-version", default="5.2.0")
    parser.add_argument("--runtime", action="store_true", help="Requires offline license; exercise published console")
    parser.add_argument("--apple-target", choices=["ios", "maccatalyst"], default="maccatalyst")
    args = parser.parse_args()
    command([sys.executable, str(Path(__file__).with_name("sync-starters.py")), "--check"])
    with tempfile.TemporaryDirectory(prefix="ditto-generated-check-") as temporary:
        workspace = Path(temporary).resolve()  # Avoid /tmp symlink resource-path mismatches in MAUI.
        hive = workspace / "hive"
        command(["dotnet", "new", "install", str(SKILL / "assets/templates"), "--debug:custom-hive", str(hive)])
        kinds = ["console", "avalonia", "uno"] if args.platform in ("desktop", "windows") else ["maui"]
        if args.platform == "windows": kinds += ["winforms"]
        for kind in kinds:
            frameworks = ["net48", "net481", "net10.0-windows"] if kind == "winforms" else [None]
            for framework in frameworks:
                folder = workspace / (kind + (framework or ""))
                generate = ["dotnet", "new", "ditto-" + kind, "-n", "VerifiedTasks", "-o", str(folder),
                            "--ditto-version", args.sdk_version, "--debug:custom-hive", str(hive)]
                if framework: generate += ["--framework", framework]
                command(generate)
                build = ["dotnet", "build", str(folder)]
                if kind == "maui":
                    target = {"android": "android", "maui-windows": "windows10.0.19041.0"}.get(args.platform, args.apple_target)
                    tfm = "net10.0-" + target
                    build += ["-f", tfm, "-p:TargetFrameworks=" + tfm]
                    if args.apple_target == "ios" and args.platform == "apple": build += ["-r", "iossimulator-arm64"]
                command(build, timeout=600)
                print("PASS generated build: " + kind + " " + (framework or args.platform))
                if kind == "console":
                    published = folder / "published"
                    command(["dotnet", "publish", str(folder), "-c", "Release", "-o", str(published)])
                    if args.runtime: console_runtime(published / "VerifiedTasks.dll", runner.environment(args.sdk_version), workspace / "store")
                if kind == "winforms":
                    dlls = list((folder / "bin").rglob("dittoffi.dll"))
                    assert dlls, "WinForms output is missing its native DLL"
        # Check the template's explicit native boundary without running NuGet restore for WASM.
        if args.platform in ("desktop", "windows"):
            project = workspace / "console/VerifiedTasks.csproj"
            rejected = subprocess.run(["dotnet", "msbuild", str(project), "-t:CheckDittoTarget",
                                       "-p:RuntimeIdentifier=browser-wasm"], text=True, capture_output=True)
            assert rejected.returncode != 0 and "no WebAssembly runtime" in rejected.stdout
            print("PASS unsupported WebAssembly target rejected")


if __name__ == "__main__":
    main()
