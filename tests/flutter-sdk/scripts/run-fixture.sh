#!/bin/bash
#
# Run a Flutter fixture's integration tests against one ditto_live line on one device.
#
#   tests/flutter-sdk/scripts/run-fixture.sh <fixture> <device> <line> <target>...
#   tests/flutter-sdk/scripts/run-fixture.sh minimal_app macos 5.2 integration_test/minimal_app_test.dart
#   tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 integration_test/minimal_app_test.dart
#
# <line> is a key of "lines" in tests/flutter-sdk/versions.json. use-version.py copies
# the fixture to $TMPDIR/flutter-fixture-<line>/ and pins ditto_live there; the
# committed fixture is never modified.
#
# Native devices run `flutter test <target> -d <device>`. `chrome` runs
# `flutter drive --driver=test_driver/integration_test.dart --target=<target> -d chrome
# --headless`, which needs a chromedriver matching the local Chrome listening on
# port 4444. If nothing listens there, this script starts $CHROMEDRIVER (default:
# `chromedriver` on PATH) and stops it on exit.
#
# Reads DITTO_OFFLINE_LICENSE from the environment, else from the gitignored repo-root
# .env, and passes it as --dart-define=DITTO_LICENSE. Web builds embed defines, so
# never publish the web build output. Output is copied to
# tests/flutter-sdk/run-<device>-<line>.log (gitignored).
#
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HARNESS/../.." && pwd)"

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
  # surrounding quotes and leading whitespace. Keep values unquoted and uncommented.
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

PIN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["lines"][sys.argv[2]])' \
  "$HARNESS/versions.json" "$LINE")"
LOG="$HARNESS/run-$DEVICE-$LINE.log"

if [[ -n "${FLUTTER:-}" ]]; then
  FLUTTER_CMD=("$FLUTTER")
else
  FLUTTER_CMD=(fvm flutter)
fi

WORKDIR="$(python3 "$HARNESS/scripts/use-version.py" "$FIXTURE" "$LINE" | tail -1)"

CHROMEDRIVER_PID=""
cleanup() {
  if [[ -n "$CHROMEDRIVER_PID" ]]; then
    kill "$CHROMEDRIVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "$DEVICE" == "chrome" ]] && ! nc -z 127.0.0.1 4444 2>/dev/null; then
  "${CHROMEDRIVER:-chromedriver}" --port=4444 >/dev/null 2>&1 &
  CHROMEDRIVER_PID=$!
  for _ in $(seq 1 50); do
    nc -z 127.0.0.1 4444 2>/dev/null && break
    sleep 0.2
  done
fi

DEFINES=(--dart-define=DITTO_LICENSE="$DITTO_OFFLINE_LICENSE" --dart-define=DITTO_VERSION="$PIN")

status=0
{
  echo "== $FIXTURE on $DEVICE, ditto_live $PIN ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  (cd "$WORKDIR" && "${FLUTTER_CMD[@]}" --version 2>&1 | head -1)
  for target in "$@"; do
    echo "== $target"
    if [[ "$DEVICE" == "chrome" ]]; then
      (cd "$WORKDIR" && "${FLUTTER_CMD[@]}" drive --driver=test_driver/integration_test.dart \
        --target="$target" -d chrome --headless "${DEFINES[@]}") || status=$?
    else
      (cd "$WORKDIR" && "${FLUTTER_CMD[@]}" test "$target" -d "$DEVICE" "${DEFINES[@]}") || status=$?
    fi
  done
  echo "== exit $status"
  exit "$status"
} 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
