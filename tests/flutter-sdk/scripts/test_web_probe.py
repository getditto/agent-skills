#!/usr/bin/env python3
"""Unit checks for scripts/web-probe.py: secret handling, build arguments, the probe
HTTP server and the timing arithmetic. No Flutter, Chrome or license needed.

Run: python3 tests/flutter-sdk/scripts/test_web_probe.py
"""

import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
import urllib.error
import urllib.request

HARNESS = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("web_probe", HARNESS / "scripts/web-probe.py")
WEB_PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WEB_PROBE)

FAKE_LICENSE = "synthetic-license-value=="
POSIX = os.name == "posix"


class ChildEnvironment(unittest.TestCase):
    def test_drops_every_ditto_variable(self):
        environ = {"DITTO_OFFLINE_LICENSE": "x", "DITTO_TOKEN": "y", "PATH": "/bin", "FLUTTER": "flutter"}
        self.assertEqual(WEB_PROBE.child_environment(environ), {"PATH": "/bin", "FLUTTER": "flutter"})


class License(unittest.TestCase):
    def test_env_file_parser_matches_run_fixture(self):
        text = ("# comment\nDITTO_OFFLINE_LICENSE=  \"abc==\"\r\nlower=ignored\n"
                "DITTO_URL='wss://example.invalid'\nDITTO_OFFLINE_LICENSE=second\nNO_VALUE\n")
        self.assertEqual(WEB_PROBE.parse_env_file(text),
                         {"DITTO_OFFLINE_LICENSE": "abc==", "DITTO_URL": "wss://example.invalid"})

    def test_environment_wins_over_env_file(self):
        with tempfile.TemporaryDirectory() as temp:
            env_file = Path(temp) / ".env"
            env_file.write_text("DITTO_OFFLINE_LICENSE=from-file\n")
            self.assertEqual(WEB_PROBE.offline_license({"DITTO_OFFLINE_LICENSE": "from-env"}, env_file),
                             "from-env")
            self.assertEqual(WEB_PROBE.offline_license({}, env_file), "from-file")
            with self.assertRaises(SystemExit):
                WEB_PROBE.offline_license({}, Path(temp) / "missing")

    @unittest.skipUnless(POSIX, "POSIX permissions")
    def test_defines_file_is_private_and_deleted(self):
        with WEB_PROBE.defines_file({"DITTO_LICENSE": FAKE_LICENSE}) as path:
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertIn(FAKE_LICENSE, path.read_text())
        self.assertFalse(path.exists())

    def test_defines_file_is_deleted_on_error(self):
        with self.assertRaises(RuntimeError):
            with WEB_PROBE.defines_file({"DITTO_LICENSE": FAKE_LICENSE}) as path:
                raise RuntimeError
        self.assertFalse(path.exists())

    def test_redact(self):
        self.assertEqual(WEB_PROBE.redact(f"token {FAKE_LICENSE}!", FAKE_LICENSE), "token <redacted>!")
        self.assertEqual(WEB_PROBE.redact("text", ""), "text")


class BuildArgs(unittest.TestCase):
    def test_license_only_travels_in_the_defines_file(self):
        defines = Path("/private/defines.json")
        for variant in ("js", "wasm", "js-app"):
            args = WEB_PROBE.build_args(variant, Path("/out") / variant, defines)
            self.assertIn(f"--dart-define-from-file={defines}", args)
            self.assertFalse(any(arg.startswith("--dart-define=") for arg in args), args)
            self.assertIn("--release", args)
            self.assertIn("--no-web-resources-cdn", args)
            self.assertEqual(args[args.index("-t") + 1], WEB_PROBE.TARGET)

    def test_variants(self):
        defines = Path("/d.json")
        self.assertNotIn("--wasm", WEB_PROBE.build_args("js", Path("/o"), defines))
        self.assertIn("--wasm", WEB_PROBE.build_args("wasm", Path("/o"), defines))
        app = WEB_PROBE.build_args("js-app", Path("/o"), defines)
        self.assertEqual(app[app.index("--base-href") + 1], "/app/")
        self.assertNotIn("--base-href", WEB_PROBE.build_args("js", Path("/o"), defines))

    def test_builds_are_deleted_on_close(self):
        with tempfile.TemporaryDirectory() as temp:
            builds = WEB_PROBE.Builds(Path(temp), Path(temp) / "d.json")
            (builds.root / "js").mkdir(parents=True)
            (builds.root / "js" / "main.dart.js").write_text(FAKE_LICENSE)
            for leftover in (Path(temp) / ".dart_tool" / "flutter_build" / "0123abcd",
                             Path(temp) / "build" / "web"):
                leftover.mkdir(parents=True)
                (leftover / "main.dart.js").write_text(FAKE_LICENSE)
            (Path(temp) / "build" / "macos").mkdir()
            (Path(temp) / "build" / "0123abcd.cache.dill.track.dill").write_text(FAKE_LICENSE)
            builds.close()
            self.assertFalse(builds.root.exists())
            self.assertFalse((Path(temp) / ".dart_tool" / "flutter_build").exists())
            self.assertFalse((Path(temp) / "build" / "web").exists())
            self.assertTrue((Path(temp) / "build" / "macos").exists())
            self.assertEqual(list((Path(temp) / "build").glob("*.cache.dill.track.dill")), [])


class Server(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        (root / "index.html").write_text("<html></html>")
        (root / "assets").mkdir()
        (root / "assets" / "ditto.wasm").write_bytes(b"\0asm")
        self.root = root

    def fetch(self, url):
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                return response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.headers, b""

    def test_root_mount_with_headers_and_wasm_type(self):
        with WEB_PROBE.serve(self.root, headers=WEB_PROBE.COOP_COEP) as url:
            status, headers, body = self.fetch(url + "?mode=smoke")
            self.assertEqual((status, body), (200, b"<html></html>"))
            self.assertEqual(headers.get("Cross-Origin-Opener-Policy"), "same-origin")
            self.assertEqual(headers.get("Cross-Origin-Embedder-Policy"), "require-corp")
            status, headers, _ = self.fetch(url + "assets/ditto.wasm")
            self.assertEqual((status, headers.get("Content-Type")), (200, "application/wasm"))

    def test_subpath_mount_hides_the_site_root(self):
        with WEB_PROBE.serve(self.root, prefix="/app/") as url:
            self.assertTrue(url.endswith("/app/"))
            self.assertEqual(self.fetch(url)[0], 200)
            self.assertEqual(self.fetch(url + "assets/ditto.wasm")[0], 200)
            origin = url[: -len("app/")]
            self.assertEqual(self.fetch(origin + "assets/ditto.wasm")[0], 404)
            self.assertNotIn("Cross-Origin-Opener-Policy", self.fetch(url)[1])

    def test_prefix_must_be_slashed(self):
        with self.assertRaises(ValueError):
            with WEB_PROBE.serve(self.root, prefix="/app"):
                pass


class Transcript(unittest.TestCase):
    transcript = {"status": "done", "lines": [
        "compiler: dart2js", "release: true", "crossOriginIsolated: false",
        "read-back make: Toyota", "select all: items=5000 ms=24 window=100.5-124.5"]}

    def test_transcript_value(self):
        self.assertEqual(WEB_PROBE.transcript_value(self.transcript, "compiler"), "dart2js")
        self.assertIsNone(WEB_PROBE.transcript_value(self.transcript, "missing"))

    def test_parse_window(self):
        value = WEB_PROBE.transcript_value(self.transcript, "select all")
        self.assertEqual(WEB_PROBE.parse_window(value), (5000, 24, 100.5, 124.5))

    def test_expect_smoke(self):
        WEB_PROBE.expect_smoke(self.transcript, "dart2js", isolated=False)
        with self.assertRaises(WEB_PROBE.ProbeFailure):
            WEB_PROBE.expect_smoke(self.transcript, "dart2wasm", isolated=False)
        with self.assertRaises(WEB_PROBE.ProbeFailure):
            WEB_PROBE.expect_smoke({**self.transcript, "status": "timeout"}, "dart2js", isolated=False)


class Timing(unittest.TestCase):
    def test_longest_task_counts_only_overlapping_tasks(self):
        tasks = [[0.0, 300.0], [1000.0, 80.0], [1500.0, 60.0], [3000.0, 500.0]]
        self.assertEqual(WEB_PROBE.longest_task_in(tasks, 1050.0, 1600.0), 80.0)
        self.assertEqual(WEB_PROBE.longest_task_in(tasks, 2000.0, 2500.0), 0.0)
        self.assertEqual(WEB_PROBE.longest_task_in([], 0.0, 1.0), 0.0)

    def test_longest_frame_gap(self):
        frames = [0.0, 16.7, 33.4, 250.0, 266.7, 283.4]
        self.assertAlmostEqual(WEB_PROBE.longest_frame_gap_in(frames, 100.0, 120.0), 216.6)
        self.assertAlmostEqual(WEB_PROBE.longest_frame_gap_in(frames, 255.0, 290.0), 16.7)
        self.assertEqual(WEB_PROBE.longest_frame_gap_in([5.0], 0.0, 10.0), 0.0)


class Probes(unittest.TestCase):
    def test_every_probe_id_has_a_function(self):
        self.assertEqual(sorted(WEB_PROBE.PROBES), sorted([
            "web_reload_persistence", "web_default_build", "web_wasm_build", "web_no_coop_coep",
            "web_csp", "web_base_href", "web_large_result_jank"]))
        self.assertTrue(WEB_PROBE.MANUAL <= set(WEB_PROBE.PROBES))


if __name__ == "__main__":
    unittest.main()
