#!/bin/bash
#
# Build and run the swift-sdk skill fixture against one Ditto version line.
#
#   ./scripts/run.sh 5.1.0            # tests only
#   ./scripts/run.sh 5.1.0 --app      # tests, then the minimal app (server mode if
#                                     # DITTO_URL/DITTO_TOKEN are set)
#   ./scripts/run.sh 5.1.0 --app --offline   # force the minimal app's offline mode
#   ./scripts/run.sh --all            # 4.14.6, 5.0.3 and 5.1.0 in sequence
#
# Reads DITTO_OFFLINE_LICENSE (required) and DITTO_DATABASE_ID / DITTO_URL /
# DITTO_TOKEN (optional) from the gitignored repo-root .env, unless already set in the
# environment. See ../../.env-sample.
#
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$FIXTURE_DIR/../.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  # Environment variables already set take precedence, matching tests/lib/load-env.mjs.
  # Split on the FIRST "=" only, and never with IFS: base64 license tokens end in "=",
  # which `IFS== read` silently strips as a trailing delimiter.
  while read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] && continue
    export "$key=$value"
  done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$REPO_ROOT/.env" || true)
fi

if [[ -z "${DITTO_OFFLINE_LICENSE:-}" ]]; then
  echo "DITTO_OFFLINE_LICENSE is not set. Copy .env-sample to .env at the repo root." >&2
  exit 1
fi

run_one() {
  local version="$1"
  local run_app="$2"
  local offline="$3"

  echo
  echo "=============================================================="
  echo "Ditto $version  —  $(sw_vers -productName) $(sw_vers -productVersion) $(uname -m), $(swift --version 2>/dev/null | head -1)"
  echo "=============================================================="

  cd "$FIXTURE_DIR"
  export DITTO_SWIFT_VERSION="$version"

  # A stale build directory would silently keep the previous version's framework.
  rm -rf .build/out

  swift build --build-tests
  local bin
  bin="$(swift build --show-bin-path)"

  # The published DittoSwift.xcframework ships unsigned, and SwiftPM copies it out of
  # the artifact cache without signing it. macOS refuses to load an unsigned library
  # into the test host, so ad-hoc sign every framework the build produced. Xcode app
  # targets do this automatically; only this command-line harness needs it.
  for framework in "$bin"/*.framework; do
    [[ -e "$framework" ]] || continue
    local name
    name="$(basename "$framework" .framework)"
    /usr/bin/codesign --force --sign - "$framework/Versions/A/$name"
  done

  # `swift test` exports NO_COLOR=1 into the test process and there is no flag to stop
  # it. Ditto's Rust core reads NO_COLOR as its `--disable-color` option, which accepts
  # only "true"/"false", so the value "1" panics the process before any test runs.
  # Driving SwiftPM's own test helper directly is what lets us clear the variable.
  # See ../../skills/swift-sdk/references/testing.md.
  local helper platform bundle
  helper="$(dirname "$(xcrun --find swift)")/../libexec/swift/pm/swiftpm-testing-helper"
  platform="$(xcrun --sdk macosx --show-sdk-platform-path)"
  bundle="$bin/SwiftSDKSkillTests.xctest/Contents/MacOS/SwiftSDKSkillTests"

  env -u NO_COLOR \
    DYLD_FRAMEWORK_PATH="$bin:$platform/Developer/Library/Frameworks" \
    DYLD_LIBRARY_PATH="$bin:$platform/Developer/usr/lib" \
    "$helper" --test-bundle-path "$bundle" "$bundle" --testing-library swift-testing

  if [[ "$run_app" == "yes" ]]; then
    echo
    echo "--- MinimalApp ---"
    if [[ "$offline" == "yes" ]]; then
      env -u NO_COLOR -u DITTO_URL -u DITTO_TOKEN DYLD_FRAMEWORK_PATH="$bin" "$bin/MinimalApp"
    else
      env -u NO_COLOR DYLD_FRAMEWORK_PATH="$bin" "$bin/MinimalApp"
    fi
  fi
}

RUN_APP="no"
OFFLINE="no"
VERSIONS=()
for arg in "$@"; do
  case "$arg" in
    --app) RUN_APP="yes" ;;
    --offline) OFFLINE="yes" ;;
    --all) VERSIONS=(4.14.6 5.0.3 5.1.0) ;;
    *) VERSIONS+=("$arg") ;;
  esac
done
[[ ${#VERSIONS[@]} -eq 0 ]] && VERSIONS=(5.1.0)

for version in "${VERSIONS[@]}"; do
  run_one "$version" "$RUN_APP" "$OFFLINE"
done
