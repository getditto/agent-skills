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
import re
from pathlib import Path
import shutil
import socket
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

    def test_every_fixture_pins_the_versions_json_flutter_lints(self):
        pin = json.loads((HARNESS / "versions.json").read_text())["flutter_lints"]
        pubspecs = sorted(HARNESS.glob("*/pubspec.yaml"))
        self.assertGreaterEqual({p.parent.name for p in pubspecs}, {"minimal_app", "snippet_check", "v4_app"})
        for pubspec in pubspecs:
            with self.subTest(fixture=pubspec.parent.name):
                pins = re.findall(r"^  flutter_lints:[ \t]*(\S+)[ \t]*$", pubspec.read_text(), re.M)
                self.assertEqual(pins, [pin], f"{pubspec}: flutter_lints must be exactly {pin} (versions.json)")


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
printf 'env-ditto: [%s]\n' "$(env | grep -o '^DITTO_[A-Za-z0-9_]*' | sort | tr '\n' ' ')" >> "$log"
for arg in "$@"; do
  case "$arg" in
    --dart-define-from-file=*)
      file="${arg#--dart-define-from-file=}"
      # Python, not stat(1): BSD and GNU stat flags differ.
      printf 'mode: %s\n' "$("$FAKE_PYTHON" -c 'import os, sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$file")" >> "$log"
      printf 'defines: %s\n' "$(cat "$file")" >> "$log"
      printf 'file: %s\n' "$file" >> "$log"
      ;;
  esac
done
[[ "${1:-}" == "--version" ]] && echo "Flutter 0.0.0-fake"
# Stand-ins for the web build output a real flutter leaves in the fixture copy.
if [[ "${1:-}" == "pub" ]]; then
  mkdir -p .dart_tool/flutter_build/0123abcd build/web
  echo "synthetic" > .dart_tool/flutter_build/0123abcd/main.dart.js
  echo "synthetic" > build/web/main.dart.js
  echo "synthetic" > build/0123abcd.cache.dill.track.dill
fi
# FAKE_TIMEOUT_ONCE=<marker>: the first `test` run prints $FAKE_TIMEOUT_OUTPUT and
# exits 124, as `timeout` would.
if [[ "${1:-}" == "test" && -n "${FAKE_TIMEOUT_ONCE:-}" && ! -e "$FAKE_TIMEOUT_ONCE" ]]; then
  : > "$FAKE_TIMEOUT_ONCE"
  printf '%s\n' "${FAKE_TIMEOUT_OUTPUT:-}"
  exit 124
fi
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
            "FAKE_PYTHON": sys.executable,
            "TMPDIR": str(self.temp / "tmp"), "FIXTURE_LOG_DIR": str(self.temp / "logs"),
            "DITTO_OFFLINE_LICENSE": FAKE_LICENSE, "PROBE_DEFAULT_LOGGING": "true",
        }
        self.environment.pop("DITTO_PLATFORM", None)

    def run_fixture(self, *args, bash="bash", environment=None):
        return subprocess.run([bash, str(HARNESS / "scripts/run-fixture.sh"), *args],
                              env=environment or self.environment, capture_output=True, text=True, timeout=300)

    def test_runs_without_a_timeout_command(self):
        # A PATH with every tool the script needs except `timeout`. /bin/bash is
        # bash 3.2 on macOS, where an empty "${array[@]}" fails under `set -u`.
        tools = self.temp / "path"
        tools.mkdir()
        for name in ("sed", "tr", "grep", "mktemp", "rm", "date", "tee", "dirname", "cat", "env", "seq", "tail"):
            found = shutil.which(name)
            self.assertIsNotNone(found, name)
            (tools / name).symlink_to(found)
        self.assertIsNone(shutil.which("timeout", path=str(tools)))
        bash = "/bin/bash" if Path("/bin/bash").exists() else shutil.which("bash")
        result = self.run_fixture("minimal_app", "macos", "5.2", "integration_test/minimal_app_test.dart",
                                  bash=bash, environment={**self.environment, "PATH": str(tools)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no `timeout` command", result.stderr)
        self.assertIn("[test]", self.record.read_text())

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

    def test_migration_phase_is_a_define_keeps_the_app_and_names_the_log(self):
        result = self.run_fixture("minimal_app", "macos", "5.1", "integration_test/migration/migrate_default_dir_test.dart",
                                  environment={**self.environment, "MIGRATION_PHASE": "write"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        record = self.record.read_text()
        defines = json.loads(next(line for line in record.splitlines() if line.startswith("defines: "))[9:])
        self.assertEqual(defines["MIGRATION_PHASE"], "write")
        self.assertTrue(any("--no-uninstall" in line for line in record.splitlines() if line.startswith("argv:")),
                        record)
        logs = list((self.temp / "logs").glob("run-minimal_app-macos-5.1-migration_migrate_default_dir_test-write.log"))
        self.assertEqual(len(logs), 1, list((self.temp / "logs").iterdir()))
        self.assertIn("MIGRATION_PHASE=write", logs[0].read_text())

    def run_timing_out_once(self, output, retries):
        marker = self.temp / "timed-out-once"
        marker.unlink(missing_ok=True)
        self.record.unlink(missing_ok=True)
        environment = {**self.environment, "FAKE_TIMEOUT_ONCE": str(marker), "FAKE_TIMEOUT_OUTPUT": output,
                       "GITHUB_ACTIONS": "true"}
        if retries:
            environment["FIXTURE_RETRIES"] = retries
        result = self.run_fixture("minimal_app", "macos", "5.2", "integration_test/minimal_app_test.dart",
                                  environment=environment)
        runs = sum("[test]" in line for line in self.record.read_text().splitlines())
        return result, runs

    def test_retries_only_the_known_ios_simulator_timeouts(self):
        for output in ("Error waiting for a debug connection: The log reader failed unexpectedly",
                       "Running Xcode build...\nXcode build done.                    114.2s"):
            with self.subTest(output=output):
                result, runs = self.run_timing_out_once(output, "")
                self.assertEqual((result.returncode, runs), (124, 1), result.stdout + result.stderr)
                result, runs = self.run_timing_out_once(output, "1")
                self.assertEqual((result.returncode, runs), (0, 2), result.stdout + result.stderr)
                self.assertIn("::warning::", result.stdout)
                self.assertIn("with the known iOS Simulator failure", result.stdout)
        # A timeout after tests started, or with any other output, is never retried.
        for output in ("Xcode build done.\n00:01 +1: some test", "some other hang"):
            with self.subTest(output=output):
                result, runs = self.run_timing_out_once(output, "1")
                self.assertEqual((result.returncode, runs), (124, 1), result.stdout + result.stderr)
                self.assertNotIn("retrying", result.stdout)

    def test_flutter_sees_no_ditto_variables(self):
        environment = {**self.environment, "DITTO_TOKEN": "synthetic-token", "DITTO_URL": "https://example.invalid",
                       "DITTO_DATABASE_ID": "REPLACE_ME", "DITTO_PLATFORM": "macos"}
        result = self.run_fixture("minimal_app", "macos", "5.2", "integration_test/minimal_app_test.dart",
                                  environment=environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        seen = [line for line in self.record.read_text().splitlines() if line.startswith("env-ditto:")]
        self.assertTrue(seen)
        # Every flutter invocation (pub get, --version, test) ran without DITTO_*.
        self.assertTrue(all(line == "env-ditto: []" for line in seen), seen)
        defines = json.loads(next(line for line in self.record.read_text().splitlines()
                                  if line.startswith("defines: "))[9:])
        self.assertEqual(defines["DITTO_LICENSE"], FAKE_LICENSE)

    def test_v4_app_runs_on_the_4_14_line_only(self):
        result = self.run_fixture("v4_app", "macos", "5.2", "integration_test/v4_test.dart")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("4.14 line only", result.stdout + result.stderr)

    def test_unsupported_web_devices_are_rejected(self):
        for device in ("edge", "web-server"):
            with self.subTest(device=device):
                result = self.run_fixture("minimal_app", device, "5.2", "integration_test/minimal_app_test.dart")
                self.assertEqual(result.returncode, 2)
                self.assertIn("not supported", result.stderr)

    def test_chrome_fails_early_when_chromedriver_does_not_come_up(self):
        with socket.socket() as probe:
            if probe.connect_ex(("127.0.0.1", 4444)) == 0:
                self.skipTest("something already listens on 127.0.0.1:4444")
        broken = self.temp / "chromedriver"
        broken.write_text("#!/bin/bash\nexit 1\n")
        broken.chmod(0o755)
        result = self.run_fixture("minimal_app", "chrome", "5.2", "integration_test/web/web_all_test.dart",
                                  environment={**self.environment, "CHROMEDRIVER": str(broken)})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ChromeDriver did not come up on 127.0.0.1:4444", result.stderr)
        record = self.record.read_text()
        self.assertNotIn("[drive]", record)
        # The EXIT trap deletes the chrome leg's web build output in the fixture copy.
        workdir = Path(next(line for line in record.splitlines() if line.startswith("pwd: "))[6:-1])
        self.assertTrue(workdir.is_dir(), workdir)
        self.assertFalse((workdir / ".dart_tool" / "flutter_build").exists())
        self.assertFalse((workdir / "build" / "web").exists())
        self.assertEqual(list((workdir / "build").glob("*.cache.dill.track.dill")), [])

    def test_native_runs_leave_the_fixture_build_alone(self):
        result = self.run_fixture("minimal_app", "macos", "5.2", "integration_test/minimal_app_test.dart")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        workdir = Path(next(line for line in self.record.read_text().splitlines()
                            if line.startswith("pwd: "))[6:-1])
        self.assertTrue((workdir / "build" / "web").exists())


if __name__ == "__main__":
    unittest.main()
