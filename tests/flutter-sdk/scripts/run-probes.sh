#!/bin/bash
#
# Run the native behavior probes for one ditto_live line on one device.
#
#   tests/flutter-sdk/scripts/run-probes.sh <device> <line>
#   tests/flutter-sdk/scripts/run-probes.sh macos 5.2
#
# init_once runs first, alone, in its own process (nothing may call Ditto.init()
# before it). Then every probe directory at or below <line> runs:
#
#   5.0  v50
#   5.1  v50 v51
#   5.2  v50 v51 v52
#
# The harness turns Ditto logging off (README, Findings that changed a research
# lead, entry 1). PROBE_DEFAULT_LOGGING=true in the environment keeps the default
# (logging on); run-fixture.sh passes it as a --dart-define.
#
# Everything else (license, pins, log file) is run-fixture.sh's.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  sed -n '3,6p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
DEVICE="$1"
LINE="$2"

case "$LINE" in
  5.0) DIRS=(v50) ;;
  5.1) DIRS=(v50 v51) ;;
  5.2) DIRS=(v50 v51 v52) ;;
  *)
    echo "no probe directories for line '$LINE' (5.0, 5.1, 5.2)" >&2
    exit 2
    ;;
esac

TARGETS=(integration_test/probes/init_once)
for dir in "${DIRS[@]}"; do
  TARGETS+=("integration_test/probes/$dir")
done

exec "$(dirname "${BASH_SOURCE[0]}")/run-fixture.sh" minimal_app "$DEVICE" "$LINE" "${TARGETS[@]}"
