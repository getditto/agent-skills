#!/usr/bin/env python3
"""Copy the tested Expo starter and its sibling skill assets; never overwrite a project."""
import argparse
from pathlib import Path
import shutil


def create(destination):
    skills = Path(__file__).resolve().parents[2]
    if destination.exists():
        raise ValueError(f"Destination already exists: {destination}")
    required = [skills / name / "assets" for name in
                ("js-expo", "js-sdk", "js-react-native", "native-app-config")]
    if not all(path.is_dir() for path in required):
        raise ValueError("Install the complete ditto-js plugin, including its sibling skills")
    shutil.copytree(required[0], destination)
    source = destination / "src"
    source.mkdir()
    for name in ("runtime.ts", "DittoProvider.tsx", "tasks.ts"):
        shutil.copy2(required[1] / name, source / name)
    for name in ("App.tsx", "TasksScreen.tsx", "permissions.ts"):
        shutil.copy2(required[2] / name, source / name)
    shutil.copy2(required[3] / "android-permissions.ts", source / "android-permissions.ts")
    shutil.copy2(destination / "config.example.json", destination / "config.local.json")
    print(f"Created {destination}. Configure config.local.json, then npm install and npm run android or npm run ios.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        create(args.destination.expanduser().absolute())
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
