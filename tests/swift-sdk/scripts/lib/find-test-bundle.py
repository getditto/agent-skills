#!/usr/bin/env python3
"""Find the single macOS test product emitted by this fixture's SwiftPM build."""

from pathlib import Path
import sys


def find_bundle(bin_directory: Path) -> Path:
    binaries = [
        bundle / "Contents" / "MacOS" / bundle.stem
        for bundle in bin_directory.glob("*.xctest")
        if (bundle / "Contents" / "MacOS" / bundle.stem).is_file()
    ]
    if len(binaries) != 1:
        raise ValueError(
            f"Expected one built test bundle in {bin_directory}, found {len(binaries)}. "
            "Run swift build --build-tests and inspect the build products."
        )
    return binaries[0]


if __name__ == "__main__":
    try:
        print(find_bundle(Path(sys.argv[1])))
    except (IndexError, ValueError) as error:
        sys.exit(str(error))
