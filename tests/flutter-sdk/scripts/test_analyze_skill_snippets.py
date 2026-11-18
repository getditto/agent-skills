#!/usr/bin/env python3
"""Tests for analyze_skill_snippets.py: compiling the Dart fences published in a skill.

These run the real Flutter toolchain (pinned in tests/flutter-sdk/versions.json), so
they need network access for `pub get`.
"""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "analyze_skill_snippets.py"
sys.dont_write_bytecode = True

PRELUDE = "<!-- dart-prelude: " "ditto -->"
PRELUDE_FLUTTER = "<!-- dart-prelude: " "ditto-flutter -->"
V50 = "<!-- dart-version: " "5.0 -->"
FRAGMENT = "<!-- dart-fragment: {} -->"
BLOCK_OPEN = "<!-- snippet: " "demo -->"
BLOCK_CLOSE = "<!-- /snippet" " -->"


def fence(code, *markers):
    head = "".join(f"{m}\n" for m in markers)
    return f"{head}```dart\n{textwrap.dedent(code).strip()}\n```\n"


class AnalyzeSkillSnippets(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dart-fences-")
        self.addCleanup(self.temp.cleanup)
        self.skill = Path(self.temp.name)

    def run_script(self, body):
        (self.skill / "x.md").write_text("# Probe\n\n" + body, encoding="utf-8")
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--skill", str(self.skill)],
            capture_output=True,
            text=True,
            timeout=900,
        )

    def test_valid_fence_passes(self):
        result = self.run_script(fence("void main() {}"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_positional_arguments_fail(self):
        body = fence("await ditto.store.execute('SELECT 1', {'a': 1});", PRELUDE)
        result = self.run_script(body)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("x.md:5", result.stdout + result.stderr)

    def test_await_void_update_transport_config_fails(self):
        body = fence("await ditto.updateTransportConfig((b) {});", PRELUDE)
        result = self.run_script(body)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("await_only_futures", result.stdout + result.stderr)

    def test_prelude_wraps(self):
        body = fence("final result = await ditto.store.execute('SELECT 1');\nprint(result);", PRELUDE)
        body = body.replace("print(result);", "result.items.length;")
        result = self.run_script(body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_flutter_prelude_imports_foundation(self):
        code = "if (!kIsWeb) ditto.sync.start();"
        result = self.run_script(fence(code, PRELUDE_FLUTTER))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Without foundation, kIsWeb is undefined.
        result = self.run_script(fence(code, PRELUDE))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("x.md:5", result.stdout + result.stderr)

    def test_flutter_prelude_reports_fence_lines(self):
        body = fence("ditto.sync.start();\nawait ditto.sync.start();", PRELUDE_FLUTTER)
        result = self.run_script(body)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("x.md:6", result.stdout + result.stderr)

    def test_dart_version_marker_uses_that_pin(self):
        code = (
            "// ignore: experimental_member_use\n"
            "ditto.store.registerObserverV2('SELECT 1', onChange: (_) {});"
        )
        self.assertEqual(self.run_script(fence(code, PRELUDE)).returncode, 0)
        result = self.run_script(fence(code, PRELUDE, V50))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("x.md:", result.stdout + result.stderr)

    def test_fragment_with_ditto_call_rejected(self):
        body = fence("await ditto.sync.start();", FRAGMENT.format("pseudo-diff"))
        result = self.run_script(body)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("x.md:5", result.stdout + result.stderr)

    def test_unknown_fragment_reason_rejected(self):
        body = fence("this is not dart", FRAGMENT.format("because-i-said-so"))
        result = self.run_script(body)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("because-i-said-so", result.stdout + result.stderr)

    def test_accepted_fragment_is_skipped(self):
        body = fence("- old\n+ new", FRAGMENT.format("pseudo-diff"))
        result = self.run_script(body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_snippet_blocks_ignored(self):
        broken = fence("this does not compile at all")
        result = self.run_script(f"{BLOCK_OPEN}\n{broken}{BLOCK_CLOSE}\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class Helpers(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("analyze_skill_snippets", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        # dataclasses resolves string annotations through sys.modules.
        sys.modules[spec.name] = self.module
        self.addCleanup(sys.modules.pop, spec.name, None)
        spec.loader.exec_module(self.module)

    def test_windows_candidates_include_bat(self):
        flutter = Path("sdk") / "bin" / "flutter"
        names = [Path(c).name for c in self.module.executable_candidates(flutter, windows=True)]
        self.assertEqual(names, ["flutter.bat", "flutter.exe", "flutter"])
        self.assertEqual(self.module.executable_candidates(flutter, windows=False), [str(flutter)])

    def test_fragment_ditto_call_detection(self):
        def errors_for(code):
            errors = []
            fence = self.module.Fence(Path("x.md"), 3, code, {"dart-fragment": "pseudo-diff"})
            self.assertIsNone(self.module.classify(fence, {"5.2": "5.2.0"}, errors))
            return errors

        self.assertTrue(errors_for("- ditto.sync.start();"))
        self.assertTrue(errors_for("+ await Ditto.open(config);"))
        self.assertTrue(errors_for("- _ditto.store.execute(q);"))
        self.assertTrue(errors_for("+ myDitto.sync.start();"))
        self.assertTrue(errors_for("  final ditto2 = otherditto.store;"))
        self.assertEqual(errors_for("// The old shape, removed in Ditto."), [])
        self.assertEqual(errors_for("// Ditto. Then a new sentence, ditto ."), [])

if __name__ == "__main__":
    unittest.main()
