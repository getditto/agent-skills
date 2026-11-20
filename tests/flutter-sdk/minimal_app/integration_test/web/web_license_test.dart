// `bad offline license on web`, alone in its own `flutter drive` target, so
// it runs in a fresh page where no instance has set a valid license, and on
// a database ID no other probe uses:
//
//   tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.2 \
//     integration_test/web/web_license_test.dart
//
// Compiles against ditto_live 5.0.4 and later.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_harness.dart';

const _isolatedDatabaseId = '11111111-2222-4333-8444-555555555555';

void main() {
  ensureWebProbeBinding();

  testWidgets('bad offline license on web', (t) async {
    await Ditto.init();
    final ditto = await Ditto.open(
      DittoConfig(databaseID: _isolatedDatabaseId),
    );
    try {
      record(
        'absolutePersistenceDirectory',
        ditto.absolutePersistenceDirectory,
      );
      final outcome = await outcomeOf(
        () => ditto.setOfflineOnlyLicenseToken('not-a-license'),
      );
      record('setOfflineOnlyLicenseToken(bad)', outcome);
      expect(outcome, 'ok');
    } finally {
      await ditto.close();
    }
  });
}
