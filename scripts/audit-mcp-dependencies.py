#!/usr/bin/env python3
"""Audit the configured MCP bridge snapshots without installing or executing code."""

import json
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    servers = json.loads((root / ".mcp.json").read_text())["mcpServers"].values()
    snapshots = set()
    for server in servers:
        args = server["args"]
        package = next(arg for arg in args if arg.startswith("mcp-remote@"))
        before = next(arg for arg in args if arg.startswith("--before="))
        snapshots.add((package.split("@", 1)[1], before))
    for version, before in sorted(snapshots):
        with tempfile.TemporaryDirectory(prefix="mcp-dependency-audit-") as directory:
            manifest = {"private": True, "dependencies": {"mcp-remote": version}}
            (Path(directory) / "package.json").write_text(json.dumps(manifest))
            print(f"Auditing mcp-remote {version}, {before}", flush=True)
            subprocess.run(["npm", "install", "--package-lock-only", "--ignore-scripts", before],
                           cwd=directory, check=True)
            subprocess.run(["npm", "audit", "--package-lock-only"], cwd=directory, check=True)


if __name__ == "__main__":
    main()
