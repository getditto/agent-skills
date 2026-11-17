// Close semantics that changed in 5.1.0.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('observer isCancelled after close', (t) async {
    await withDitto(t, (ditto) async {
      final v1 = ditto.store.registerObserver(
        'SELECT * FROM probes',
        onChange: (_) {},
      );
      // ignore: experimental_member_use
      final v2 = ditto.store.registerObserverV2('SELECT * FROM probes');
      expect(v1.isCancelled, isFalse);
      expect(v2.isCancelled, isFalse);

      await ditto.close();
      expect(v1.isCancelled, isTrue);
      expect(v2.isCancelled, isTrue);
    });
  });

  testWidgets('close resets customLogCallback', (t) async {
    await withDitto(t, (ditto) async {
      DittoLogger.customLogCallback = (level, message) {};
      expect(DittoLogger.customLogCallback, isNotNull);

      await ditto.close();
      expect(DittoLogger.customLogCallback, isNull);
    });
  });
}
