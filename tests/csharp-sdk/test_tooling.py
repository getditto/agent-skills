"""Offline tests for packaged generators and their failure boundaries (stdlib only)."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GENERATOR = load('csharp_generator', ROOT / 'skills/csharp-sdk/scripts/create-app.py')
PACKAGER = load('csharp_packager', ROOT / 'scripts/package-sdk-plugin.py')
PACKAGER.configure('ditto-csharp')


class CSharpToolingTests(unittest.TestCase):
    def test_latest_stable_selection_is_numeric_and_v5_only(self):
        data = {'versions': ['4.14.7', '5.2.0', '5.10.0', '5.11.0-preview.1', '6.0.0', '5.9.0']}
        with patch.object(GENERATOR.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps(data).encode())):
            self.assertEqual(GENERATOR.resolve_version(), '5.10.0')

    def test_no_stable_release_is_an_error(self):
        with patch.object(GENERATOR.urllib.request, 'urlopen', return_value=io.BytesIO(b'{"versions":["6.0.0","5.2.0-rc.1"]}')):
            with self.assertRaises(ValueError): GENERATOR.resolve_version()

    def test_generator_preserves_existing_content_and_rejects_wrong_framework(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'existing'
            path.write_text('customer file')
            for arguments in ([str(path)], [str(path), '--framework', 'net48']):
                with patch.object(sys, 'argv', ['create-app.py', 'console'] + arguments), contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as error: GENERATOR.main()
                    self.assertEqual(error.exception.code, 2)
                self.assertEqual(path.read_text(), 'customer file')

    def test_common_sources_are_synchronized(self):
        subprocess.run([sys.executable, str(ROOT / 'tests/csharp-sdk/scripts/sync-starters.py'), '--check'], check=True)

    def test_packages_are_scoped_and_include_hidden_template_metadata(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            output = Path(directory) / 'packages'
            PACKAGER.sync(check=True)
            PACKAGER.build(output)
            archives = list(output.glob('*.zip'))
            self.assertEqual(len(archives), 5)
            for path in archives:
                with self.subTest(archive=path.name), zipfile.ZipFile(path) as archive:
                    names = archive.namelist()
                    skills = [name for name in names if name.endswith('/SKILL.md')]
                    self.assertEqual(len(skills), 1)
                    prefix = skills[0][:-len('SKILL.md')]
                    self.assertTrue(prefix.endswith('csharp-sdk/'))
                    for kind in ('console', 'winforms', 'maui', 'uno', 'avalonia'):
                        config = prefix + 'assets/templates/' + kind + '/.template.config/template.json'
                        self.assertEqual(json.loads(archive.read(config))['shortName'], 'ditto-' + kind)
                        common = 'assets/templates/' + kind + '/Common/TaskStore.cs'
                        self.assertEqual(archive.read(prefix + common), (ROOT / 'skills/csharp-sdk' / common).read_bytes())
                    self.assertIn(prefix + 'scripts/create-app.py', names)
                    self.assertFalse(any(set(Path(name).parts) & {'.env', 'obj', 'bin', 'tests', '__pycache__'} for name in names))


if __name__ == '__main__':
    unittest.main()
