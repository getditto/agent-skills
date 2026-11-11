#!/usr/bin/env python3
"""Tests for scripts/sync-snippets.py: copying tested code from tests/ into skills/."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("sync_snippets", ROOT / "scripts/sync-snippets.py")
snippets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snippets)

BLOCK = "<!-- snippet: {name} -->\n<!-- /snippet -->\n"


class SyncSnippets(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="snippets-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "skills/probe").mkdir(parents=True)
        (self.root / "tests/probe").mkdir(parents=True)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def doc(self, body):
        return self.write("skills/probe/SKILL.md", f"# Probe\n\n{body}")

    def test_injects_regions_joined_and_dedented(self):
        self.write(
            "tests/probe/Main.kt",
            "import a.B\n// snippet:start demo\nimport a.C\n// snippet:end demo\n"
            "class Main {\n    // snippet:start demo\n    fun f() = 1\n    // snippet:end demo\n"
            "    fun hidden() = 2\n// snippet:start demo\n}\n// snippet:end demo\n",
        )
        doc = self.doc(BLOCK.format(name="demo"))
        stale, used = snippets.sync(self.root, check=False)
        self.assertEqual((stale, used), (["skills/probe/SKILL.md"], {"demo"}))
        text = doc.read_text()
        self.assertIn("```kotlin\nimport a.C\n\nfun f() = 1\n}\n```", text)
        self.assertIn("Generated from tests/probe/Main.kt", text)
        self.assertNotIn("hidden", text)
        self.assertNotIn("snippet:start", text)
        # A second run is a no-op, and --check agrees.
        self.assertEqual(snippets.sync(self.root, check=False)[0], [])
        self.assertEqual(snippets.sync(self.root, check=True)[0], [])

    def test_check_reports_drift_without_writing(self):
        source = self.write("tests/probe/a.ts", "// snippet:start demo\nconst a = 1;\n// snippet:end demo\n")
        doc = self.doc(BLOCK.format(name="demo"))
        snippets.sync(self.root, check=False)
        source.write_text("// snippet:start demo\nconst a = 2;\n// snippet:end demo\n")
        before = doc.read_text()
        self.assertEqual(snippets.sync(self.root, check=True)[0], ["skills/probe/SKILL.md"])
        self.assertEqual(doc.read_text(), before)

    def test_whole_file(self):
        self.write("tests/probe/settings.gradle.kts", 'rootProject.name = "x"\n')
        doc = self.doc("<!-- snippet-file: tests/probe/settings.gradle.kts -->\n<!-- /snippet -->\n")
        snippets.sync(self.root, check=False)
        self.assertIn('```kotlin\nrootProject.name = "x"\n```', doc.read_text())

    def test_whole_file_must_be_under_tests(self):
        self.write("docs/x.md", "# x\n")
        self.doc("<!-- snippet-file: docs/x.md -->\n<!-- /snippet -->\n")
        with self.assertRaisesRegex(snippets.SnippetError, "must be under tests/"):
            snippets.sync(self.root, check=False)

    def test_code_containing_a_fence_gets_a_longer_fence(self):
        self.write("tests/probe/a.md", "<!-- snippet:start demo -->\n```js\nx\n```\n<!-- snippet:end demo -->\n")
        doc = self.doc(BLOCK.format(name="demo"))
        snippets.sync(self.root, check=False)
        self.assertIn("````markdown\n```js\nx\n```\n````", doc.read_text())

    def test_errors(self):
        cases = {
            "unknown snippet 'nope'": ("tests/probe/a.ts", "", BLOCK.format(name="nope")),
            "has no snippet:end": ("tests/probe/a.ts", "// snippet:start demo\nx\n", ""),
            "does not match": ("tests/probe/a.ts", "// snippet:start demo\nx\n// snippet:end other\n", ""),
            "used by no skill": ("tests/probe/a.ts", "// snippet:start demo\nx\n// snippet:end demo\n", ""),
            "is empty": ("tests/probe/a.ts", "// snippet:start demo\n// snippet:end demo\n", BLOCK.format(name="demo")),
            "no matching": ("tests/probe/a.ts", "", "<!-- snippet: demo -->\n"),
        }
        for message, (source, code, doc) in cases.items():
            with self.subTest(message):
                self.write(source, code)
                self.doc(doc)
                with self.assertRaisesRegex(snippets.SnippetError, message):
                    snippets.sync(self.root, check=True)

    def test_name_defined_in_two_files_is_rejected(self):
        self.write("tests/probe/a.ts", "// snippet:start demo\na\n// snippet:end demo\n")
        self.write("tests/probe/b.ts", "// snippet:start demo\nb\n// snippet:end demo\n")
        self.doc(BLOCK.format(name="demo"))
        with self.assertRaisesRegex(snippets.SnippetError, "already defined"):
            snippets.sync(self.root, check=True)

    def test_repository_is_in_sync(self):
        stale, _ = snippets.sync(ROOT, check=True)
        self.assertEqual(stale, [], "run: python3 scripts/sync-snippets.py")


if __name__ == "__main__":
    unittest.main()
