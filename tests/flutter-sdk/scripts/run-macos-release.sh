#!/bin/bash
#
# Build minimal_app for macOS in release mode, run the built app, and check the
# transcript it prints on stdout.
#
#   tests/flutter-sdk/scripts/run-macos-release.sh <line>
#   tests/flutter-sdk/scripts/run-macos-release.sh 5.2
#
# Release builds use macos/Runner/Release.entitlements, which debug runs never
# exercise. The app (lib/main.dart) runs the published program with the SDK default
# persistence directory and prints each transcript line as `transcript: <line>`.
#
# The license reaches Flutter only through a mode-600 --dart-define-from-file file,
# deleted on exit, and the release build embeds it: the build output is deleted on
# exit too. Never upload or cache the .app. The log
# (tests/flutter-sdk/run-minimal_app-macos-release-<line>.log, gitignored) is checked
# for the license before the script exits.
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
cleanup() {
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null || true
  [[ -n "$DEFINES_FILE" ]] && rm -f "$DEFINES_FILE"
  # The release build embeds the license.
  rm -rf "$WORKDIR/build/macos" "$WORKDIR/.dart_tool/flutter_build"
}
trap cleanup EXIT

DEFINES_FILE="$(umask 077 && mktemp "${TMPDIR:-/tmp}/ditto-defines.XXXXXX")"
DITTO_VERSION="$PIN" "$PYTHON" - "$DEFINES_FILE" <<'EOF'
import json, os, sys
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump({"DITTO_LICENSE": os.environ["DITTO_OFFLINE_LICENSE"],
               "DITTO_VERSION": os.environ["DITTO_VERSION"], "DITTO_PLATFORM": "macos"}, output)
EOF

{
  echo "== minimal_app macOS release, ditto_live $PIN ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "== $(cd "$WORKDIR" && "${FLUTTER_CMD[@]}" --version 2>&1 | sed -n 1p)"
  echo "== defines: DITTO_VERSION=$PIN DITTO_PLATFORM=macos DITTO_LICENSE=<redacted>"
  (cd "$WORKDIR" && "${FLUTTER_CMD[@]}" build macos --release --dart-define-from-file="$DEFINES_FILE")
} 2>&1 | tee "$LOG"

APP="$(find "$WORKDIR/build/macos/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)"
BINARY="$APP/Contents/MacOS/$(defaults read "$APP/Contents/Info" CFBundleExecutable)"
echo "== running $BINARY" | tee -a "$LOG"
APP_OUT="$(mktemp "${TMPDIR:-/tmp}/release-app.XXXXXX")"
# Without the DITTO_* variables of this shell: Ditto reads DITTO_* from the process
# environment as system parameters, and the app gets the license from its defines.
UNSET=()
while read -r name; do UNSET+=(-u "$name"); done < <(env | sed -n 's/^\(DITTO_[A-Za-z0-9_]*\)=.*/\1/p')
env ${UNSET[@]+"${UNSET[@]}"} "$BINARY" >"$APP_OUT" 2>&1 &
APP_PID=$!
deadline=$((SECONDS + ${RELEASE_APP_TIMEOUT:-120}))
while (( SECONDS < deadline )) && kill -0 "$APP_PID" 2>/dev/null; do
  grep -q -e 'transcript: closed:' -e 'transcript: error:' "$APP_OUT" && break
  sleep 1
done
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""
cat "$APP_OUT" >>"$LOG"
rm -f "$APP_OUT"

if grep -qF -- "$DITTO_OFFLINE_LICENSE" "$LOG"; then
  rm -f "$LOG"
  echo "the license appeared in the app output; log deleted" >&2
  exit 1
fi
# The engine prefixes Dart's print output with "flutter: ".
TRANSCRIPT="$(sed -n 's/^\(flutter: \)\{0,1\}transcript: /transcript: /p' "$LOG")"
printf '%s\n' "$TRANSCRIPT" | sed 's/^/  /'
status=0
for expected in 'transcript: observer: 1 car(s)' 'transcript: read-back make: Toyota' \
  "transcript: SDK version: $PIN" 'transcript: platform: macos' 'transcript: closed: true'; do
  if ! printf '%s\n' "$TRANSCRIPT" | grep -qxF -- "$expected"; then
    echo "missing: $expected" | tee -a "$LOG" >&2
    status=1
  fi
done
echo "== exit $status" | tee -a "$LOG"
exit "$status"
