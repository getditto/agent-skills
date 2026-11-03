#!/bin/bash
#
# Executes the cross-version persistence claims in
# ../../skills/swift-sdk/references/versions.md:
#
#   * data written by 4.14.6 is readable by 5.0.3, 5.1.0 and 5.2.0 (upgrade), both
#     chained and as direct pairs
#   * data written by 5.1.0 is readable by 5.0.3 and 4.14.6 (documented rollback path),
#     both chained and as a DIRECT 5.1.0 -> 4.14.6 downgrade with no intermediate 5.0.x
#   * data written by 5.2.0 is readable by 5.1.0, 5.0.3 and 4.14.6 — the newest
#     line down, chained and direct
#   * an upgrading app that never set `persistenceDirectory` still finds its v4
#     database through the v5 legacy-path fallback
#
# Each leg builds the PersistenceProbe executable at one version pin and runs it against
# a shared directory. `PersistenceProbe read` exits non-zero when the document or the
# index did not survive, and this script runs under `set -e`, so a leg that loses data
# fails the run.
#
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$FIXTURE_DIR/../.." && pwd)"
cd "$FIXTURE_DIR"

# Source from the computed absolute path: after `cd`, a relative BASH_SOURCE
# (e.g. `bash tests/swift-sdk/scripts/run.sh` from the repo root) resolves
# against the new working directory and fails.
. "$FIXTURE_DIR/scripts/lib/build-lock.sh"
acquire_build_lock

if [[ -f "$REPO_ROOT/.env" ]]; then
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
  echo "DITTO_OFFLINE_LICENSE is not set." >&2
  exit 1
fi

WORK="$(mktemp -d)"
# Replaces the build lock's own EXIT trap, so it has to release the lock too.
trap 'rm -rf "$WORK" "$FIXTURE_DIR/.build.lock"' EXIT

probe() {
  local version="$1"; shift
  rm -rf .build/out
  DITTO_SWIFT_VERSION="$version" swift build --product PersistenceProbe >/dev/null
  local bin
  bin="$(DITTO_SWIFT_VERSION="$version" swift build --product PersistenceProbe --show-bin-path)"
  for framework in "$bin"/*.framework; do
    [[ -e "$framework" ]] || continue
    local name
    name="$(basename "$framework" .framework)"
    /usr/bin/codesign --force --sign - "$framework/Versions/A/$name"
  done
  # stderr is kept: PersistenceProbe reports assertion failures there. `--expect-version`
  # makes the probe fail if a stale artifact means this leg is not running the SDK the
  # matrix thinks it is — otherwise a degenerate same-version pair looks identical to a
  # genuine cross-version one.
  env -u NO_COLOR DYLD_FRAMEWORK_PATH="$bin" "$bin/PersistenceProbe" "$@" \
    --expect-version "$version" \
    2> >(grep -vE '  (INFO|WARN|DEBUG|ERROR|TRACE) ' >&2)
}

banner() { echo; echo "### $*"; }

banner "upgrade: 4.14.6 writes, 5.0.3, 5.1.0 and 5.2.0 read (explicit directory)"
UPGRADE_DIR="$WORK/upgrade"
probe 4.14.6 write upgrade-1 "$UPGRADE_DIR"
probe 5.0.3  read  upgrade-1 "$UPGRADE_DIR"
probe 5.1.0  read  upgrade-1 "$UPGRADE_DIR"
probe 5.2.0 read upgrade-1 "$UPGRADE_DIR"

banner "rollback: 5.1.0 writes, 5.0.3 then 4.14.6 read (documented downgrade route)"
ROLLBACK_DIR="$WORK/rollback"
probe 5.1.0  write rollback-1 "$ROLLBACK_DIR"
probe 5.0.3  read  rollback-1 "$ROLLBACK_DIR"
probe 4.14.6 read  rollback-1 "$ROLLBACK_DIR"

banner "rollback: 5.2.0 writes, 5.1.0 then 5.0.3 then 4.14.6 read (newest line down)"
NEWEST_DOWN_DIR="$WORK/newest-down"
probe 5.2.0 write newest-down-1 "$NEWEST_DOWN_DIR"
probe 5.1.0        read  newest-down-1 "$NEWEST_DOWN_DIR"
probe 5.0.3        read  newest-down-1 "$NEWEST_DOWN_DIR"
probe 4.14.6       read  newest-down-1 "$NEWEST_DOWN_DIR"

# The chains above route every read through the adjacent version, which is exactly the
# step the published contract says reverts the 5.1 index format. These legs remove that
# step so each pair is tested directly.
banner "direct pairs: no intermediate version between writer and reader"
for pair in "4.14.6 5.1.0 direct-up" "5.1.0 4.14.6 direct-down" "4.14.6 5.0.3 direct-up-50" "5.1.0 5.0.3 direct-down-50" "4.14.6 5.2.0 direct-up-52" "5.2.0 5.1.0 direct-down-52"; do
  set -- $pair
  writer="$1"; reader="$2"; label="$3"
  dir="$WORK/$label"
  echo "  -- $writer writes, $reader reads"
  probe "$writer" write "$label" "$dir"
  probe "$reader" read  "$label" "$dir"
done

banner "default directory: 4.14.6 Ditto.open writes with no persistenceDirectory, 5.1.0 reads"
# CFFIXED_USER_HOME redirects Foundation's home-relative directories, so the default
# path is exercised without touching the real ~/Library.
export CFFIXED_USER_HOME="$WORK/home"
mkdir -p "$CFFIXED_USER_HOME/Library/Application Support" "$CFFIXED_USER_HOME/Documents"

# Capture the directory 4.14.6 resolved, then require 5.1.0 to resolve the SAME one.
# Without this the leg passes even if the defaults diverged, because v5's legacy-path
# fallback would find the v4 store anyway — so the claim "both versions reported the
# same absolute directory" would be unproven.
default_dir="$(probe 4.14.6 write default-1 | sed -n 's/^directory=//p')"
if [[ -z "$default_dir" ]]; then
  echo "could not capture the 4.14.6 default directory" >&2
  exit 1
fi
echo "  -- 4.14.6 resolved: $default_dir"
probe 5.1.0  read  default-1 --expect-directory "$default_dir"

banner "legacy fallback: 4.14.6 Ditto(identity:) writes to <Documents>/ditto, 5.1.0 finds it"
export CFFIXED_USER_HOME="$WORK/legacy-home"
mkdir -p "$CFFIXED_USER_HOME/Library/Application Support" "$CFFIXED_USER_HOME/Documents"
probe 4.14.6 legacy-write legacy-1
# The legacy initializer does not create an index, so do not require one here.
probe 5.1.0  read         legacy-1 --no-index
