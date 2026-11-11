#!/usr/bin/env python3
"""Run the exact published program and assert its observer/version transcript."""
import argparse
import importlib.util
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('run.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--version', default='5.2.0')
args = parser.parse_args()
result = subprocess.run(['dotnet', 'run', '--project', str(ROOT / 'tests/csharp-sdk/MinimalApp'),
                         '-p:DittoVersion=' + args.version], env=runner.environment(args.version),
                        text=True, capture_output=True, timeout=90)
# Do not echo native logs: they can contain application identifiers or user data.
if result.returncode:
    raise SystemExit('Minimal app failed; reproduce locally to inspect SDK diagnostics.')
lines = result.stdout.splitlines()
assert 'observer: Toyota' in lines, 'Missing observer delivery'
assert any(line.startswith('SDK version: ' + args.version) for line in lines), 'Wrong loaded SDK'
print('PASS normative minimal program: observer delivery and SDK ' + args.version)
