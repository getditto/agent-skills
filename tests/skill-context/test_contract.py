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

    def check(self, name="probe", body="Guidance.", resource=None):
        (self.skill / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Probe guidance.\n---\n\n{body}", encoding="utf-8"
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
        split = "// snippet:start app\na\n// snippet:end app\n// snippet:start app\nb\n// snippet:end app\n"
        self.assertTrue(any("one region" in e for e in self.check(self.block(), split)))


if __name__ == "__main__":
    unittest.main()
