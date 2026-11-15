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
START, END = "// snippet:" + "start", "// snippet:" + "end"


def marked(name, code, prefix="// "):
    return f"{prefix}snippet:start {name}\n{code}\n{prefix}snippet:end {name}\n"


class SyncSnippets(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="snippets-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "skills/probe").mkdir(parents=True)
        (self.root / "tests/probe").mkdir(parents=True)

    def write(self, rel, text, binary=False):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if binary:
            path.write_bytes(text)
        else:
            path.write_text(text, encoding="utf-8")
        return path

    def doc(self, body, name="SKILL.md"):
        return self.write(f"skills/probe/{name}", f"# Probe\n\n{body}")

    def sync(self, check=False):
        return snippets.sync(self.root, check=check)

    def test_injects_regions_joined_and_dedented_together(self):
        self.write(
            "tests/probe/Main.kt",
            f"import a.B\n{START} demo\nimport a.C\n{END} demo\n"
            f"{START} demo\nclass Main {{\n    fun f() = 1\n{END} demo\n"
            f"    fun hidden() = 2\n{START} demo\n}}\n{END} demo\n",
        )
        doc = self.doc(BLOCK.format(name="demo"))
        self.assertEqual(self.sync(), (["skills/probe/SKILL.md"], {"demo"}))
        text = doc.read_text()
        self.assertIn("```kotlin\nimport a.C\n\nclass Main {\n    fun f() = 1\n}\n```", text)
        self.assertNotIn("hidden", text)
        self.assertNotIn("snippet:start", text)
        self.assertNotIn("tests/probe", text)  # no repository paths in installed skills
        self.assertEqual(self.sync()[0], [])  # idempotent
        self.assertEqual(self.sync(check=True)[0], [])

    def test_continuation_regions_join_without_a_blank_line(self):
        self.write(
            "tests/probe/build.gradle.kts",
            f"{START} demo\nval license = System.getenv(\"L\")\n{END} demo\n"
            f"    ?: localFile[\"L\"]\n{START} demo\n    ?: \"\"\n{END} demo\n",
        )
        doc = self.doc(BLOCK.format(name="demo"))
        self.sync()
        self.assertIn('val license = System.getenv("L")\n    ?: ""\n```', doc.read_text())

    def test_check_reports_drift_without_writing(self):
        source = self.write("tests/probe/a.ts", marked("demo", "const a = 1;"))
        doc = self.doc(BLOCK.format(name="demo"))
        self.sync()
        source.write_text(marked("demo", "const a = 2;"))
        before = doc.read_text()
        self.assertEqual(self.sync(check=True)[0], ["skills/probe/SKILL.md"])
        self.assertEqual(doc.read_text(), before)

    def test_comment_styles(self):
        self.write("tests/probe/gradle.properties", marked("props", "a=b", prefix="# "))
        self.write("tests/probe/Manifest.xml", '<?xml version="1.0"?>\n<!-- snippet:start xml -->\n<m/>\n<!-- snippet:end xml -->\n')
        doc = self.doc(BLOCK.format(name="props") + BLOCK.format(name="xml"))
        self.sync()
        text = doc.read_text()
        self.assertIn("```properties\na=b\n```", text)
        self.assertIn("```xml\n<m/>\n```", text)

    def test_blocks_inside_fenced_code_are_left_alone(self):
        self.write("tests/probe/a.ts", marked("demo", "x"))
        example = "```markdown\n" + BLOCK.format(name="demo") + "```\n\n"
        doc = self.doc(example + BLOCK.format(name="demo"))
        self.sync()
        text = doc.read_text()
        self.assertTrue(text.startswith("# Probe\n\n" + example))
        self.assertEqual(text.count("```ts\nx\n```"), 1)

    def test_code_containing_a_fence_gets_a_longer_fence(self):
        self.write("tests/probe/a.py", marked("demo", 'DOC = """\n```js\nx\n```\n"""', prefix="# "))
        doc = self.doc(BLOCK.format(name="demo"))
        self.sync()
        self.assertIn('````python\nDOC = """\n```js\nx\n```\n"""\n````', doc.read_text())
        self.assertEqual(self.sync(check=True)[0], [])  # the inner fence doesn't confuse rescans

    def test_markers_in_strings_are_not_markers(self):
        self.write("tests/probe/a.py", 'TEXT = "// snippet:start demo"\n')
        self.doc("No blocks.\n")
        self.assertEqual(self.sync(check=True), ([], set()))

    def test_errors(self):
        cases = {
            "unknown snippet 'nope'": ("tests/probe/a.ts", "", BLOCK.format(name="nope")),
            "has no snippet:end": ("tests/probe/a.ts", f"{START} demo\nx\n", ""),
            "does not match": ("tests/probe/a.ts", f"{START} demo\nx\n{END} other\n", ""),
            "used by no skill": ("tests/probe/a.ts", marked("demo", "x"), ""),
            "is empty": ("tests/probe/a.ts", f"{START} demo\n{END} demo\n", BLOCK.format(name="demo")),
            "has no <!-- /snippet -->": ("tests/probe/a.ts", "", "<!-- snippet: demo -->\n"),
            "malformed snippet marker;": ("tests/probe/a.ts", f"{START} Demo\nx\n{END} Demo\n", ""),
            "malformed snippet marker inside": ("tests/probe/a.ts", f"{START} demo\nx // snippet:end demo\n", ""),
            "not supported": ("tests/probe/A.java", marked("demo", "class A {}"), BLOCK.format(name="demo")),
            "malformed snippet comment": ("tests/probe/a.ts", "", "<!-- snippet:demo -->\n"),
        }
        for message, (source, code, doc) in cases.items():
            with self.subTest(message):
                for old in (self.root / "tests/probe").iterdir():
                    old.unlink()
                self.write(source, code)
                self.doc(doc)
                with self.assertRaisesRegex(snippets.SnippetError, message):
                    self.sync(check=True)

    def test_non_utf8_source_with_markers_is_rejected(self):
        self.write("tests/probe/a.ts", b"// snippet:start demo\n\xff\n// snippet:end demo\n", binary=True)
        self.doc(BLOCK.format(name="demo"))
        with self.assertRaisesRegex(snippets.SnippetError, "not UTF-8"):
            self.sync(check=True)

    def test_name_defined_in_two_files_is_rejected(self):
        self.write("tests/probe/a.ts", marked("demo", "a"))
        self.write("tests/probe/b.ts", marked("demo", "b"))
        self.doc(BLOCK.format(name="demo"))
        with self.assertRaisesRegex(snippets.SnippetError, "already defined"):
            self.sync(check=True)

    def test_code_that_installers_read_as_a_skill_link_is_rejected(self):
        self.write("skills/other/SKILL.md", "# Other\n")
        self.write("tests/probe/a.ts", marked("demo", "import x from '../other/x';"))
        self.doc(BLOCK.format(name="demo"))
        with self.assertRaisesRegex(snippets.SnippetError, "link to that skill"):
            self.sync(check=True)

    def test_unclosed_fence_is_an_error(self):
        self.write("tests/probe/a.ts", marked("demo", "x"))
        self.doc("````\nopened with four, never closed\n```\n\n" + BLOCK.format(name="demo"))
        with self.assertRaisesRegex(snippets.SnippetError, "never closed"):
            self.sync(check=True)

    def test_markdown_under_tests_is_documentation(self):
        self.write("tests/probe/README.md", "// snippet:start example\nshown as syntax\n// snippet:end example\n")
        self.doc("No blocks.\n")
        self.assertEqual(self.sync(check=True), ([], set()))

    def test_continuation_rule_applies_only_to_code(self):
        self.write("tests/probe/a.yml", "# snippet:start demo\na: 1\n# snippet:end demo\n"
                   "b: 2\n# snippet:start demo\n.hidden: 3\n# snippet:end demo\n")
        doc = self.doc(BLOCK.format(name="demo"))
        self.sync()
        self.assertIn("```yaml\na: 1\n\n.hidden: 3\n```", doc.read_text())

    def test_a_skill_may_link_to_itself(self):
        self.write("skills/probe/SKILL.md", "# Probe\n")
        self.write("tests/probe/a.ts", marked("demo", "import x from '../probe/x';"))
        self.doc(BLOCK.format(name="demo"), name="references/r.md")
        self.assertEqual(self.sync()[1], {"demo"})

    def test_crlf_files_stay_crlf(self):
        self.write("tests/probe/a.ts", marked("demo", "x"))
        doc = self.write("skills/probe/SKILL.md", "# Probe\r\n\r\n<!-- snippet: demo -->\r\n<!-- /snippet -->\r\n")
        self.sync()
        data = doc.read_bytes()
        self.assertIn(b"```ts\r\nx\r\n```\r\n", data)
        self.assertNotIn(b"\n\n", data.replace(b"\r\n", b"\r"))
        self.assertEqual(self.sync(check=True)[0], [])

    def test_repository_is_in_sync(self):
        stale, _ = snippets.sync(ROOT, check=True)
        self.assertEqual(stale, [], "run: python3 scripts/sync-snippets.py")


if __name__ == "__main__":
    unittest.main()
