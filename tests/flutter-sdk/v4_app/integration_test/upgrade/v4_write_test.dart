// First phase of scripts/run-v4-upgrade.sh: ditto_live 4.14.x writes one car
// into the v4 default persistence directory, `{Documents}/ditto`, after
// deleting that directory and both v5 default directories. The second phase
// (minimal_app/integration_test/migration/upgrade_from_v4_test.dart) opens
// the store with a 5.x line. The script gives this fixture copy minimal_app's
// macOS bundle ID, so both phases share one sandbox container.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:v4_app/v4_app.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');

/// The v5 default directory name for the database ID the second phase opens:
/// the v4 fixture's app ID.
const v5DirectoryName = 'ditto-REPLACE_ME_WITH_YOUR_APP_ID';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));

  testWidgets('4.14 writes the v4 default directory', (tester) async {
    expect(license, isNotEmpty);
    expect(expectedVersion, startsWith('4.14.'));
    final documents = (await getApplicationDocumentsDirectory()).path;
    final support = (await getApplicationSupportDirectory()).path;
    final v4Directory = Directory('$documents/ditto');
    for (final directory in [
      v4Directory,
      Directory('$documents/$v5DirectoryName'),
      Directory('$support/$v5DirectoryName'),
    ]) {
      if (directory.existsSync()) await directory.delete(recursive: true);
      expect(directory.existsSync(), isFalse, reason: directory.path);
    }

    // 'ditto', relative: 4.14 resolves it against Documents. It is the
    // directory a v4 app that passed no persistenceDirectory used.
    final lines = await runV4App(
      license: license,
      persistenceDirectory: 'ditto',
    );
    for (final line in lines) {
      debugPrint('transcript: $line');
    }
    debugPrint('transcript: v4 directory: ${v4Directory.path}');
    expect(lines, [
      'v4 read-back make: Toyota',
      'v4 SDK version: $expectedVersion',
      'v4 closed: true',
    ]);
    expect(v4Directory.existsSync(), isTrue, reason: v4Directory.path);
  });
}
