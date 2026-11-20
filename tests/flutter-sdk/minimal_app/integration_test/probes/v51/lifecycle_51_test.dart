// Close semantics that changed in 5.1.0. The V1 isCancelled and
// customLogCallback cases run on every line in v50/lifecycle_test.dart.
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  ensureProbeBinding();

  testWidgets('observer isCancelled after close', (t) async {
    await withDitto(t, (ditto) async {
      final v1 = ditto.store.registerObserver(
        'SELECT * FROM cars',
        onChange: (_) {},
      );
      // ignore: experimental_member_use
      final v2 = ditto.store.registerObserverV2('SELECT * FROM cars');
      expect(v1.isCancelled, isFalse);
      expect(v2.isCancelled, isFalse);

      await ditto.close();
      expect(v1.isCancelled, isTrue);
      expect(v2.isCancelled, isTrue);
    });
  });
}
