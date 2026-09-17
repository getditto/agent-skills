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

# Serialise against another run sharing this .build directory. Two concurrent
# swift/xcodebuild invocations here produce confusing failures — "build.db: database is
# locked", and dlopen crashes from a half-written framework — that look like SDK bugs.
#
# `mkdir` rather than `flock`: flock is not present on macOS, where this fixture runs,
# so a flock-based guard would be a silent no-op on the only platform that needs it.
acquire_build_lock() {
  local lock="$FIXTURE_DIR/.build.lock" waited=0
  until mkdir "$lock" 2>/dev/null; do
    if [[ $waited -ge 600 ]]; then
      echo "another run has held $lock for 10 minutes; remove it if that run is gone" >&2
      exit 1
    fi
    # `${lock}`, braced: bash absorbs the following multi-byte character into the
    # variable name otherwise, and `set -u` then reports it as unbound.
    [[ $waited -eq 0 ]] && echo "waiting for another run to release ${lock}" >&2
    sleep 2
    waited=$((waited + 2))
  done
  # Expand the path NOW: `lock` is a local, so a single-quoted trap would reference an
  # unbound variable by the time it runs (and `set -u` makes that fatal).
  trap "rmdir '$lock' 2>/dev/null || true" EXIT
}
acquire_build_lock

build_for() {
  local version="$1" label="$2" destination="$3"
  local log=".build/xcodebuild-$version-${label// /-}.log"
  echo "--- $version : $label"
  # A per-version derived-data path: Xcode caches the resolved package graph and the
  # built module, and reusing one path across version pins fails with
  # "cannot load underlying module for 'DittoSwift'".
  # SwiftPM names the whole-package scheme "<Package>-Package" once the package has
  # more than one executable product.
  DITTO_SWIFT_VERSION="$version" xcodebuild \
    -scheme DittoSwiftSkillTests-Package \
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
    --all) VERSIONS=(4.14.6 5.0.3 5.1.0) ;;
    *) VERSIONS+=("$arg") ;;
  esac
done
[[ ${#VERSIONS[@]} -eq 0 ]] && VERSIONS=(5.1.0)

for version in "${VERSIONS[@]}"; do
  run_one "$version"
done
