"""Application generation resolves stable releases independently of the knowledge baseline."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("starter", ROOT / "skills/swift-sdk/scripts/create-swift-app.py")
starter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(starter)


class VersionSelectionTests(unittest.TestCase):
    def run_default_cli(self, temporary, tags, git_exit=0):
        directory = Path(temporary)
        fake_bin = directory / "bin"
        fake_bin.mkdir()
        invocation = directory / "git-arguments.json"
        fake_git = fake_bin / "git"
        fake_git.write_text(
            f"#!{sys.executable}\n"
            "import json, pathlib, sys\n"
            f"pathlib.Path({str(invocation)!r}).write_text(json.dumps(sys.argv[1:]))\n"
            f"sys.stdout.write({tags!r})\n"
            f"sys.exit({git_exit})\n"
        )
        fake_git.chmod(0o755)
        destination = directory / "Notes"
        result = subprocess.run(
            [sys.executable, str(Path(starter.__file__)), str(destination), "--name", "Notes"],
            env={**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ.get("PATH", "")},
            capture_output=True, text=True, timeout=10,
        )
        self.assertTrue(invocation.exists(), "Default CLI must look up SwiftPM release tags")
        self.assertEqual(json.loads(invocation.read_text()),
                         ["ls-remote", "--tags", "--refs", starter.PACKAGE_URL])
        return result, destination

    def test_cli_default_uses_latest_stable_release(self):
        tags = "\n".join(f"hash\trefs/tags/{v}" for v in
                         ["5.2.0", "5.9.0", "5.10.0", "6.0.0-rc.1", "6.0.0-dev.1"])
        with tempfile.TemporaryDirectory() as temporary:
            result, destination = self.run_default_cli(temporary, tags)
            self.assertEqual(result.returncode, 0, result.stderr)
            project = (destination / "Notes.xcodeproj/project.pbxproj").read_text()
            self.assertIn('"version" = "5.10.0"', project)
            self.assertIn("Ditto 5.10.0", result.stdout)

    def test_cli_default_lookup_failure_creates_no_project(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, destination = self.run_default_cli(temporary, "", git_exit=17)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Cannot generate project", result.stderr)
            self.assertFalse(destination.exists(), "Failed lookup must not silently generate a stale pin")

    def test_latest_excludes_prereleases_and_sorts_numerically(self):
        tags = "\n".join(f"hash\trefs/tags/{v}" for v in
                         ["5.2.0", "5.9.0", "5.10.0", "6.0.0-rc.1", "6.0.0-dev.1"])
        with patch.object(starter.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, tags)):
            self.assertEqual(starter.latest_version(), "5.10.0")

    def test_lookup_failure_does_not_fall_back_to_baseline(self):
        with patch.object(starter.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                starter.latest_version()
        with patch.object(starter.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "")):
            with self.assertRaises(ValueError):
                starter.latest_version()

    def test_explicit_newer_pin_generates_project_and_retains_architecture(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "Notes"
            starter.generate(destination, "Notes", "com.example.notes", "5.10.0")
            project = (destination / "Notes.xcodeproj/project.pbxproj").read_text()
            self.assertIn('"version" = "5.10.0"', project)
            self.assertIn('"ARCHS" = "arm64"', project)
            with self.assertRaises(ValueError):
                starter.generate(destination, "Notes", "com.example.notes", "5.10.0")

    def test_cli_explicit_pin_needs_no_network(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(["python3", str(Path(starter.__file__)),
                                     str(Path(temporary) / "Notes"), "--sdk-version", "5.2.0"],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Ditto 5.2.0", result.stdout)

    def test_rejects_nonrelease_version(self):
        for version in ["latest", "5.2.0-rc.1", "5.2", "05.2.0", "5.2.0;echo"]:
            with self.assertRaises(ValueError):
                starter.release_version(version)


if __name__ == "__main__":
    unittest.main()
