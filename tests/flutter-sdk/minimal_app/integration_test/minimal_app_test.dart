import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:minimal_app/minimal_app.dart';

import 'support/temp_dir.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');
const expectedPlatform = String.fromEnvironment('DITTO_PLATFORM');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // integration_test defaults to no timeout; a hang must fail the run.
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));

  testWidgets('minimal app transcript', (tester) async {
    expect(license, isNotEmpty, reason: 'pass --dart-define=DITTO_LICENSE');
    expect(
      expectedVersion,
      isNotEmpty,
      reason: 'pass --dart-define=DITTO_VERSION',
    );
    expect(
      expectedPlatform,
      isNotEmpty,
      reason: 'pass --dart-define=DITTO_PLATFORM',
    );

    // A fresh directory per run (native); the published program uses the
    // SDK default directory instead.
    final directory = await createPersistenceDirectory();
    final List<String> lines;
    try {
      lines = await runMinimalApp(
        license: license,
        persistenceDirectory: directory,
        // The transcript channel, not app logging: `flutter test` shows
        // debugPrint output, and run-fixture.sh keeps it in the run log. Web:
        // the driver prints reportData instead.
        onLine: kIsWeb ? null : (line) => debugPrint('transcript: $line'),
      );
    } finally {
      await deletePersistenceDirectory(directory);
    }
    binding.reportData = {'transcript': lines};

    // `Ditto.version` is the core string (e.g. `iOSF5.2.0_<sha>`); the program
    // prints only its x.y.z, which must be the pinned pub version.
    expect(lines, [
      'observer: 1 car(s)',
      'read-back make: Toyota',
      'SDK version: $expectedVersion',
      'platform: $expectedPlatform',
      'closed: true',
    ]);
  });
}
