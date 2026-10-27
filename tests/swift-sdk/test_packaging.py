"""Regression checks for Swift installation archives (stdlib only).

Run: python3 -m unittest discover -s tests/swift-sdk -p test_packaging.py
"""

import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("swift_packager", ROOT / "scripts/package-swift-plugin.py")
PACKAGER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGER)


class SwiftPackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="ditto-packaging-tests-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        cls.first = cls.directory / "first"
        cls.second = cls.directory / "second"
        with contextlib.redirect_stdout(io.StringIO()):
            PACKAGER.build(cls.first)
            PACKAGER.build(cls.second)

    def test_committed_metadata_is_current(self):
        PACKAGER.sync(check=True)

    def test_archives_are_reproducible_and_checksummed(self):
        archives = sorted(self.first.glob("*.zip"))
        self.assertEqual(len(archives), 5)
        checksums = dict(line.split("  ", 1)[::-1]
                         for line in (self.first / "SHA256SUMS").read_text().splitlines())
        self.assertEqual(set(checksums), {path.name for path in archives})
        for path in archives:
            with self.subTest(archive=path.name):
                content = path.read_bytes()
                self.assertEqual(content, (self.second / path.name).read_bytes())
                self.assertEqual(hashlib.sha256(content).hexdigest(), checksums[path.name])

    def test_archives_are_scoped_self_contained_and_safe(self):
        source = ROOT / "skills/swift-sdk"
        for path in self.first.glob("*.zip"):
            with self.subTest(archive=path.name), zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                self.assertEqual(len(names), len(set(names)))
                skills = [name for name in names if name.endswith("/SKILL.md")]
                self.assertEqual(len(skills), 1)
                skill_root = skills[0][:-len("SKILL.md")]
                self.assertTrue(skill_root.endswith("swift-sdk/"))
                for member in archive.infolist():
                    parts = Path(member.filename).parts
                    self.assertFalse(Path(member.filename).is_absolute())
                    self.assertNotIn("..", parts)
                    self.assertFalse(stat.S_ISLNK(member.external_attr >> 16))
                    self.assertFalse(set(parts) & {".git", ".env", "__pycache__"})
                    if member.filename.endswith(".json"):
                        json.loads(archive.read(member))
                for resource in ("scripts/create-swift-app.py", "assets/swiftui-starter/StarterApp.swift"):
                    self.assertEqual(archive.read(skill_root + resource), (source / resource).read_bytes())
                self.assertEqual({name[len(skill_root):] for name in names if name.startswith(skill_root)},
                                 {file.relative_to(source).as_posix() for file in source.rglob("*")
                                  if file.is_file() and not set(file.relative_to(source).parts) &
                                  {"__pycache__", ".git", ".env", ".DS_Store"}
                                  and file.suffix != ".pyc"})
                for name in names:
                    if name.endswith("marketplace.json"):
                        self.assertEqual([entry["name"] for entry in json.loads(archive.read(name))["plugins"]],
                                         ["ditto-swift"])

    def test_package_file_manifest_covers_actual_files(self):
        package = self.first / "ditto-swift-marketplace/plugins/ditto-swift"
        manifest = json.loads((package / "PACKAGE-MANIFEST.json").read_text())
        actual = {file.relative_to(package).as_posix(): hashlib.sha256(file.read_bytes()).hexdigest()
                  for file in package.rglob("*") if file.is_file() and file.name != "PACKAGE-MANIFEST.json"}
        self.assertEqual(manifest["sha256"], actual)
        self.assertEqual(manifest["plugin"], "ditto-swift")

    def test_existing_output_is_preserved(self):
        marker = self.first / "customer-file.txt"
        marker.write_text("keep me")
        with self.assertRaises(ValueError):
            PACKAGER.build(self.first)
        self.assertEqual(marker.read_text(), "keep me")

    def test_archive_rejects_unmaterialized_file_symlink(self):
        folder = self.directory / "symlink-negative"
        folder.mkdir()
        target = self.directory / "outside.txt"
        target.write_text("outside fixture")
        try:
            (folder / "linked.txt").symlink_to(target)
        except (OSError, NotImplementedError):
            self.skipTest("Creating symlinks is unavailable on this platform")
        with self.assertRaises(ValueError):
            PACKAGER.archive(folder, self.directory / "symlink-negative.zip")

    def test_skill_copy_rejects_file_directory_and_dangling_symlinks(self):
        for kind in ("file", "directory", "dangling"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory(dir=self.directory) as temporary:
                root = Path(temporary)
                source = root / "repository/skills/swift-sdk"
                source.mkdir(parents=True)
                (source / "SKILL.md").write_text("Synthetic fixture")
                outside = root / "outside"
                if kind == "file":
                    outside.write_text("Synthetic non-secret outside fixture")
                elif kind == "directory":
                    outside.mkdir()
                    (outside / "fixture.txt").write_text("Synthetic non-secret outside fixture")
                try:
                    (source / "linked-fixture").symlink_to(outside, target_is_directory=kind == "directory")
                except (OSError, NotImplementedError):
                    self.skipTest("Creating symlinks is unavailable on this platform")
                destination = root / "copied-skill"
                with patch.object(PACKAGER, "ROOT", root / "repository"):
                    with self.assertRaises(ValueError):
                        PACKAGER.copy_skill(destination)
                self.assertFalse(destination.exists())

    def test_catalog_update_preserves_other_plugins_and_custom_fields(self):
        with tempfile.TemporaryDirectory(dir=self.directory) as temporary:
            root = Path(temporary)
            catalog = root / "catalog.json"
            catalog.write_text(json.dumps({"name": "custom-marketplace", "metadata": {"custom": True},
                "plugins": [{"name": "ditto-kotlin", "source": "./kotlin"},
                            {"name": "ditto-swift", "source": "./old-swift"}]}))
            new_swift = {"name": "ditto-swift", "source": "./new-swift"}
            with patch.object(PACKAGER, "ROOT", root):
                result = PACKAGER.update_catalog("catalog.json", {"name": "default", "plugins": [new_swift]})
            self.assertEqual(result["plugins"], [{"name": "ditto-kotlin", "source": "./kotlin"}, new_swift])
            self.assertEqual(result["name"], "custom-marketplace")
            self.assertEqual(result["metadata"], {"custom": True})

    def test_metadata_check_detects_stale_files_without_writing(self):
        with tempfile.TemporaryDirectory(dir=self.directory) as temporary:
            root = Path(temporary)
            file = root / "plugin.json"
            file.write_text("{}")
            with patch.object(PACKAGER, "ROOT", root), patch.object(PACKAGER, "manifests", return_value={"plugin.json": {"name": "ditto-swift"}}):
                with self.assertRaises(ValueError):
                    PACKAGER.sync(check=True)
            self.assertEqual(file.read_text(), "{}")


if __name__ == "__main__":
    unittest.main()
