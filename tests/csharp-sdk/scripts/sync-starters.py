#!/usr/bin/env python3
"""Materialize shared C# in each standalone dotnet-new template; --check detects drift."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "skills/csharp-sdk/assets"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
for template in sorted((ASSETS / "templates").iterdir()):
    destination = template / "Common"
    if not args.check:
        destination.mkdir(exist_ok=True)
    for source in sorted((ASSETS / "common").glob("*.cs")):
        target = destination / source.name
        if args.check:
            if not target.exists() or target.read_bytes() != source.read_bytes():
                raise SystemExit(f"Starter drift: {target.relative_to(ROOT)}")
        else:
            target.write_bytes(source.read_bytes())
print("Shared starter sources are synchronized.")
