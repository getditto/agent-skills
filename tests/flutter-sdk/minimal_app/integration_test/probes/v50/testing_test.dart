import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// snippet:start flutter-testing-2
/// Opens a Ditto instance for one integration test: a fresh temporary
/// directory, the offline license from `--dart-define-from-file`, every
/// peer-to-peer transport off. Closes it and deletes the directory after
/// [body], also when [body] fails.
Future<void> withTestDitto(Future<void> Function(Ditto ditto) body) async {
  await Ditto.init();
  // Tests only, not an app fix: re-opening Ditto in one process with logging
  // on can abort or hang it when the GC frees a handle of the closed one.
  DittoLogger.isEnabled = false;
  final directory = await Directory.systemTemp.createTemp('ditto_test_');
  try {
    final ditto = await Ditto.open(
      DittoConfig(persistenceDirectory: directory.path),
    );
    try {
      ditto.setOfflineOnlyLicenseToken(
        const String.fromEnvironment('DITTO_LICENSE'),
      );
      ditto.updateTransportConfig((config) {
        config.peerToPeer.bluetoothLE.isEnabled = false;
        config.peerToPeer.lan.isEnabled = false;
        config.peerToPeer.awdl.isEnabled = false;
        config.peerToPeer.wifiAware.isEnabled = false;
      });
      await body(ditto); // cancel observers and subscriptions in here
    } finally {
      await ditto.close();
    }
  } finally {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Windows keeps the directory locked for a while after close().
      if (!Platform.isWindows) rethrow;
    }
  }
}
// snippet:end flutter-testing-2

void main() {
  // integration_test has no per-test timeout by default.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout =
      const Timeout(Duration(minutes: 2));

  for (final run in [1, 2]) {
    testWidgets('withTestDitto opens a fresh store, run $run', (t) async {
      await withTestDitto((ditto) async {
        final before = await ditto.store.execute('SELECT * FROM cars');
        expect(before.items, isEmpty);
        await ditto.store.execute(
          'INSERT INTO cars DOCUMENTS (:car)',
          arguments: {
            'car': {'_id': 'car-$run'},
          },
        );
        final after = await ditto.store.execute('SELECT * FROM cars');
        expect(after.items.single.value['_id'], 'car-$run');
      });
    });
  }
}
