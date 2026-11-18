// The 5.1 -> 5.2 default persistence directory migration, in three processes:
//
//   MIGRATION_PHASE=wipe   delete {Documents}/ditto-<id> and
//                          {Application Support}/ditto-<id>
//   MIGRATION_PHASE=write  (5.1) run the published minimal app, which opens
//                          the SDK default directory and writes one car
//   MIGRATION_PHASE=read   (5.2) open the default directory the same way and
//                          expect that car
//
// Each phase is its own `flutter test` process with the same bundle ID, so
// the write and read phases never close and reopen Ditto in one process.
// Native only.
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:minimal_app/minimal_app.dart';
import 'package:path_provider/path_provider.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');
const phase = String.fromEnvironment('MIGRATION_PHASE');

/// `DittoConfig()`'s default database ID; the default directory is
/// `ditto-<lowercase database ID>`.
const defaultDirectoryName = 'ditto-00000000-0000-0000-0000-000000000000';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // integration_test defaults to no timeout; a hang must fail the run.
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));

  testWidgets('migrate default directory: $phase', (tester) async {
    expect(license, isNotEmpty, reason: 'pass --dart-define=DITTO_LICENSE');
    expect(
      phase,
      isIn(['wipe', 'write', 'read']),
      reason: 'pass --dart-define=MIGRATION_PHASE=wipe|write|read',
    );
    final documents = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/$defaultDirectoryName',
    );
    final support = Directory(
      '${(await getApplicationSupportDirectory()).path}/$defaultDirectoryName',
    );
    void transcript(String line) => debugPrint('transcript: $line');

    switch (phase) {
      case 'wipe':
        for (final directory in [documents, support]) {
          if (directory.existsSync()) {
            await directory.delete(recursive: true);
          }
          expect(directory.existsSync(), isFalse, reason: directory.path);
        }
        transcript('wiped: ${documents.path}');
        transcript('wiped: ${support.path}');

      case 'write':
        expect(expectedVersion, startsWith('5.1.'));
        // The published program, unchanged: no persistenceDirectory.
        final lines = await runMinimalApp(license: license, onLine: transcript);
        expect(lines, contains('read-back make: Toyota'));
        expect(lines.last, 'closed: true');
        transcript('documents default exists: ${documents.existsSync()}');
        transcript('support default exists: ${support.existsSync()}');
        // 5.1 puts the default directory under Documents.
        expect(documents.existsSync(), isTrue, reason: documents.path);

      case 'read':
        expect(expectedVersion, startsWith('5.2.'));
        // The same open as the published program: DittoConfig with no
        // persistenceDirectory, so the SDK picks the default directory.
        await Ditto.init();
        final ditto = await Ditto.open(
          const DittoConfig(persistenceDirectory: null),
        );
        final List<String> makes;
        try {
          ditto.setOfflineOnlyLicenseToken(license);
          transcript('5.2 directory: ${ditto.absolutePersistenceDirectory}');
          final result = await ditto.store.execute(
            'SELECT * FROM cars WHERE _id = :id',
            arguments: {'id': 'blue-toyota'},
          );
          makes = [for (final item in result.items) '${item.value['make']}'];
        } finally {
          await ditto.close();
        }
        transcript('5.2 read-back makes: $makes');
        transcript('documents default exists: ${documents.existsSync()}');
        transcript('support default exists: ${support.existsSync()}');
        expect(makes, ['Toyota']);
    }
  });
}
