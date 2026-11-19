#!/bin/bash
#
# Build minimal_app for macOS in release mode, run the built app, and check the
# transcript it prints on stdout.
#
#   tests/flutter-sdk/scripts/run-macos-release.sh <line>
#   tests/flutter-sdk/scripts/run-macos-release.sh 5.2
#
# Release builds use macos/Runner/Release.entitlements, which debug runs never
# exercise. Two builds: lib/main.dart runs the published program with the SDK default
# persistence directory, and integration_test/release/two_peer_app.dart syncs two
# instances over TCP on 127.0.0.1, which a sandboxed app can do only with the
# network.server and network.client entitlements. Each prints `transcript: <line>`.
#
# The license is given to `flutter build` only through a mode-600
# --dart-define-from-file file, deleted on exit; flutter and the app run without this
# shell's DITTO_* variables. The flutter tool forwards the defines to its own build
# steps (README, Running fixtures), and the release build embeds them: the whole fixture copy (build
# output, .dart_tool and generated config) is deleted on exit too. Never upload or cache the .app. The log
# (tests/flutter-sdk/run-minimal_app-macos-release-<line>.log, gitignored) is checked
# for the license before any of it is printed. The check reads the license from the
# environment, never from an argument list.
#
# Environment: as run-fixture.sh (DITTO_OFFLINE_LICENSE or the repo-root .env, FLUTTER,
# PYTHON, FIXTURE_LOG_DIR); RELEASE_APP_TIMEOUT (seconds, default 120).
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HARNESS/../.." && pwd)"
PYTHON="${PYTHON:-python3}"
if [[ $# -ne 1 ]]; then
  sed -n '3,7p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
LINE="$1"

if [[ -z "${DITTO_OFFLINE_LICENSE:-}" && -f "$REPO_ROOT/.env" ]]; then
  DITTO_OFFLINE_LICENSE="$(sed -n 's/^DITTO_OFFLINE_LICENSE=//p' "$REPO_ROOT/.env" | tail -1 | tr -d '\r')"
  DITTO_OFFLINE_LICENSE="${DITTO_OFFLINE_LICENSE#\"}"
  DITTO_OFFLINE_LICENSE="${DITTO_OFFLINE_LICENSE%\"}"
fi
if [[ -z "${DITTO_OFFLINE_LICENSE:-}" ]]; then
  echo "DITTO_OFFLINE_LICENSE is not set. Copy .env-sample to .env at the repo root." >&2
  exit 1
fi
export DITTO_OFFLINE_LICENSE

PIN="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["lines"][sys.argv[2]])' \
  "$HARNESS/versions.json" "$LINE" | tr -d '\r')"
if [[ -n "${FLUTTER:-}" ]]; then FLUTTER_CMD=("$FLUTTER"); else FLUTTER_CMD=(fvm flutter); fi
WORKDIR="$("$PYTHON" "$HARNESS/scripts/use-version.py" minimal_app "$LINE" | tail -1 | tr -d '\r')"
LOG="${FIXTURE_LOG_DIR:-$HARNESS}/run-minimal_app-macos-release-$LINE.log"

DEFINES_FILE=""
APP_PID=""
FIXTURE=minimal_app
# Every build of the fixture copy embeds the defines, the license included: build/,
# .dart_tool/, and the generated platform config (DART_DEFINES in
# macos/Flutter/ephemeral/*.xcconfig and ios/Flutter/Generated.xcconfig). So the
# whole copy is deleted when the run ends, on success, failure or interrupt; the
# next run copies and builds it from scratch.
remove_fixture_copy() {
  [[ -n "$WORKDIR" ]] || return 0
  local normalized="${WORKDIR//\\//}"
  case "$normalized" in
    */flutter-fixture-*/"$LINE"/"$FIXTURE") ;;
    *)
      echo "not deleting $WORKDIR: not a use-version.py fixture copy" >&2
      return 0
      ;;
  esac
  if ! rm -rf "$WORKDIR" 2>/dev/null; then
    # Windows can hold a just-exited app's files open for a moment.
    sleep 5
    rm -rf "$WORKDIR" || echo "::warning::could not delete the fixture copy $WORKDIR, which embeds the license" >&2
  fi
}
cleanup() {
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null || true
  [[ -n "$DEFINES_FILE" ]] && rm -f "$DEFINES_FILE"
  remove_fixture_copy
}
trap cleanup EXIT

DEFINES_FILE="$(umask 077 && mktemp "${TMPDIR:-/tmp}/ditto-defines.XXXXXX")"
DITTO_VERSION="$PIN" "$PYTHON" - "$DEFINES_FILE" <<'EOF'
import json, os, sys
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump({"DITTO_LICENSE": os.environ["DITTO_OFFLINE_LICENSE"],
               "DITTO_VERSION": os.environ["DITTO_VERSION"], "DITTO_PLATFORM": "macos"}, output)
EOF

# Deletes the log and fails when it contains the license. grep reads the license
# as its pattern file from a pipe, so the value never reaches an argument list.
refuse_license_in_log() {
  if grep -qF -f <(printenv DITTO_OFFLINE_LICENSE) "$LOG"; then
    rm -f "$LOG"
    echo "the license appeared in the $1 output; log deleted" >&2
    exit 1
  fi
}

# flutter and the app run without this shell's DITTO_* variables: Ditto reads DITTO_*
# from the process environment as system parameters, and the build and the app get the
# license from the defines file only.
UNSET=()
while read -r name; do UNSET+=(-u "$name"); done < <(env | sed -n 's/^\(DITTO_[A-Za-z0-9_]*\)=.*/\1/p')
CLEAN_ENV=(env ${UNSET[@]+"${UNSET[@]}"})

# build_and_run <label> <flutter build arguments>...: builds the release app, runs
# its executable until it prints `transcript: closed:` or `transcript: error:`, and
# leaves this run's transcript lines in $TRANSCRIPT. Build output goes to the log
# only; it is printed after the license check.
build_and_run() {
  local label="$1"
  shift
  local build_status=0 section
  section="$(mktemp "${TMPDIR:-/tmp}/release-build.XXXXXX")"
  {
    echo "== minimal_app macOS release ($label), ditto_live $PIN ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo "== $(cd "$WORKDIR" && "${CLEAN_ENV[@]}" "${FLUTTER_CMD[@]}" --version 2>&1 | sed -n 1p)"
    echo "== defines: DITTO_VERSION=$PIN DITTO_PLATFORM=macos DITTO_LICENSE=<redacted>"
    (cd "$WORKDIR" && "${CLEAN_ENV[@]}" "${FLUTTER_CMD[@]}" build macos --release \
      --dart-define-from-file="$DEFINES_FILE" "$@")
  } >"$section" 2>&1 || build_status=$?
  cat "$section" >>"$LOG"
  refuse_license_in_log build
  cat "$section"
  rm -f "$section"
  if (( build_status != 0 )); then
    echo "== build failed (exit $build_status)" >&2
    exit "$build_status"
  fi

  local app binary app_out deadline
  app="$(find "$WORKDIR/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)"
  binary="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable)"
  echo "== running $binary ($label)" | tee -a "$LOG"
  app_out="$(mktemp "${TMPDIR:-/tmp}/release-app.XXXXXX")"
  "${CLEAN_ENV[@]}" "$binary" >"$app_out" 2>&1 &
  APP_PID=$!
  deadline=$((SECONDS + ${RELEASE_APP_TIMEOUT:-120}))
  while (( SECONDS < deadline )) && kill -0 "$APP_PID" 2>/dev/null; do
    grep -q -e 'transcript: closed:' -e 'transcript: error:' "$app_out" && break
    sleep 1
  done
  # The app may be exiting on its own; give it a moment before killing it.
  sleep 1
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
  cat "$app_out" >>"$LOG"
  # The engine prefixes Dart's print output with "flutter: ".
  TRANSCRIPT="$(sed -n 's/^\(flutter: \)\{0,1\}transcript: /transcript: /p' "$app_out")"
  rm -f "$app_out"
  refuse_license_in_log app
  printf '%s\n' "$TRANSCRIPT" | sed 's/^/  /'
}

status=0
expect_lines() {
  local expected
  for expected in "$@"; do
    if ! printf '%s\n' "$TRANSCRIPT" | grep -qxF -- "$expected"; then
      echo "missing: $expected" | tee -a "$LOG" >&2
      status=1
    fi
  done
}

: >"$LOG"
# 1. The published program (lib/main.dart), with the SDK default directory.
build_and_run "lib/main.dart"
expect_lines 'transcript: observer: 1 car(s)' 'transcript: read-back make: Toyota' \
  "transcript: SDK version: $PIN" 'transcript: platform: macos' 'transcript: closed: true'

# 2. Two instances in the app syncing over TCP loopback: the sandboxed release app can
# listen and connect only with the network entitlements of Release.entitlements.
build_and_run "two peers over loopback" -t integration_test/release/two_peer_app.dart
expect_lines 'transcript: two-peer sync: car-from-listener' 'transcript: closed: true'

echo "== exit $status" | tee -a "$LOG"
exit "$status"
