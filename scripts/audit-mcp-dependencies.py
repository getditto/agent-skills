#!/usr/bin/env python3
"""Audit the same committed MCP lockfile used at startup, without installing code."""

from pathlib import Path
import subprocess

from mcp_snapshot import validate_snapshot


def main():
    snapshot, before = validate_snapshot(Path(__file__).resolve().parents[1])
    print(f"Auditing committed MCP snapshot, before={before}", flush=True)
    subprocess.run(["npm", "audit", "--package-lock-only"], cwd=snapshot, check=True)


if __name__ == "__main__":
    main()
