// Runs alone, first, in its own process: nothing may call Ditto.init() before
// this test does. It does not use the harness for that reason.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  // integration_test defaults to no timeout; a hang must fail the run.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout =
      const Timeout(Duration(minutes: 2));

  testWidgets('DittoLogger getter before init', (t) async {
    expect(
      () => DittoLogger.isEnabled,
      throwsA(
        isA<DittoError>().having(
          (e) => e.toString(),
          'toString()',
          'DittoError(Ditto not initialized. Call `Ditto.init()` and await the '
              '`Future` before using any Ditto functionality)',
        ),
      ),
    );

    await Ditto.init();
    expect(DittoLogger.isEnabled, isA<bool>());
  });
}
