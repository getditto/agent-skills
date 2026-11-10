import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from mcp_snapshot import validate_snapshot

SPEC = importlib.util.spec_from_file_location("launcher", ROOT / "scripts/run-mcp-remote.py")
LAUNCHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LAUNCHER)


class McpSnapshotTests(unittest.TestCase):
    def snapshot(self, directory):
        root = Path(directory)
        shutil.copytree(ROOT / "tools/mcp-remote", root / "tools/mcp-remote")
        shutil.copyfile(ROOT / ".mcp.json", root / ".mcp.json")
        return root

    def test_duplicate_cutoffs_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.snapshot(directory)
            path = root / "tools/mcp-remote/.npmrc"
            path.write_text(path.read_text() + "before=2026-11-03T17:09:20Z\n")
            with self.assertRaisesRegex(ValueError, "exactly one"):
                validate_snapshot(root)

    def test_legacy_npx_config_cannot_bypass_locked_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.snapshot(directory)
            (root / ".mcp.json").write_text(json.dumps({"mcpServers": {"test": {
                "command": "npx", "args": ["--before=2026-10-31T17:09:20Z", "--before=2026-11-03T17:09:20Z", "mcp-remote@0.15.2"]}}}))
            with self.assertRaisesRegex(ValueError, "locked launcher"):
                validate_snapshot(root)

    def test_manifest_and_lock_must_match(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.snapshot(directory)
            path = root / "tools/mcp-remote/package.json"
            manifest = json.loads(path.read_text())
            manifest["dependencies"]["mcp-remote"] = "0.15.1"
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "disagree"):
                validate_snapshot(root)

    def test_snapshot_has_stable_identity_when_relocated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.snapshot(directory)
            validate_snapshot(root)
            path = root / "tools/mcp-remote/package.json"
            manifest = json.loads(path.read_text())
            del manifest["name"]
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "relocation"):
                validate_snapshot(root)

    def test_launch_uses_fresh_locked_install_and_protocol_only_stdout(self):
        directories = []
        def child(command, **kwargs):
            directory = Path(kwargs["cwd"])
            self.assertTrue(directory.exists())
            if command[0] == "npm":
                directories.append(directory)
                self.assertEqual(command, ["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"])
                self.assertIs(kwargs["stdout"], sys.stderr)
                self.assertEqual((directory / "package-lock.json").read_bytes(),
                                 (ROOT / "tools/mcp-remote/package-lock.json").read_bytes())
                self.assertFalse((directory / "node_modules").exists())
            else:
                self.assertEqual(command, ["node", str(directory / "node_modules/mcp-remote/dist/proxy.js"), "https://example.invalid/mcp"])
                self.assertNotIn("stdout", kwargs)
            return 0
        with patch.object(LAUNCHER, "run_child", side_effect=child):
            for _ in range(2):
                self.assertEqual(LAUNCHER.main(["https://example.invalid/mcp"]), 0)
        self.assertNotEqual(*directories)
        self.assertTrue(all(not path.exists() for path in directories))

    def test_install_failure_never_launches_bridge(self):
        with patch.object(LAUNCHER, "run_child", return_value=42) as child:
            self.assertEqual(LAUNCHER.main(["https://example.invalid/mcp"]), 42)
        self.assertEqual(child.call_count, 1)


if __name__ == "__main__":
    unittest.main()
