#!/usr/bin/env python3
"""Drive a Flutter hot restart against an open Ditto instance and print what happens.

    python3 tests/flutter-sdk/scripts/hot-restart.py --device macos|chrome --mode v1|v2|holder
        [--line 5.2] [--observe 30] [--peer]

Runs integration_test/hot_restart/hot_restart_app.dart with `flutter run -d <device>`
(debug) in a use-version.py copy of minimal_app pinned to <line>, with stdin attached.
Once the app prints `HR: ready`, it sends `R` (hot restart), watches for --observe
seconds, sends `q`, and kills whatever is left. --peer (macos only) sets
HOT_RESTART_PEER=true: after the restart a second instance writes a document to the
orphaned one over TCP loopback, so its observer has a change to deliver. Chrome runs headless. Records go to
tests/flutter-sdk/README.md, "Manual records"; this script is how they were driven.

Prints every `HR: ` line the app writes plus the flutter tool's restart, crash and exit
lines, each with seconds since launch; the full output goes to
tests/flutter-sdk/hot-restart-<device>-<line>-<mode>.log (gitignored). The license
reaches Flutter only through web-probe.py's mode-600 --dart-define-from-file file and
is redacted from the output; the fixture copy, whose builds embed it, is deleted at the
end. Bounded: 900 s for the first launch, then --observe.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
_SPEC = importlib.util.spec_from_file_location("web_probe", HARNESS / "scripts/web-probe.py")
WEB_PROBE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(WEB_PROBE)

TARGET = "integration_test/hot_restart/hot_restart_app.dart"
TOOL_MARKERS = ("Performing hot restart", "Restarted application", "Lost connection",
                "Application finished", "Exception", "Error", "crash", "SIGABRT",
                "Callback invoked after it has been deleted")


def interesting(line: str) -> bool:
    return "HR: " in line or any(marker in line for marker in TOOL_MARKERS)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", required=True, choices=["macos", "chrome"])
    parser.add_argument("--mode", required=True, choices=["v1", "v2", "holder"])
    parser.add_argument("--line", default="5.2", choices=["5.1", "5.2"])
    parser.add_argument("--observe", type=float, default=30.0)
    parser.add_argument("--peer", action="store_true")
    args = parser.parse_args(argv)

    pin = json.loads((HARNESS / "versions.json").read_text())["lines"][args.line]
    secret = WEB_PROBE.offline_license()
    WEB_PROBE.exit_on_sigterm()
    workdir = WEB_PROBE.prepare_workdir(args.line)
    try:
        if args.peer and args.device != "macos":
            parser.error("--peer needs a native device (macos)")
        suffix = "-peer" if args.peer else ""
        log_path = HARNESS / f"hot-restart-{args.device}-{args.line}-{args.mode}{suffix}.log"
        defines = {"DITTO_LICENSE": secret, "DITTO_VERSION": pin, "HOT_RESTART_MODE": args.mode,
                   "HOT_RESTART_PEER": "true" if args.peer else "false"}
        started = time.monotonic()
        lines: queue.Queue[str | None] = queue.Queue()

        with WEB_PROBE.defines_file(defines) as path, open(log_path, "w", encoding="utf-8") as log:
            command = WEB_PROBE.flutter_command() + [
                "run", "-d", args.device, "--debug", "-t", TARGET, f"--dart-define-from-file={path}"]
            if args.device == "chrome":
                command += ["--web-browser-flag=--headless=new"]
            print(f"== ditto_live {pin}, {args.device}, mode {args.mode}{suffix}: "
                  f"flutter run -d {args.device} --debug -t {TARGET}", flush=True)
            process = subprocess.Popen(command, cwd=workdir, stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, bufsize=1, start_new_session=True,
                                       env=WEB_PROBE.child_environment())

            def pump() -> None:
                assert process.stdout is not None
                for raw in process.stdout:
                    lines.put(raw.rstrip("\n"))
                lines.put(None)

            threading.Thread(target=pump, daemon=True).start()

            def emit(line: str) -> None:
                line = WEB_PROBE.redact(line, secret)
                stamp = f"[{time.monotonic() - started:6.1f}s]"
                log.write(f"{stamp} {line}\n")
                if interesting(line):
                    print(f"{stamp} {line}", flush=True)

            def read_until(predicate, timeout: float) -> bool:
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    try:
                        line = lines.get(timeout=0.5)
                    except queue.Empty:
                        continue
                    if line is None:
                        return False
                    emit(line)
                    if predicate(line):
                        return True
                return False

            def send(keys: str) -> None:
                if process.poll() is None and process.stdin is not None:
                    emit(f"(script) sending {keys!r}")
                    try:
                        process.stdin.write(keys)
                        process.stdin.flush()
                    except BrokenPipeError:
                        emit("(script) stdin closed")

            status = "launched"
            try:
                if not read_until(lambda l: "HR: ready" in l or "HR: open failed" in l, 900):
                    status = "never ready"
                else:
                    read_until(lambda l: False, 5)
                    send("R")
                    read_until(lambda l: False, args.observe)
                    send("q")
                    read_until(lambda l: False, 20)
                    status = "observed"
            finally:
                if process.poll() is None:
                    emit("(script) flutter run still running; killing its process group")
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        with contextlib.suppress(ProcessLookupError):
                            os.killpg(process.pid, signal.SIGKILL)
                if args.device == "macos":
                    subprocess.run(["pkill", "-f", f"flutter-fixture-[^/]*/{args.line}/minimal_app/build/macos"],
                                   check=False)
                emit(f"(script) {status}; flutter run exit {process.wait()}")
    finally:
        # Every build in the copy (build/macos or build/web, .dart_tool, the
        # generated platform config) embeds the defines, the license included;
        # delete the whole copy even when the run above raised.
        WEB_PROBE.remove_fixture_copy(workdir)
    print(f"== full output: {log_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
