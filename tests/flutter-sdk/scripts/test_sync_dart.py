#!/usr/bin/env python3
"""Tests that scripts/sync-snippets.py handles Dart and platform-config sources."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("sync_snippets", ROOT / "scripts/sync-snippets.py")
snippets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snippets)

BLOCK = "<!-- snippet: {name} -->\n<!-- /snippet -->\n"


def marked(name, code, prefix="// ", suffix=""):
    return f"{prefix}snippet:" f"start {name}{suffix}\n{code}\n{prefix}snippet:" f"end {name}{suffix}\n"


class SyncDart(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sync-dart-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "skills/probe").mkdir(parents=True)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def doc(self, name):
        return self.write("skills/probe/SKILL.md", "# Probe\n\n" + BLOCK.format(name=name))

    def test_dart_region_syncs_into_dart_fence(self):
        self.write("tests/flutter-sdk/lib/main.dart", marked("flutter-main", "void main() {}"))
        doc = self.doc("flutter-main")
        snippets.sync(self.root, check=False)
        self.assertIn("```dart\nvoid main() {}\n```", doc.read_text())

    def test_check_fails_on_one_byte_drift(self):
        self.write("tests/flutter-sdk/lib/main.dart", marked("flutter-main", "void main() {}"))
        doc = self.doc("flutter-main")
        snippets.sync(self.root, check=False)
        self.assertEqual(snippets.sync(self.root, check=True)[0], [])
        doc.write_text(doc.read_text().replace("main()", "mainn()"))
        self.assertEqual(snippets.sync(self.root, check=True)[0], ["skills/probe/SKILL.md"])

    def test_plist_region_syncs_as_xml(self):
        plist = "<dict>\n  <key>NSBluetoothAlwaysUsageDescription</key>\n</dict>"
        self.write("tests/flutter-sdk/ios/Info.plist", marked("flutter-info-plist", plist, "<!-- ", " -->"))
        self.write("tests/flutter-sdk/macos/Release.entitlements", marked("flutter-entitlements", plist, "<!-- ", " -->"))
        self.write("tests/flutter-sdk/android/build.gradle", marked("flutter-gradle", "plugins {}"))
        doc = self.write(
            "skills/probe/SKILL.md",
            "# Probe\n\n" + BLOCK.format(name="flutter-info-plist")
            + BLOCK.format(name="flutter-entitlements") + BLOCK.format(name="flutter-gradle"),
        )
        snippets.sync(self.root, check=False)
        text = doc.read_text()
        self.assertEqual(text.count("```xml\n"), 2)
        self.assertIn("```groovy\nplugins {}\n```", text)
        self.assertIn("NSBluetoothAlwaysUsageDescription", text)

    def test_podfile_region_syncs_as_ruby(self):
        self.write("tests/flutter-sdk/ios/Podfile", marked("flutter-podfile", "platform :ios, '15.0'", "# "))
        doc = self.doc("flutter-podfile")
        snippets.sync(self.root, check=False)
        self.assertIn("```ruby\nplatform :ios, '15.0'\n```", doc.read_text())

    def test_tool_output_directories_are_skipped(self):
        self.write("tests/flutter-sdk/.dart_tool/x.dart", marked("stray", "void a() {}"))
        self.write("tests/flutter-sdk/ios/Pods/y.plist", marked("stray2", "<a/>", "<!-- ", " -->"))
        self.write("tests/flutter-sdk/macos/Flutter/ephemeral/z.dart", marked("stray3", "void b() {}"))
        self.assertEqual(snippets.collect_snippets(self.root), {})


if __name__ == "__main__":
    unittest.main()
