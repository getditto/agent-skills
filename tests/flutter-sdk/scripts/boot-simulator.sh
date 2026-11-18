#!/bin/bash
#
# Boot an iPhone simulator on the newest installed iOS runtime and print its UDID.
#
#   udid="$(tests/flutter-sdk/scripts/boot-simulator.sh)"
#
# The runtime and device name go to stderr. An already booted device is reused.
# run-fixture.sh cannot tell a simulator UDID's platform: pass DITTO_PLATFORM=ios.
set -euo pipefail

picked="$(xcrun simctl list devices available -j | jq -er '
  .devices | to_entries
  | map(select(.key | test("SimRuntime\\.iOS-")))
  | map(select(any(.value[]; .name | startswith("iPhone"))))
  | sort_by(.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber))
  | last
  | . as $runtime
  | [.value[] | select(.name | startswith("iPhone"))][0]
  | [$runtime.key, .name, .udid, .state] | @tsv')"
IFS=$'\t' read -r runtime name udid state <<<"$picked"
echo "simulator: $name ($runtime), $udid, $state" >&2
if [[ "$state" != "Booted" ]]; then
  xcrun simctl boot "$udid"
fi
xcrun simctl bootstatus "$udid" -b >&2
echo "$udid"
