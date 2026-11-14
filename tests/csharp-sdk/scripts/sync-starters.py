#!/usr/bin/env python3
"""Materialize shared C# in each standalone dotnet-new template; --check detects drift.

WinForms gets the C# 7.3 copy (assets/common-legacy) because it also builds for .NET
Framework. Every other template gets the modern copy (assets/common).
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "skills/csharp-sdk/assets"
LEGACY_TEMPLATES = {"winforms"}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
for template in sorted((ASSETS / "templates").iterdir()):
    if not template.is_dir():
        continue
    source_dir = ASSETS / ("common-legacy" if template.name in LEGACY_TEMPLATES else "common")
    destination = template / "Common"
    sources = sorted(source_dir.glob("*.cs"))
    if not args.check:
        destination.mkdir(exist_ok=True)
        for stale in destination.glob("*.cs"):
            if not (source_dir / stale.name).exists():
                stale.unlink()
    for source in sources:
        target = destination / source.name
        if args.check:
            if not target.exists() or target.read_bytes() != source.read_bytes():
                raise SystemExit(f"Starter drift: {target.relative_to(ROOT)} (source: {source.relative_to(ROOT)})")
        else:
            target.write_bytes(source.read_bytes())
    if args.check:
        extra = {p.name for p in destination.glob("*.cs")} - {p.name for p in sources}
        if extra:
            raise SystemExit(f"Starter drift: unexpected {sorted(extra)} in {destination.relative_to(ROOT)}")
print("Shared starter sources are synchronized.")
