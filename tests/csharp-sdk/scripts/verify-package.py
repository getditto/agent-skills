#!/usr/bin/env python3
"""Extract a standalone archive, use its generator, publish and execute its Console app."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('starter_checks', Path(__file__).with_name('verify-starters.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

with tempfile.TemporaryDirectory(prefix='ditto-installed-csharp-') as temporary:
    workspace = Path(temporary).resolve()
    packages = workspace / 'packages'
    checks.command([sys.executable, str(ROOT / 'scripts/package-sdk-plugin.py'),
                    '--plugin', 'ditto-csharp', '--output', str(packages)])
    archive = packages / 'csharp-sdk.zip'
    installed = workspace / 'installed'
    with zipfile.ZipFile(archive) as package:
        package.extractall(installed)
    skill = next(installed.rglob('csharp-sdk/SKILL.md')).parent
    app = workspace / 'application'
    checks.command([sys.executable, str(skill / 'scripts/create-app.py'), 'console',
                    str(app), '--name', 'InstalledTasks', '--sdk-version', '5.2.0'])
    published = workspace / 'published'
    checks.command(['dotnet', 'publish', str(app), '-c', 'Release', '-o', str(published)])
    checks.console_runtime(published / 'InstalledTasks.dll', checks.runner.environment('5.2.0'), workspace / 'store')
    print('PASS standalone installed archive: generator, native publish and execution')
