#!/bin/bash
#
# Run a Flutter fixture's integration tests against one ditto_live line on one device.
#
#   tests/flutter-sdk/scripts/run-fixture.sh <fixture> <device> <line> <target>...
#   tests/flutter-sdk/scripts/run-fixture.sh minimal_app macos 5.2 integration_test/minimal_app_test.dart
#   tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 integration_test/minimal_app_test.dart
#
# <line> is a key of "lines" in tests/flutter-sdk/versions.json. use-version.py copies
# the fixture into a private (mode 0700) per-user directory under the system temp
# directory and pins ditto_live there; the committed fixture is never modified.
#
# Native devices run `flutter test <target> -d <device>`. `chrome` runs
# `flutter drive --driver=test_driver/integration_test.dart --target=<target> -d chrome
# --headless`, which needs a chromedriver matching the local Chrome listening on
# port 4444. If nothing listens there, this script starts $CHROMEDRIVER (default:
# `chromedriver` on PATH) and stops it on exit. Other web devices (edge, web-server)
# are rejected.
#
# Reads DITTO_OFFLINE_LICENSE from the environment, else from the gitignored repo-root
# .env. The defines (DITTO_LICENSE, DITTO_VERSION = the pin, DITTO_PLATFORM = the
# expected Ditto.currentPlatform.name, and PROBE_DEFAULT_LOGGING and MIGRATION_PHASE
# when those variables are set) go to Flutter through --dart-define-from-file: a mode-600 temporary file that
# is deleted on exit, so the license never appears in a process argument list.
# Compiled builds embed every define, so never cache or upload the fixture copy or its
# build/ directory.
#
# Each flutter invocation is bounded by FIXTURE_TIMEOUT seconds (default 1800) when a
# GNU `timeout` (or Homebrew's `gtimeout`) is available. Each target's output is copied to
# tests/flutter-sdk/run-<fixture>-<device>-<line>-<target>.log (gitignored).
#
# Environment: FLUTTER (a flutter executable; default `fvm flutter`), PYTHON (default
# python3), CHROMEDRIVER, DITTO_PLATFORM (required for phone and simulator device IDs),
# FIXTURE_TIMEOUT, FIXTURE_RETRIES (default 0: re-runs of a target the timeout stopped
# (exit 124) with the known iOS Simulator debug-connection failure; nothing else), FIXTURE_LOG_DIR (default
# tests/flutter-sdk), PROBE_DEFAULT_LOGGING,
# MIGRATION_PHASE (wipe, write or read; integration_test/migration/, and added to the
# log name).
#
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HARNESS/../.." && pwd)"
PYTHON="${PYTHON:-python3}"

if [[ $# -lt 4 ]]; then
  sed -n '3,7p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
FIXTURE="$1"
DEVICE="$2"
LINE="$3"
shift 3

if [[ -f "$REPO_ROOT/.env" ]]; then
  # Same parser as tests/swift-sdk/scripts/run.sh: environment variables already set
  # take precedence; split on the FIRST "=" only (base64 tokens end in "="); strip
  # surrounding quotes, leading whitespace and a Windows line ending. Keep values
  # unquoted and uncommented.
  while read -r line; do
    line="${line%$'\r'}"
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

# The `Ditto.currentPlatform.name` the run must report (SupportedPlatform values in
# ditto_live: android, ios, linux, macos, web, windows). Phone and simulator device
# IDs carry no platform, so set DITTO_PLATFORM for those.
if [[ "$DEVICE" == "edge" || "$DEVICE" == "web-server" ]]; then
  echo "Device '$DEVICE' is not supported; web runs use chrome (flutter drive)." >&2
  exit 2
fi
if [[ -z "${DITTO_PLATFORM:-}" ]]; then
  case "$DEVICE" in
    macos | linux | windows) DITTO_PLATFORM="$DEVICE" ;;
    chrome) DITTO_PLATFORM=web ;;
    emulator-*) DITTO_PLATFORM=android ;;
    *)
      echo "Cannot tell the platform of device '$DEVICE'; set DITTO_PLATFORM (android or ios)." >&2
      exit 2
      ;;
  esac
fi
export DITTO_PLATFORM

# `tr -d '\r'`: Python on Windows prints CRLF, which Git Bash keeps in $(...).
PIN="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["lines"][sys.argv[2]])' \
  "$HARNESS/versions.json" "$LINE" | tr -d '\r')"
export DITTO_VERSION="$PIN"

if [[ -n "${FLUTTER:-}" ]]; then
  FLUTTER_CMD=("$FLUTTER")
else
  FLUTTER_CMD=(fvm flutter)
fi

WORKDIR="$("$PYTHON" "$HARNESS/scripts/use-version.py" "$FIXTURE" "$LINE" | tail -1 | tr -d '\r')"

CHROMEDRIVER_PID=""
DEFINES_FILE=""
cleanup() {
  if [[ -n "$DEFINES_FILE" ]]; then
    rm -f "$DEFINES_FILE"
  fi
  if [[ -n "$CHROMEDRIVER_PID" ]]; then
    kill "$CHROMEDRIVER_PID" 2>/dev/null || true
  fi
  # The chrome leg's debug web build leaves compiled JavaScript with every define
  # (the license included) in the fixture copy; delete it.
  # Flutter's incremental-compile caches (build/*.cache.dill.track.dill) embed it too.
  if [[ "$DEVICE" == "chrome" && -n "$WORKDIR" ]]; then
    rm -rf "$WORKDIR/.dart_tool/flutter_build" "$WORKDIR/build/web"
    rm -f "$WORKDIR"/build/*.cache.dill.track.dill
  fi
}
trap cleanup EXIT

# The defines file: created mode 600 (umask 077) and written by Python from the
# environment, so the license is never a command-line argument.
DEFINES_FILE="$(umask 077 && mktemp "${TMPDIR:-/tmp}/ditto-defines.XXXXXX")"
"$PYTHON" - "$DEFINES_FILE" <<'EOF'
import json, os, sys
defines = {name: os.environ[name] for name in ("DITTO_VERSION", "DITTO_PLATFORM")}
defines["DITTO_LICENSE"] = os.environ["DITTO_OFFLINE_LICENSE"]
# PROBE_DEFAULT_LOGGING=true keeps Ditto logging at its default in the probe harness
# (integration_test/probes/harness.dart), which otherwise turns it off.
if os.environ.get("PROBE_DEFAULT_LOGGING"):
    defines["PROBE_DEFAULT_LOGGING"] = os.environ["PROBE_DEFAULT_LOGGING"]
# MIGRATION_PHASE selects the phase of integration_test/migration/migrate_default_dir_test.dart.
if os.environ.get("MIGRATION_PHASE"):
    defines["MIGRATION_PHASE"] = os.environ["MIGRATION_PHASE"]
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(defines, output)
EOF
# Git Bash on Windows: pass a C:/... path, so neither MSYS argument conversion nor
# the native flutter tool has to interpret a /tmp/... one.
DEFINES_ARG="$DEFINES_FILE"
if command -v cygpath >/dev/null 2>&1; then
  DEFINES_ARG="$(cygpath -m "$DEFINES_FILE")"
fi
DEFINES=(--dart-define-from-file="$DEFINES_ARG")

# The defines file now holds everything the app needs. Ditto reads DITTO_* variables
# from its process environment as system parameters, so flutter and the app it
# launches run without any of them (the license, and .env keys such as DITTO_TOKEN).
CLEAN_ENV=(env)
while read -r name; do
  CLEAN_ENV+=(-u "$name")
done < <(env | sed -n 's/^\(DITTO_[A-Za-z0-9_]*\)=.*/\1/p')
PUBLIC_DEFINES="DITTO_VERSION=$PIN DITTO_PLATFORM=$DITTO_PLATFORM PROBE_DEFAULT_LOGGING=${PROBE_DEFAULT_LOGGING:-unset}"
PHASE_SUFFIX=""
TEST_FLAGS=()
if [[ -n "${MIGRATION_PHASE:-}" ]]; then
  PUBLIC_DEFINES="$PUBLIC_DEFINES MIGRATION_PHASE=$MIGRATION_PHASE"
  PHASE_SUFFIX="-$(printf '%s' "$MIGRATION_PHASE" | tr -c 'A-Za-z0-9._-' '_')"
  # `flutter test` uninstalls the app from a phone or simulator after the run,
  # which deletes its data container; the migration phases need it kept.
  TEST_FLAGS=(--no-uninstall)
fi

FIXTURE_TIMEOUT="${FIXTURE_TIMEOUT:-1800}"
BOUND=()
# GNU timeout only: on Windows, PATH can resolve `timeout` to System32's wait command.
# Homebrew's coreutils installs it as gtimeout on macOS.
if timeout --version >/dev/null 2>&1; then
  BOUND=(timeout -k 30 "$FIXTURE_TIMEOUT")
elif gtimeout --version >/dev/null 2>&1; then
  BOUND=(gtimeout -k 30 "$FIXTURE_TIMEOUT")
else
  echo "warning: no \`timeout\` command; flutter runs are not time-bounded" >&2
fi

if [[ "$DEVICE" == "chrome" ]] && ! nc -z 127.0.0.1 4444 2>/dev/null; then
  "${CHROMEDRIVER:-chromedriver}" --port=4444 >/dev/null 2>&1 &
  CHROMEDRIVER_PID=$!
  for _ in $(seq 1 50); do
    nc -z 127.0.0.1 4444 2>/dev/null && break
    kill -0 "$CHROMEDRIVER_PID" 2>/dev/null || break
    sleep 0.2
  done
fi
# Fail here, not later at "Unable to start a WebDriver session": whatever listens on
# :4444 (started above or already running) must answer ChromeDriver's /status.
if [[ "$DEVICE" == "chrome" ]]; then
  ready=""
  for _ in $(seq 1 10); do
    status_json="$(curl -sf --max-time 5 http://127.0.0.1:4444/status 2>/dev/null || true)"
    if [[ "$(printf '%s' "$status_json" | tr -d ' \n')" == *'"ready":true'* ]]; then
      ready=1
      break
    fi
    sleep 0.2
  done
  if [[ -z "$ready" ]]; then
    echo "ChromeDriver did not come up on 127.0.0.1:4444 (CHROMEDRIVER=${CHROMEDRIVER:-chromedriver})." >&2
    echo "Install one matching the local Chrome; see tests/flutter-sdk/README.md, Running fixtures." >&2
    exit 1
  fi
fi

FLUTTER_VERSION="$(cd "$WORKDIR" && "${CLEAN_ENV[@]}" "${FLUTTER_CMD[@]}" --version 2>&1 | sed -n 1p | tr -d '\r')"
SAFE_DEVICE="$(printf '%s' "$DEVICE" | tr -c 'A-Za-z0-9._-' '_')"

status=0
for target in "$@"; do
  slug="$(printf '%s' "${target#integration_test/}" | sed 's/\.dart$//' | tr -c 'A-Za-z0-9._-' '_')"
  log="${FIXTURE_LOG_DIR:-$HARNESS}/run-$FIXTURE-$SAFE_DEVICE-$LINE-$slug$PHASE_SUFFIX.log"
  attempt=0
  attempt_log="$(mktemp "${TMPDIR:-/tmp}/run-fixture-attempt.XXXXXX")"
  : >"$log"
  while :; do
    attempt=$((attempt + 1))
    target_status=0
    {
      echo "== $FIXTURE on $DEVICE, ditto_live $PIN ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
      echo "== $FLUTTER_VERSION"
      echo "== defines: $PUBLIC_DEFINES DITTO_LICENSE=<redacted>"
      echo "== $target (attempt $attempt)"
      if [[ "$DEVICE" == "chrome" ]]; then
        (cd "$WORKDIR" && ${BOUND[@]+"${BOUND[@]}"} "${CLEAN_ENV[@]}" "${FLUTTER_CMD[@]}" drive \
          --driver=test_driver/integration_test.dart --target="$target" -d chrome --headless "${DEFINES[@]}")
      else
        (cd "$WORKDIR" && ${BOUND[@]+"${BOUND[@]}"} "${CLEAN_ENV[@]}" "${FLUTTER_CMD[@]}" test "$target" -d "$DEVICE" \
          ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"} "${DEFINES[@]}")
      fi
    } 2>&1 | tee "$attempt_log" || target_status=$?
    cat "$attempt_log" >>"$log"
    # FIXTURE_RETRIES re-runs a target only for the known iOS Simulator debug-connection
    # failure: stopped by the timeout (exit 124) after either "The log reader failed
    # unexpectedly", or a hang after "Xcode build done" before any test output. Any
    # other failure or timeout is never retried.
    known=""
    if grep -q 'The log reader failed unexpectedly' "$attempt_log"; then
      known="The log reader failed unexpectedly"
    elif grep -q 'Xcode build done' "$attempt_log" && ! grep -Eq '^[0-9]{2}:[0-9]{2} \+[0-9]' "$attempt_log"; then
      known="hang after Xcode build done, no test output"
    fi
    if [[ "$target_status" -eq 124 && -n "$known" && "$attempt" -le "${FIXTURE_RETRIES:-0}" ]]; then
      message="$target: timed out (exit 124) with the known iOS Simulator failure ($known); retrying (FIXTURE_RETRIES=${FIXTURE_RETRIES})"
      echo "== $message" | tee -a "$log"
      [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::warning::$message"
      continue
    fi
    break
  done
  rm -f "$attempt_log"
  echo "== $target: exit $target_status" | tee -a "$log"
  if [[ "$target_status" -ne 0 ]]; then
    status="$target_status"
  fi
done
echo "== exit $status"
exit "$status"
