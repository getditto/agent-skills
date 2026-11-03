#!/usr/bin/env python3
"""Launch the reviewed MCP graph without reusing local/global/npx installations."""

from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

from mcp_snapshot import validate_snapshot

ROOT = Path(__file__).resolve().parents[1]


def run_child(command, **kwargs):
    child = subprocess.Popen(command, **kwargs)
    previous = {}
    try:
        def forward(signum, _frame):
            if child.poll() is None:
                child.send_signal(signum)
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, forward)
        return child.wait()
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
        if child.poll() is None:
            child.terminate()
            child.wait()


def main(args=None):
    args = sys.argv[1:] if args is None else args
    if len(args) != 1 or not args[0].startswith("https://"):
        raise ValueError("Expected one HTTPS MCP endpoint")
    snapshot, _ = validate_snapshot(ROOT)
    # Each server owns its installation: simultaneous startup cannot remove another
    # server's node_modules. npm's content cache is checked against lock integrity.
    with tempfile.TemporaryDirectory(prefix="ditto-mcp-") as directory:
        for name in ("package.json", "package-lock.json", ".npmrc"):
            shutil.copyfile(snapshot / name, Path(directory) / name)
        status = run_child(["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"],
                           cwd=directory, stdout=sys.stderr)
        if status:
            return status
        entry = Path(directory) / "node_modules/mcp-remote/dist/proxy.js"
        return run_child(["node", str(entry), args[0]], cwd=directory)


if __name__ == "__main__":
    raise SystemExit(main())
