#!/bin/bash
#
# Run the 5.1 -> 5.2 default persistence directory migration on one device.
#
#   tests/flutter-sdk/scripts/run-migration.sh <device>
#   tests/flutter-sdk/scripts/run-migration.sh macos
#   DITTO_PLATFORM=ios tests/flutter-sdk/scripts/run-migration.sh <simulator-udid>
#
# Three run-fixture.sh invocations of
# minimal_app/integration_test/migration/migrate_default_dir_test.dart, one process
# each, same bundle ID, no uninstall between them:
#   MIGRATION_PHASE=wipe  on 5.1 (delete both default directories),
#   MIGRATION_PHASE=write on 5.1 (the published minimal app, default directory),
#   MIGRATION_PHASE=read  on 5.2 (open the default directory, expect the car).
# Nothing else may open the default directory on this device in between. Stops at
# the first failing phase.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  sed -n '3,7p' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=integration_test/migration/migrate_default_dir_test.dart

MIGRATION_PHASE="wipe" "$SCRIPTS/run-fixture.sh" minimal_app "$1" 5.1 "$TARGET"
MIGRATION_PHASE="write" "$SCRIPTS/run-fixture.sh" minimal_app "$1" 5.1 "$TARGET"
MIGRATION_PHASE="read" "$SCRIPTS/run-fixture.sh" minimal_app "$1" 5.2 "$TARGET"
