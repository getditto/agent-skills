// Store.observers: 5.2.0+.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Store.observers contains a live v1 observer after its stream is cancelled',
    (t) async {
      await withDitto(t, (ditto) async {
        final observer = ditto.store.registerObserver('SELECT * FROM probes');
        final subscription = observer.changes.listen((_) {});
        await subscription.cancel();

        // snippet:start flutter-observers-5
        // 5.2.0+: every V1 observer that has not been cancelled, including
        // ones whose `changes` listener is gone. Use it to find leaks.
        final live = ditto.store.observers;
        // snippet:end flutter-observers-5
        expect(live, contains(observer));
        expect(observer.isCancelled, isFalse);

        observer.cancel();
        expect(ditto.store.observers, isNot(contains(observer)));

        await ditto.close();
        expect(ditto.store.observers, isEmpty);
      });
    },
  );
}
