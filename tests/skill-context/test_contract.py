#!/usr/bin/env python3
"""Negative controls for portable skill discovery and bounded resource reads."""

import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("skill_validator", ROOT / "scripts/validate-sdk-skills.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ContextContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="skill-context-")
        self.root = Path(self.temp.name)
        self.skill = self.root / "probe"
        self.skill.mkdir()
        self.previous_root = validator.SKILLS_DIR
        validator.SKILLS_DIR = str(self.root)
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(setattr, validator, "SKILLS_DIR", self.previous_root)

    def check(self, name="probe", body="Guidance.", resource=None, description="Probe guidance."):
        (self.skill / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: {description}\n---\n\n{body}", encoding="utf-8"
        )
        if resource is not None:
            (self.skill / "reference.md").write_text(resource, encoding="utf-8")
        validator.errors.clear()
        validator.warnings.clear()
        validator.validate_every_skill()
        return list(validator.errors)

    def test_matching_name_loads_and_mismatch_is_rejected(self):
        self.assertEqual(self.check(), [])
        self.assertTrue(any("does not match" in error for error in self.check(name="legacy-alias")))

    def test_contents_cannot_excuse_an_oversized_full_file(self):
        text = "# Resource\n\n## Contents\n\n- [Detail](#detail)\n\n## Detail\n\n"
        self.assertEqual(self.check(resource=text + "x" * 10_000), [])
        self.assertTrue(any("20,000" in error for error in self.check(resource=text + "x" * 20_001)))

    def test_dense_short_resource_still_needs_navigation(self):
        self.assertTrue(any("linked" in error for error in self.check(resource="# Dense\n" + "x" * 8_001)))

    def test_fake_heading_in_code_does_not_make_a_link_valid(self):
        text = "# Resource\n\n[Missing](#missing)\n\n```md\n## Missing\n```\n"
        self.assertTrue(any("does not match" in error for error in self.check(resource=text)))

    def test_relative_link_out_of_skills_is_rejected(self):
        errors = self.check(resource="# Resource\n\n[Tests](../../tests/js-sdk/README.md)\n")
        self.assertTrue(any("leaves" in error and "sync-snippets" in error for error in errors))

    def test_every_link_form_out_of_skills_is_rejected(self):
        forms = {
            "reference definition": "[tests]: ../../tests/js-sdk/README.md",
            "html href": '<a href="../../tests/js-sdk/README.md">tests</a>',
            "html src": '<img src="../../docs/diagram.png">',
        }
        for label, line in forms.items():
            with self.subTest(label):
                self.assertTrue(any("leaves" in e for e in self.check(resource=f"# Resource\n\n{line}\n")))

    def test_every_repository_url_form_is_rejected(self):
        forms = [
            "[Tests](https://github.com/getditto/agent-skills/blob/main/tests/js-sdk/README.md)",
            "<https://github.com/getditto/agent-skills/blob/main/tests/js-sdk/README.md>",
            "[Tag](https://github.com/getditto/agent-skills/blob/v0.6.0/docs/install-js.md)",
            "[Raw](https://raw.githubusercontent.com/getditto/agent-skills/main/README.md)",
            "[Http](http://github.com/getditto/agent-skills/tree/main/tests)",
            "[Case](https://github.com/GetDitto/Agent-Skills/blob/main/README.md)",
            "[ref]: https://github.com/getditto/agent-skills/blob/main/README.md",
            "See github.com/getditto/agent-skills/tree/main/tests for the fixtures.",
        ]
        for line in forms:
            with self.subTest(line):
                errors = self.check(resource=f"# Resource\n\n{line}\n")
                self.assertTrue(any("refers to this repository" in e for e in errors))

    def test_more_link_forms_are_rejected(self):
        forms = {
            "single-quoted title": "[x](../../tests/a.md 'T')",
            "paren title": "[x](../../tests/a.md (T))",
            "unquoted href": "<a href=../../tests/a.md>x</a>",
            "file scheme": "[x](file:../../tests/a.md)",
        }
        for label, line in forms.items():
            with self.subTest(label):
                self.assertTrue(any("leaves" in e for e in self.check(resource=f"# Resource\n\n{line}\n")))
        for line in ["git@github.com:getditto/agent-skills.git",
                     "https://api.github.com/repos/getditto/agent-skills/contents"]:
            with self.subTest(line):
                errors = self.check(resource=f"# Resource\n\n{line}\n")
                self.assertTrue(any("refers to this repository" in e for e in errors))

    def test_no_false_positives(self):
        resource = (
            "# Resource\n\n```tsx\n<img src=\"./logo.png\" />\n[tests]: ../../tests/x\n```\n\n"
            "[String: Any]: a Swift dictionary type, not a link definition.\n\n"
            "See github.com/getditto/agent-skills-other for another project.\n\n"
            "Docs: <https://docs.ditto.live/sdk/latest>.\n"
        )
        self.assertEqual(self.check(resource=resource), [])

    def test_repository_url_in_an_asset_is_rejected(self):
        assets = self.skill / "assets"
        assets.mkdir()
        (assets / "a.ts").write_text("// see https://github.com/getditto/agent-skills/blob/main/tests/x.ts\n")
        self.assertTrue(any("a.ts:1: refers to this repository" in e for e in self.check()))

    def test_readme_follows_the_same_rule(self):
        (self.skill / "README.md").write_text(
            "# Probe\n\n[Tests](https://github.com/getditto/agent-skills/blob/main/tests/x.md)\n", encoding="utf-8"
        )
        self.assertTrue(any("refers to this repository" in e for e in self.check()))

    def test_sibling_skill_and_external_links_are_allowed(self):
        sibling = self.root / "other"
        sibling.mkdir()
        (sibling / "SKILL.md").write_text("---\nname: other\ndescription: Other.\n---\n\nBody.")
        resource = "# Resource\n\n[Other](../other/SKILL.md) [Docs](https://docs.ditto.live/) [Mail](mailto:a@b.c)\n"
        self.assertEqual(self.check(resource=resource), [])

    def test_entry_point_cannot_overflow_its_budget(self):
        self.assertTrue(any("12,000" in error for error in self.check(body="x" * 12_001)))

    def test_entry_point_stays_under_500_lines(self):
        self.assertEqual(self.check(body="x\n" * 500), [])
        self.assertTrue(any("500" in error for error in self.check(body="x\n" * 501)))

    def test_resource_over_100_lines_needs_contents(self):
        self.assertEqual(self.check(resource="# Resource\n" + "x\n" * 99), [])
        self.assertTrue(any("Contents" in e for e in self.check(resource="# Resource\n" + "x\n" * 101)))

    def test_description_rules(self):
        cases = {
            "Use when probing things.": "before 'Use when",
            "Probes things. You can use it for probes.": "third person",
            "I help with probes.": "third person",
            "Probes <b>things</b>.": "XML",
        }
        for description, message in cases.items():
            with self.subTest(description):
                self.assertTrue(any(message in e for e in self.check(description=description)))
        self.assertEqual(self.check(description="Use ONLY for probes. Probes things. Use when probing."), [])
        self.assertEqual(self.check(description="Probes things on Ditto SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0."), [])

    def test_version_claims_match_the_declared_lines(self):
        body = "Supports **4.14.x (LTS), 5.0.x and 5.1.x**."
        good = "# R\n\nCovers Ditto SDK 4.14.x (LTS), 5.0.x and 5.1.x.\n\n> **Available in:** 5.1+.\n"
        self.assertEqual(self.check(body=body, resource=good), [])
        stale = {
            "header": "# R\n\nCovers Ditto SDK 4.14.x and 5.0.x.\n",
            "all supported": "# R\n\n> **Available in:** all supported versions (4.14.x, 5.0.x)\n",
            "identically": "# R\n\nEverything works identically on 4.14.x and 5.0.x.\n",
            "unknown line": "# R\n\nCovers Ditto SDK 4.14.x, 5.0.x, 5.1.x and 5.2.0.\n",
            "newer feature": "# R\n\n> **Available in:** Ditto SDK 5.2.0+.\n",
        }
        for label, resource in stale.items():
            with self.subTest(label):
                self.assertTrue(any("SDK lines" in e or "newer than" in e
                                    for e in self.check(body=body, resource=resource)))

    def test_reserved_word_in_name_is_rejected(self):
        bad = self.root / "claude-probe"
        bad.mkdir()
        (bad / "SKILL.md").write_text("---\nname: claude-probe\ndescription: Probes.\n---\n\nBody.")
        self.assertTrue(any("reserved word" in e for e in self.check()))


class ExamplePrograms(unittest.TestCase):
    """SDK example programs must be whole-file snippets of a fixture CI runs."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="example-programs-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        (root / "skills/probe-sdk/examples").mkdir(parents=True)
        (root / "tests/probe-sdk").mkdir(parents=True)
        self.root = root
        previous = os.getcwd()
        os.chdir(root)
        self.addCleanup(os.chdir, previous)

    def check(self, program, source=None):
        (self.root / "skills/probe-sdk/examples/app.md").write_text(f"# App\n\n## Program\n\n{program}\n")
        if source is not None:
            (self.root / "tests/probe-sdk/App.swift").write_text(source)
        validator.errors.clear()
        validator.check_examples_are_generated("probe-sdk")
        return list(validator.errors)

    def block(self):
        return "<!-- snippet: app -->\n```swift\nlet a = 1\n```\n<!-- /snippet -->"

    def test_pasted_program_is_rejected(self):
        self.assertTrue(any("pasted code" in e for e in self.check("```swift\nlet a = 1\n```")))

    def test_whole_file_program_is_accepted(self):
        source = "// Header.\n// snippet:start app\nlet a = 1\n// snippet:end app\n"
        self.assertEqual(self.check(self.block(), source), [])

    def test_code_outside_the_region_is_rejected(self):
        above = "import X\n// snippet:start app\nlet a = 1\n// snippet:end app\n"
        self.assertTrue(any("would not compile" in e for e in self.check(self.block(), above)))
        below = "// snippet:start app\nlet a = 1\n// snippet:end app\nlet b = 2\n"
        self.assertTrue(any("last line" in e for e in self.check(self.block(), below)))
        directive = "#if canImport(Foundation)\n// snippet:start app\nlet a = 1\n// snippet:end app\n"
        self.assertTrue(any("would not compile" in e for e in self.check(self.block(), directive)))
        split = "// snippet:start app\na\n// snippet:end app\n// snippet:start app\nb\n// snippet:end app\n"
        self.assertTrue(any("one region" in e for e in self.check(self.block(), split)))


if __name__ == "__main__":
    unittest.main()
