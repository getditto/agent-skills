#!/usr/bin/env python3
"""Portability and secret-handling checks for the Flutter fixture scripts.

Run: python3 tests/flutter-sdk/scripts/test_fixture_scripts.py

The run-fixture.sh end-to-end cases use a fake `flutter` and a CRLF-printing Python
wrapper, so they need no Flutter or license. They run on macOS and Linux; Windows Git
Bash is not exercised here.
"""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HARNESS = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("use_version", HARNESS / "scripts/use-version.py")
USE_VERSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(USE_VERSION)

POSIX = os.name == "posix"
FAKE_LICENSE = "synthetic-license-value=="


class Pins(unittest.TestCase):
    def test_fvmrc_matches_versions_json(self):
        fvmrc = json.loads((HARNESS / ".fvmrc").read_text())
        versions = json.loads((HARNESS / "versions.json").read_text())
        self.assertEqual(fvmrc["flutter"], versions["flutter"])


class UseVersion(unittest.TestCase):
    def test_dependency_rewrite_stays_on_one_line(self):
        pinned = "dependencies:\n  ditto_live: 5.2.0\n  flutter:\n"
        self.assertEqual(USE_VERSION.DEP_RE.subn(r"\1 5.0.4", pinned),
                         ("dependencies:\n  ditto_live: 5.0.4\n  flutter:\n", 1))
        # A map-form dependency must not be rewritten across the line break.
        mapped = "dependencies:\n  ditto_live:\n    path: ../ditto_live\n"
        self.assertEqual(USE_VERSION.DEP_RE.subn(r"\1 5.0.4", mapped)[1], 0)

    @unittest.skipUnless(POSIX, "POSIX permissions")
    def test_private_root_is_created_owner_only(self):
        with tempfile.TemporaryDirectory() as base:
            root = USE_VERSION.private_root(Path(base))
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
            self.assertEqual(USE_VERSION.private_root(Path(base)), root)

    @unittest.skipUnless(POSIX, "POSIX permissions")
    def test_private_root_refuses_shared_or_symlinked_directories(self):
        with tempfile.TemporaryDirectory() as base:
            root = USE_VERSION.private_root(Path(base))
            root.chmod(0o755)
            with self.assertRaisesRegex(ValueError, "accessible to other users"):
                USE_VERSION.private_root(Path(base))
            shutil.rmtree(root)
            elsewhere = Path(base) / "elsewhere"
            elsewhere.mkdir(mode=0o700)
            root.symlink_to(elsewhere, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                USE_VERSION.private_root(Path(base))

    def test_flutter_command_resolves_through_path(self):
        windows_flutter = r"C:\flutter\bin\flutter.bat"
        with patch.dict(os.environ, {"FLUTTER": "flutter"}), \
                patch.object(USE_VERSION.shutil, "which", return_value=windows_flutter):
            self.assertEqual(USE_VERSION.flutter_command(), [windows_flutter])
        with patch.dict(os.environ, {"FLUTTER": "missing-flutter"}), \
                patch.object(USE_VERSION.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "not an executable"):
                USE_VERSION.flutter_command()
        environment = {key: value for key, value in os.environ.items() if key != "FLUTTER"}
        with patch.dict(os.environ, environment, clear=True), \
                patch.object(USE_VERSION.shutil, "which", side_effect=lambda name: None):
            with self.assertRaisesRegex(ValueError, "fvm is not on PATH"):
                USE_VERSION.flutter_command()


FAKE_FLUTTER = r"""#!/bin/bash
# Records each invocation; for `test`/`drive`, also the defines file and its mode.
log="$FAKE_RECORD"
printf 'argv:' >> "$log"; printf ' [%s]' "$@" >> "$log"; printf '\n' >> "$log"
printf 'pwd: [%s]\n' "$PWD" >> "$log"
for arg in "$@"; do
  case "$arg" in
    --dart-define-from-file=*)
      file="${arg#--dart-define-from-file=}"
      printf 'mode: %s\n' "$(stat -f %Lp "$file" 2>/dev/null || stat -c %a "$file")" >> "$log"
      printf 'defines: %s\n' "$(cat "$file")" >> "$log"
      printf 'file: %s\n' "$file" >> "$log"
      ;;
  esac
done
[[ "${1:-}" == "--version" ]] && echo "Flutter 0.0.0-fake"
exit 0
"""

# Python that ends every output line with CRLF, as Windows Python does under Git Bash.
CRLF_PYTHON = """#!/bin/bash
set -o pipefail
{python} "$@" | sed 's/$/\\r/'
"""


@unittest.skipUnless(POSIX and shutil.which("bash"), "run-fixture.sh needs bash; Windows is not exercised here")
class RunFixture(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="run-fixture-test-"))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.record = self.temp / "record.txt"
        flutter = self.temp / "flutter"
        flutter.write_text(FAKE_FLUTTER)
        python = self.temp / "python-crlf"
        python.write_text(CRLF_PYTHON.format(python=sys.executable))
        for script in (flutter, python):
            script.chmod(0o755)
        (self.temp / "tmp").mkdir()
        (self.temp / "logs").mkdir()
        self.environment = {
            **os.environ, "FLUTTER": str(flutter), "PYTHON": str(python), "FAKE_RECORD": str(self.record),
            "TMPDIR": str(self.temp / "tmp"), "FIXTURE_LOG_DIR": str(self.temp / "logs"),
            "DITTO_OFFLINE_LICENSE": FAKE_LICENSE, "PROBE_DEFAULT_LOGGING": "true",
        }
        self.environment.pop("DITTO_PLATFORM", None)

    def run_fixture(self, *args):
        return subprocess.run(["bash", str(HARNESS / "scripts/run-fixture.sh"), *args],
                              env=self.environment, capture_output=True, text=True, timeout=300)

    def test_license_goes_through_a_private_file_that_is_deleted(self):
        result = self.run_fixture("minimal_app", "macos", "5.2", "integration_test/minimal_app_test.dart")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        record = self.record.read_text()
        argv_lines = [line for line in record.splitlines() if line.startswith("argv:")]
        self.assertTrue(any("[test]" in line for line in argv_lines), record)
        self.assertFalse(any(FAKE_LICENSE in line for line in argv_lines), "license in an argument list")
        self.assertNotIn("\r", record, "a CRLF from Python reached a path or argument")
        self.assertIn("mode: 600", record)
        defines = json.loads(next(line for line in record.splitlines() if line.startswith("defines: "))[9:])
        self.assertEqual(defines, {"DITTO_VERSION": "5.2.0", "DITTO_PLATFORM": "macos",
                                   "DITTO_LICENSE": FAKE_LICENSE, "PROBE_DEFAULT_LOGGING": "true"})
        defines_file = next(line for line in record.splitlines() if line.startswith("file: "))[6:]
        self.assertFalse(Path(defines_file).exists(), "defines file left behind")
        logs = list((self.temp / "logs").glob("run-minimal_app-macos-5.2-minimal_app_test.log"))
        self.assertEqual(len(logs), 1)
        log = logs[0].read_text()
        self.assertIn("DITTO_VERSION=5.2.0 DITTO_PLATFORM=macos PROBE_DEFAULT_LOGGING=true DITTO_LICENSE=<redacted>", log)
        self.assertNotIn(FAKE_LICENSE, log + result.stdout + result.stderr)

    def test_unsupported_web_devices_are_rejected(self):
        for device in ("edge", "web-server"):
            with self.subTest(device=device):
                result = self.run_fixture("minimal_app", device, "5.2", "integration_test/minimal_app_test.dart")
                self.assertEqual(result.returncode, 2)
                self.assertIn("not supported", result.stderr)


if __name__ == "__main__":
    unittest.main()
