import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("age", ROOT / "scripts/check-dependency-age.py")
AGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGE)


class DependencyAgeTests(unittest.TestCase):
    cutoff = AGE.timestamp("2026-10-31T17:09:20Z")

    def test_exact_boundary_is_allowed(self):
        AGE.require_mature("release", self.cutoff, self.cutoff)

    def test_one_microsecond_too_young_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "after"):
            AGE.require_mature("release", AGE.timestamp("2026-10-31T17:09:20.000001Z"), self.cutoff)

    def test_timezones_are_normalized(self):
        self.assertEqual(self.cutoff, AGE.timestamp("2026-10-31T12:09:20-05:00"))
        with self.assertRaises(ValueError):
            AGE.timestamp("2026-10-31T17:09:20")

    def test_old_release_with_retargeted_recent_commit_is_rejected(self):
        sha = "a" * 40
        data = [
            {"draft": False, "prerelease": False, "published_at": "2026-10-01T00:00:00Z"},
            {"object": {"type": "commit", "sha": sha}},
            {"commit": {"committer": {"date": "2026-11-03T00:00:00Z"}}},
        ]
        with patch.object(AGE, "fetch_json", side_effect=data), self.assertRaisesRegex(ValueError, "after"):
            AGE.action_check("actions/example", sha, "v1.0.0", self.cutoff)

    def test_commit_must_match_exact_release(self):
        data = [
            {"draft": False, "prerelease": False, "published_at": "2026-10-01T00:00:00Z"},
            {"object": {"type": "commit", "sha": "b" * 40}},
        ]
        with patch.object(AGE, "fetch_json", side_effect=data), self.assertRaisesRegex(ValueError, "does not match"):
            AGE.action_check("actions/example", "a" * 40, "v1.0.0", self.cutoff)

    def test_floating_action_tag_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / ".github/workflows/example.yml"
            path.parent.mkdir(parents=True)
            path.write_text("steps:\n  - uses: actions/checkout@v7\n")
            with patch.object(AGE.subprocess, "check_output", return_value=b".github/workflows/example.yml\0"):
                with self.assertRaisesRegex(ValueError, "full SHA"):
                    AGE.collect(root, self.cutoff)

    def test_npm_artifact_must_match_registry_release(self):
        url = "https://registry.npmjs.org/example/-/example-1.0.0.tgz"
        metadata = {"time": {"1.0.0": "2026-10-01T00:00:00Z"},
                    "versions": {"1.0.0": {"dist": {"tarball": url, "integrity": "sha512-reviewed"}}}}
        with patch.object(AGE, "fetch_json", return_value=metadata):
            AGE.npm_check("example", {"1.0.0": {(url, "sha512-reviewed")}}, self.cutoff)
            for artifact in ((url + "-young", "sha512-reviewed"), (url, "sha512-other")):
                with self.subTest(artifact=artifact), self.assertRaisesRegex(ValueError, "differs"):
                    AGE.npm_check("example", {"1.0.0": {artifact}}, self.cutoff)

    def test_npm_alias_is_rejected(self):
        import json
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "package-lock.json").write_text(json.dumps({"packages": {
                "node_modules/alias": {"name": "actual", "version": "1.0.0",
                    "resolved": "https://registry.npmjs.org/actual/-/actual-1.0.0.tgz", "integrity": "sha512-test"}}}))
            with patch.object(AGE.subprocess, "check_output", return_value=b"package-lock.json\0"):
                with self.assertRaisesRegex(ValueError, "aliases"):
                    AGE.collect(root, self.cutoff)

    def test_maven_versions_with_two_or_four_parts_and_jre_suffix_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "build.gradle.kts"
            path.write_text('classpath("a:b:1.86")\nclasspath("a:c:2.0.6.1")\nclasspath("a:d:33.7.2-jre")')
            with patch.object(AGE.subprocess, "check_output", return_value=b"build.gradle.kts\0"):
                _, _, modules = AGE.collect(root, self.cutoff)
            self.assertEqual(modules, {("a", "b", "1.86"), ("a", "c", "2.0.6.1"), ("a", "d", "33.7.2-jre")})

    def test_wrapper_jar_must_match_official_checksum(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            properties = root / "gradle-wrapper.properties"
            properties.write_text("distributionUrl=https://services.gradle.org/distributions/gradle-9.8.2-bin.zip\ndistributionSha256Sum=expected\n")
            (root / "gradle-wrapper.jar").write_bytes(b"unexpected wrapper")
            release = [{"version": "9.8.2", "buildTime": "20261019162926+0000"}]
            with patch.object(AGE, "fetch_json", return_value=release):
                with patch.object(AGE, "request", side_effect=[io.BytesIO(b"expected"), io.BytesIO(b"0" * 64)]):
                    with self.assertRaisesRegex(ValueError, "wrapper JAR differs"):
                        AGE.gradle_check(properties, self.cutoff)


if __name__ == "__main__":
    unittest.main()
