"""Offline integration regression using only Gradle core and locally authored POMs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "tests/kotlin-sdk/minimal-app/gradlew"


@unittest.skipUnless(os.environ.get("RUN_GRADLE_INVENTORY_TESTS") == "1", "requires cached Gradle; enabled in Maven CI")
class MavenInventoryTests(unittest.TestCase):
    def inventory(self, root):
        output = root / "inventory.json"
        result = subprocess.run([str(WRAPPER), "-p", str(root), "dependencyInventory", "-I",
                                 str(ROOT / "scripts/dependency-inventory.gradle"), "--offline", "--console=plain"],
                                env=dict(os.environ, DEPENDENCY_AUDIT_OUTPUT=str(output)),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return result, output

    def project(self, directory, dependencies):
        root = Path(directory)
        (root / "settings.gradle").write_text("rootProject.name = 'inventory-regression'\n")
        (root / "repository").mkdir()
        (root / "build.gradle").write_text("plugins { id 'java' }\nrepositories { maven { url = uri('repository') } }\n"
            "configurations { compilerPlugin { canBeResolved = true; canBeConsumed = false } }\n"
            "dependencies {\n" + dependencies + "\n}\n")
        return root

    def module(self, root, name, child=None):
        path = root / "repository/example" / name / "1.0"
        path.mkdir(parents=True)
        dependency = ("<dependencies><dependency><groupId>example</groupId><artifactId>" + child +
                      "</artifactId><version>1.0</version></dependency></dependencies>") if child else ""
        (path / (name + "-1.0.pom")).write_text("<project><modelVersion>4.0.0</modelVersion>"
            "<groupId>example</groupId><artifactId>" + name + "</artifactId><version>1.0</version>" + dependency + "</project>")

    def test_unresolved_graph_fails_without_success_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.project(directory, "implementation 'example:missing:1.0'")
            result, output = self.inventory(root)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("example:missing:1.0", result.stdout)
            self.assertFalse(output.exists())

    def test_compile_processor_and_compiler_plugin_transitives_are_included(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.project(directory, "compileOnly 'example:compile:1.0'\n"
                "annotationProcessor 'example:processor:1.0'\ncompilerPlugin 'example:compiler:1.0'")
            expected = set()
            for name in ("compile", "processor", "compiler"):
                self.module(root, name, name + "-child")
                self.module(root, name + "-child")
                expected.update((name, name + "-child"))
            result, output = self.inventory(root)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual({item["name"] for item in json.loads(output.read_text())}, expected)


if __name__ == "__main__":
    unittest.main()
