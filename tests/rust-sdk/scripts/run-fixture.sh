#!/usr/bin/env bash
# Build, run and test tests/rust-sdk/minimal-app against one Ditto Rust SDK version.
#
#   tests/rust-sdk/scripts/run-fixture.sh [VERSION]     # default: the committed pin
#
# Works on a copy so the committed Cargo.toml/Cargo.lock stay at the baseline pin.
# DITTO_OFFLINE_LICENSE comes from the environment, else from the repo-root .env.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/../.." && pwd)"
version="${1:-}"

if [[ -z "${DITTO_OFFLINE_LICENSE:-}" && -f "$repo/.env" ]]; then
  DITTO_OFFLINE_LICENSE="$(grep -E '^DITTO_OFFLINE_LICENSE=' "$repo/.env" | head -1 | cut -d= -f2-)"
fi
if [[ -z "${DITTO_OFFLINE_LICENSE:-}" ]]; then
  echo "error: set DITTO_OFFLINE_LICENSE (environment or repo-root .env)" >&2
  exit 2
fi
export DITTO_OFFLINE_LICENSE

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$here/minimal-app/." "$work/"
rm -rf "$work/target"
cd "$work"

if [[ -n "$version" ]]; then
  cargo add --quiet "dittolive-ditto@=$version"
else
  version="$(sed -nE 's/^dittolive-ditto = "=([^"]+)"/\1/p' Cargo.toml)"
fi
export CARGO_TARGET_DIR="$here/.target/$version"

echo "== Ditto $version on $(rustc --version)"
# Lint the published code against this version, not only the committed pin.
cargo clippy --quiet --all-targets -- -D warnings
# The SDK logs to stderr; stdout carries only the program's own lines.
cargo run --quiet 2>run.err | tee run.log
grep -qx 'observer: 1 car(s)' run.log
grep -qx 'read-back make: Toyota' run.log
grep -qx "SDK version: $version" run.log

cargo test --quiet -- --test-threads=1
