"""Shared validation for the committed MCP bridge installation and launch contract."""

import json
from pathlib import Path
import re


def validate_snapshot(root):
    directory = Path(root) / "tools/mcp-remote"
    manifest = json.loads((directory / "package.json").read_text())
    lock = json.loads((directory / "package-lock.json").read_text())
    if (not manifest.get("name") or not manifest.get("version")
            or any(lock.get(key) != manifest[key] or lock["packages"][""].get(key) != manifest[key]
                   for key in ("name", "version"))):
        raise ValueError("MCP snapshot requires a consistent explicit name and version for relocation")
    dependencies = manifest["dependencies"]
    version = dependencies.get("mcp-remote", "")
    if set(dependencies) != {"mcp-remote"} or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("MCP bridge must use one exact stable version")
    if lock["packages"][""]["dependencies"] != dependencies:
        raise ValueError("MCP manifest and lockfile disagree")
    if lock["packages"]["node_modules/mcp-remote"]["version"] != version:
        raise ValueError("MCP lockfile has the wrong bridge version")
    # No duplicate settings or npm flags: all callers use this one snapshot.
    lines = (directory / ".npmrc").read_text().splitlines()
    before = [line.removeprefix("before=") for line in lines if line.startswith("before=")]
    if len(before) != 1 or lines != ["before=" + before[0], "ignore-scripts=true"]:
        raise ValueError("MCP snapshot requires exactly one before cutoff and ignore-scripts=true")
    config = json.loads((Path(root) / ".mcp.json").read_text())
    for server in config["mcpServers"].values():
        args = server.get("args", [])
        if (server.get("command") != "python3" or len(args) != 2
                or args[0] != "scripts/run-mcp-remote.py" or not args[1].startswith("https://")):
            raise ValueError("MCP servers must use the locked launcher with one HTTPS endpoint")
    return directory, before[0]
