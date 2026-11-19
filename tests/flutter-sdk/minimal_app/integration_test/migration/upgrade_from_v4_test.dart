// Second phase of scripts/run-v4-upgrade.sh: a 5.x line opens the store that
// ditto_live 4.14.x wrote to `{Documents}/ditto`
// (v4_app/integration_test/upgrade/v4_write_test.dart), in the same sandbox
// container, and looks for the car.
//
//   MIGRATION_PHASE=read-default   DittoConfig(databaseID: <the v4 app ID>),
//                                  no persistenceDirectory
//   MIGRATION_PHASE=read-explicit  the same, with persistenceDirectory set to
//                                  the v4 directory
//
// The test records what the SDK did (the directory it opened, the cars it
// found, which directories exist afterwards) and asserts the recorded
// outcome, so a later SDK that behaves differently fails here. Native only.
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const phase = String.fromEnvironment('MIGRATION_PHASE');

/// The v4 fixture's app ID, which becomes the v5 database ID.
const databaseID = 'REPLACE_ME_WITH_YOUR_APP_ID';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));

  testWidgets('open a 4.14 store: $phase', (tester) async {
    expect(license, isNotEmpty);
    expect(phase, isIn(['read-default', 'read-explicit']));
    final documents = (await getApplicationDocumentsDirectory()).path;
    final support = (await getApplicationSupportDirectory()).path;
    final v4Directory = Directory('$documents/ditto');
    final v5Documents = Directory('$documents/ditto-$databaseID');
    final v5Support = Directory('$support/ditto-$databaseID');
    void transcript(String line) => debugPrint('transcript: $line');
    expect(
      v4Directory.existsSync(),
      isTrue,
      reason: 'run the 4.14 phase first',
    );

    await Ditto.init();
    final ditto = await Ditto.open(
      DittoConfig(
        databaseID: databaseID,
        persistenceDirectory: phase == 'read-explicit'
            ? v4Directory.path
            : null,
      ),
    );
    final List<String> makes;
    final String opened;
    try {
      ditto.setOfflineOnlyLicenseToken(license);
      opened = ditto.absolutePersistenceDirectory;
      final result = await ditto.store.execute(
        'SELECT * FROM cars WHERE _id = :id',
        arguments: {'id': 'blue-toyota'},
      );
      makes = [for (final item in result.items) '${item.value['make']}'];
    } finally {
      await ditto.close();
    }
    transcript('opened: $opened');
    transcript('read-back makes: $makes');
    transcript('v4 directory exists: ${v4Directory.existsSync()}');
    transcript('v5 Documents default exists: ${v5Documents.existsSync()}');
    transcript(
      'v5 Application Support default exists: ${v5Support.existsSync()}',
    );
    expect(makes, ['Toyota']);
    // Recorded outcome (README): 5.x opens the v4 directory in place, with or
    // without an explicit persistenceDirectory, and creates neither v5
    // default directory. Fail loudly if a later SDK moves or copies it.
    expect(
      Directory(opened).resolveSymbolicLinksSync(),
      v4Directory.resolveSymbolicLinksSync(),
    );
    expect(v5Documents.existsSync(), isFalse, reason: v5Documents.path);
    expect(v5Support.existsSync(), isFalse, reason: v5Support.path);
  });
}
