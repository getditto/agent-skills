#!/bin/bash
#
# Executes the cross-version persistence claims in
# ../../skills/swift-sdk/references/versions.md:
#
#   * data written by 4.14.6 is readable by 5.0.3 and 5.1.0 (upgrade)
#   * data written by 5.1.0 is readable by 5.0.3 and 4.14.6 (documented rollback path)
#   * an upgrading app that never set `persistenceDirectory` still finds its v4
#     database through the v5 legacy-path fallback
#
# Each leg builds the PersistenceProbe executable at one version pin and runs it
# against a shared directory.
#
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$FIXTURE_DIR/../.." && pwd)"
cd "$FIXTURE_DIR"

if [[ -f "$REPO_ROOT/.env" ]]; then
  while read -r line; do
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] && continue
    export "$key=$value"
  done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$REPO_ROOT/.env" || true)
fi

if [[ -z "${DITTO_OFFLINE_LICENSE:-}" ]]; then
  echo "DITTO_OFFLINE_LICENSE is not set." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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
  env -u NO_COLOR DYLD_FRAMEWORK_PATH="$bin" "$bin/PersistenceProbe" "$@" 2>/dev/null
}

banner() { echo; echo "### $*"; }

banner "upgrade: 4.14.6 writes, 5.0.3 and 5.1.0 read (explicit directory)"
UPGRADE_DIR="$WORK/upgrade"
probe 4.14.6 write upgrade-1 "$UPGRADE_DIR"
probe 5.0.3  read  upgrade-1 "$UPGRADE_DIR"
probe 5.1.0  read  upgrade-1 "$UPGRADE_DIR"

banner "rollback: 5.1.0 writes, 5.0.3 then 4.14.6 read (documented downgrade route)"
ROLLBACK_DIR="$WORK/rollback"
probe 5.1.0  write rollback-1 "$ROLLBACK_DIR"
probe 5.0.3  read  rollback-1 "$ROLLBACK_DIR"
probe 4.14.6 read  rollback-1 "$ROLLBACK_DIR"

banner "default directory: 4.14.6 Ditto.open writes with no persistenceDirectory, 5.1.0 reads"
# CFFIXED_USER_HOME redirects Foundation's home-relative directories, so the default
# path is exercised without touching the real ~/Library.
export CFFIXED_USER_HOME="$WORK/home"
mkdir -p "$CFFIXED_USER_HOME/Library/Application Support" "$CFFIXED_USER_HOME/Documents"
probe 4.14.6 write default-1
probe 5.1.0  read  default-1

banner "legacy fallback: 4.14.6 Ditto(identity:) writes to <Documents>/ditto, 5.1.0 finds it"
export CFFIXED_USER_HOME="$WORK/legacy-home"
mkdir -p "$CFFIXED_USER_HOME/Library/Application Support" "$CFFIXED_USER_HOME/Documents"
probe 4.14.6 legacy-write legacy-1
probe 5.1.0  read         legacy-1
