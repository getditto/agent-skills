#!/bin/bash
#
# Compile the fixture for every Apple platform the skill claims support for, so a
# platform claim is backed by a build rather than by a compatibility table.
#
#   ./scripts/build-platforms.sh 5.1.0
#   ./scripts/build-platforms.sh --all
#
# Device builds run with code signing disabled — this proves the sources and the
# XCFramework slice compile and link, not that the app is distributable. `ARCHS=arm64`
# is required: 5.1.0 ships no x86_64 slice for any platform, so a generic destination
# that also wants x86_64 fails there.
#
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FIXTURE_DIR"

# Source from the computed absolute path, not `dirname BASH_SOURCE[0]` again: after
# `cd`, a *relative* BASH_SOURCE (e.g. `bash tests/swift-sdk/scripts/build-platforms.sh`
# from the repo root) resolves against the new working directory and fails.
. "$FIXTURE_DIR/scripts/lib/build-lock.sh"
acquire_build_lock
mkdir -p .build

build_for() {
  local version="$1" label="$2" destination="$3"
  local log=".build/xcodebuild-$version-${label// /-}.log"
  echo "--- $version : $label"
  # A per-version derived-data path: Xcode caches the resolved package graph and the
  # built module, and reusing one path across version pins fails with
  # "cannot load underlying module for 'DittoSwift'".
  # Build the UI library's scheme, which also compiles SkillSupport and the SDK.
  # The whole-package scheme embeds the same v4 binary frameworks for both command
  # line executables into one output directory on Xcode 26 (duplicate copy outputs).
  # run.sh separately builds and executes the macOS command-line products.
  DITTO_SWIFT_VERSION="$version" xcodebuild \
    -scheme UIPatterns \
    -destination "$destination" \
    -derivedDataPath ".build/xcode-$version" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    build > "$log" 2>&1 || {
      echo "    FAILED — diagnostics:"
      grep -E 'error:|warning:|BUILD FAILED' "$log" | head -40
      echo "    (full log: $FIXTURE_DIR/$log)"
      return 1
    }
  echo "    ok"
}

run_one() {
  local version="$1"
  echo "=============================================================="
  echo "Ditto $version — platform compile matrix ($(uname -m))"
  echo "=============================================================="
  build_for "$version" "macOS (AppKit)"    "platform=macOS,arch=arm64"
  build_for "$version" "iOS Simulator"     "generic/platform=iOS Simulator"
  build_for "$version" "iOS device"        "generic/platform=iOS"
  build_for "$version" "Mac Catalyst"      "platform=macOS,variant=Mac Catalyst,arch=arm64"
}

VERSIONS=()
for arg in "$@"; do
  case "$arg" in
    --all) VERSIONS=(4.14.6 5.0.3 5.1.0 5.2.0-rc.2) ;;
    *) VERSIONS+=("$arg") ;;
  esac
done
[[ ${#VERSIONS[@]} -eq 0 ]] && VERSIONS=(5.1.0)

for version in "${VERSIONS[@]}"; do
  run_one "$version"
done
