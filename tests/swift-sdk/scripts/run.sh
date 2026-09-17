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

if [[ -f "$REPO_ROOT/.env" ]]; then
  # Environment variables already set take precedence, matching tests/lib/load-env.mjs.
  # Split on the FIRST "=" only, and never with IFS: base64 license tokens end in "=",
  # which `IFS== read` silently strips as a trailing delimiter.
  #
  # Surrounding quotes and leading whitespace are stripped, matching Node's
  # `process.loadEnvFile`. This is NOT full parity: unlike Node, a trailing ` # comment`
  # is kept as part of the value, and lowercase keys are ignored. Keep values in `.env`
  # unquoted and uncommented.
  while read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] && continue
    value="${value#"${value%%[![:space:]]*}"}"
    if [[ "$value" == \"*\" && ${#value} -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && ${#value} -ge 2 ]]; then
      value="${value:1:${#value}-2}"
    fi
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

  # A stale build directory keeps the previous version's framework, which produces
  # either a wrong-version run or a dlopen failure. Clearing the build products is
  # enough to force a relink; the downloaded artifacts are deliberately kept (they are
  # ~100 MB per version) and the pin is verified explicitly below instead.
  rm -rf .build/out Package.resolved

  swift build --build-tests
  local bin
  bin="$(swift build --show-bin-path)"

  # Prove the framework that was linked is the one we asked for, rather than a stale
  # artifact from a previous leg. `SwiftSDKSkillTests` also asserts this at runtime
  # (`the build is pinned to the version it claims`), but failing here names the cause.
  # EVERY resolved artifact must carry the requested version — 4.14.x resolves two
  # (DittoObjC and DittoSwift), so an any-match would accept a half-stale graph. An
  # unreadable state file is a hard failure, not a silently disabled guard.
  if ! python3 - "$version" <<'PYEOF'
import json, sys

version = sys.argv[1]
try:
    with open(".build/workspace-state.json") as handle:
        state = json.load(handle)
except (OSError, ValueError) as error:
    sys.exit(f"Cannot read .build/workspace-state.json to verify the pin: {error}")

urls = [
    artifact.get("source", {}).get("url", "")
    for artifact in state.get("object", {}).get("artifacts", [])
    if artifact.get("packageRef", {}).get("identity") == "dittoswiftpackage"
]
if not urls:
    sys.exit("No dittoswiftpackage artifacts resolved; cannot verify the pin.")

stale = [url for url in urls if f"/{version}/" not in url]
if stale:
    sys.exit(
        "Resolved artifacts do not all match the requested version "
        f"{version}:\n  " + "\n  ".join(stale)
    )
PYEOF
  then
    echo "Remove tests/swift-sdk/.build and retry." >&2
    return 1
  fi

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
    local app_output
    if [[ "$offline" == "yes" ]]; then
      app_output="$(env -u NO_COLOR -u DITTO_URL -u DITTO_TOKEN DYLD_FRAMEWORK_PATH="$bin" "$bin/MinimalApp" 2>&1 | tee /dev/stderr)"
    else
      app_output="$(env -u NO_COLOR DYLD_FRAMEWORK_PATH="$bin" "$bin/MinimalApp" 2>&1 | tee /dev/stderr)"
    fi

    # Exit code alone is not enough: the program would exit 0 having observed nothing.
    for expected in "Ditto $version opened at" "observed 1 car(s): Toyota" "done"; do
      if ! grep -qF "$expected" <<<"$app_output"; then
        echo "MinimalApp output did not contain: $expected" >&2
        return 1
      fi
    done
    echo "--- MinimalApp output verified ---"
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
