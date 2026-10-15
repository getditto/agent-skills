#!/usr/bin/env python3
"""Negative controls for portable skill discovery and bounded resource reads."""

import importlib.util
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

    def test_entry_point_cannot_overflow_its_budget(self):
        self.assertTrue(any("12,000" in error for error in self.check(body="x" * 12_001)))


if __name__ == "__main__":
    unittest.main()
