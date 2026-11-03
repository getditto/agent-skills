"""Fast runner regressions; no SDK, credentials, or Apple toolchain required."""

import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "find_test_bundle", ROOT / "scripts/lib/find-test-bundle.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RunnerTests(unittest.TestCase):
    def test_published_data_streams_sample_is_the_executed_source(self):
        guide = (ROOT.parents[1] / "skills/swift-sdk/references/data-streams.md").read_text()
        programs = re.findall(r"```swift\n(.*?)\n```", guide, re.S)
        source = (ROOT / "Sources/UIPatterns/StreamInbox.swift").read_text().splitlines()
        self.assertEqual(source[0], "#if DITTO_DATA_STREAMS")
        self.assertEqual(source[-1], "#endif")
        self.assertIn("\n".join(source[1:-1]), programs)

    def make_bundle(self, root, name):
        binary = root / f"{name}.xctest/Contents/MacOS/{name}"
        binary.parent.mkdir(parents=True)
        binary.touch()
        return binary

    def test_both_swiftpm_bundle_names(self):
        for name in ("SwiftSDKSkillTests", "DittoSwiftSkillTestsPackageTests"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary = self.make_bundle(root, name)
                self.assertEqual(MODULE.find_bundle(root), binary)

    def test_missing_bundle_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "found 0"):
                MODULE.find_bundle(Path(directory))

    def test_ambiguous_products_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_bundle(root, "First")
            self.make_bundle(root, "Second")
            with self.assertRaisesRegex(ValueError, "found 2"):
                MODULE.find_bundle(root)

    def test_platform_runner_starts_from_a_clean_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "scripts", root / "scripts")
            bin_directory = root / "bin"
            bin_directory.mkdir()
            xcodebuild = bin_directory / "xcodebuild"
            xcodebuild.write_text(
                '#!/bin/bash\nset -eu\n'
                'test -d .build\n'
                'printf "%s\\n" "$*" >> calls.txt\n',
                encoding="utf-8",
            )
            xcodebuild.chmod(0o755)
            result = subprocess.run(
                ["bash", str(root / "scripts/build-platforms.sh"), "5.1.0"],
                env={**os.environ, "PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}"},
                text=True, capture_output=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = (root / "calls.txt").read_text().splitlines()
            self.assertEqual(len(calls), 4)
            self.assertTrue(all("ARCHS=arm64" in call for call in calls))
            self.assertFalse((root / ".build.lock").exists())


if __name__ == "__main__":
    unittest.main()
