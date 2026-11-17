import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:minimal_app/minimal_app.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('minimal app transcript', (tester) async {
    expect(license, isNotEmpty, reason: 'pass --dart-define=DITTO_LICENSE');
    expect(
      expectedVersion,
      isNotEmpty,
      reason: 'pass --dart-define=DITTO_VERSION',
    );

    final lines = await runMinimalApp(
      license: license,
      // Native: `flutter test` shows this. Web: the driver prints reportData.
      onLine: kIsWeb ? null : (line) => debugPrint('transcript: $line'),
    );
    binding.reportData = {'transcript': lines};

    expect(
      lines,
      containsAllInOrder([
        'observer: 1 car(s)',
        'read-back make: Toyota',
        'closed: true',
      ]),
    );
    expect(
      lines.firstWhere((l) => l.startsWith('SDK version: ')),
      contains(expectedVersion),
    );
  });
}
