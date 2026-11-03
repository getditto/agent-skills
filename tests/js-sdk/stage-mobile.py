#!/usr/bin/env python3
"""Refresh the ignored mobile fixture from the shipped starter without copying credentials."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
with tempfile.TemporaryDirectory() as temporary:
    project = Path(temporary) / 'app'
    subprocess.run([sys.executable, str(ROOT / 'skills/js-expo/scripts/create-app.py'), str(project)], check=True)
    target = HERE / 'mobile'
    shutil.copytree(project, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns('config.local.json'))
    # Compile the optional real-native probe in CI without bundling it into the starter.
    shutil.copy2(HERE / 'native/Probe.tsx', target / 'src/NativeProbe.tsx')
    if not (target / 'config.local.json').exists():
        shutil.copy2(project / 'config.local.json', target / 'config.local.json')
    if (HERE / 'mobile-package-lock.json').exists():
        shutil.copy2(HERE / 'mobile-package-lock.json', target / 'package-lock.json')
