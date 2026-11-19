#!/bin/bash
#
# Open a store written by ditto_live 4.14.x with a 5.x line, on macOS.
#
#   tests/flutter-sdk/scripts/run-v4-upgrade.sh [<5.x line>]
#   tests/flutter-sdk/scripts/run-v4-upgrade.sh 5.2
#
# Two rounds, each two run-fixture.sh invocations (one process each):
#   v4_app      on 4.14   integration_test/upgrade/v4_write_test.dart: wipe, then
#                         write one car into the v4 default, {Documents}/ditto
#   minimal_app on <line> integration_test/migration/upgrade_from_v4_test.dart with
#                         MIGRATION_PHASE=read-default (round 1: no
#                         persistenceDirectory) or read-explicit (round 2: the v4
#                         directory passed explicitly)
# Each round starts from a fresh 4.14 store, because the 5.x open may change it.
#
# macOS only: a sandboxed app's Documents directory belongs to its bundle ID, so the
# v4_app copy is built with minimal_app's bundle ID (FIXTURE_MACOS_BUNDLE_ID in
# run-fixture.sh). Nothing else may use that container's default directories in
# between. Stops at the first failing phase.
set -euo pipefail

LINE="${1:-5.2}"
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER = //p' \
  "$SCRIPTS/../minimal_app/macos/Runner/Configs/AppInfo.xcconfig")"

for phase in read-default read-explicit; do
  FIXTURE_MACOS_BUNDLE_ID="$BUNDLE_ID" "$SCRIPTS/run-fixture.sh" v4_app macos 4.14 \
    integration_test/upgrade/v4_write_test.dart
  MIGRATION_PHASE="$phase" "$SCRIPTS/run-fixture.sh" minimal_app macos "$LINE" \
    integration_test/migration/upgrade_from_v4_test.dart
done
