#!/usr/bin/env python3
"""ditto-flutter installation archives ship flutter-sdk together with native-app-config.

Run: python3 tests/flutter-sdk/scripts/test_packaging.py
"""

import contextlib
import importlib.util
import io
from pathlib import Path, PurePosixPath
import posixpath
import re
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("flutter_packager", ROOT / "scripts/package-sdk-plugin.py")
PACKAGER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGER)

SHIPPED = ("flutter-sdk", "native-app-config")
UPLOADS = {f"{name}.zip": name for name in SHIPPED}


class FlutterPackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="ditto-flutter-packaging-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.output = Path(cls.temporary.name) / "out"
        PACKAGER.configure("ditto-flutter")
        cls.addClassCleanup(PACKAGER.configure, "ditto-swift")
        with contextlib.redirect_stdout(io.StringIO()):
            PACKAGER.build(cls.output)

    def setUp(self):
        PACKAGER.configure("ditto-flutter")

    def archives(self):
        found = sorted(self.output.glob("*.zip"))
        self.assertEqual({path.name for path in found}, {
            "ditto-flutter-marketplace.zip", "ditto-flutter-plugin.zip",
            "ditto-flutter-antigravity.zip", "ditto-flutter-gemini.zip", *UPLOADS})
        return found

    def test_every_plugin_archive_ships_native_app_config(self):
        for path in self.archives():
            if path.name in UPLOADS:
                continue
            with self.subTest(archive=path.name), zipfile.ZipFile(path) as archive:
                skills = sorted(name for name in archive.namelist() if name.endswith("/SKILL.md"))
                self.assertEqual([PurePosixPath(name).parent.name for name in skills], list(SHIPPED))
                self.assertTrue(any(name.endswith("skills/native-app-config/SKILL.md") for name in skills))

    def test_upload_archives_hold_exactly_one_skill(self):
        for path in self.archives():
            if path.name not in UPLOADS:
                continue
            with self.subTest(archive=path.name), zipfile.ZipFile(path) as archive:
                skills = [name for name in archive.namelist() if name.endswith("/SKILL.md")]
                self.assertEqual(skills, [f"{UPLOADS[path.name]}/SKILL.md"])

    def test_links_into_native_app_config_resolve_inside_the_archive(self):
        checked = 0
        with zipfile.ZipFile(self.output / "ditto-flutter-plugin.zip") as archive:
            names = set(archive.namelist())
            for name in names:
                if "/skills/flutter-sdk/" not in name or not name.endswith(".md"):
                    continue
                for link in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", archive.read(name).decode()):
                    if "native-app-config" not in link:
                        continue
                    self.assertFalse(link.startswith("http"), f"{name}: {link} was rewritten to a URL")
                    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), link))
                    self.assertTrue(resolved in names or any(n.startswith(resolved + "/") for n in names),
                                    f"{name}: {link} does not resolve inside the archive")
                    checked += 1
        if checked == 0:
            self.skipTest("flutter-sdk has no links into native-app-config yet")

    def test_copy_keeps_sibling_links_and_rewrites_repository_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in SHIPPED:
                (root / "skills" / name).mkdir(parents=True)
            (root / "skills/native-app-config/SKILL.md").write_text("native\n")
            (root / "tests").mkdir()
            (root / "tests/README.md").write_text("tests\n")
            (root / "skills/flutter-sdk/SKILL.md").write_text(
                "[apple](../native-app-config/SKILL.md#apple) [harness](../../tests/README.md)\n")
            destination = root / "out"
            with patch.object(PACKAGER, "ROOT", root):
                PACKAGER.copy_skill(destination, "flutter-sdk")
            self.assertEqual((destination / "SKILL.md").read_text(),
                             "[apple](../native-app-config/SKILL.md#apple) "
                             "[harness](https://github.com/getditto/agent-skills/blob/main/tests/README.md)\n")

    def test_scope_must_match_the_wrapper(self):
        with patch.dict(PACKAGER.META, {"skills": ["flutter-sdk"]}):
            with self.assertRaisesRegex(ValueError, "native-app-config"):
                PACKAGER.check_scope()
        PACKAGER.check_scope()


if __name__ == "__main__":
    unittest.main()
