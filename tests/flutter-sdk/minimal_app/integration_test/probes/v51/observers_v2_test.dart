// registerObserverV2 and registerObserverWithSignalNext: 5.1.0+, @experimental.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

Future<void> _insert(Ditto ditto, String id) => ditto.store.execute(
  'INSERT INTO probes DOCUMENTS (:doc)',
  arguments: {
    'doc': {'_id': id},
  },
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signalNext gates delivery and coalesces', (t) async {
    await withDitto(t, (ditto) async {
      final counts = <int>[];
      void Function()? next;
      // snippet:start flutter-observers-4
      // ignore: experimental_member_use
      final observer = ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM probes',
        onChange: (result, signalNext) {
          counts.add(result.items.length);
          // Nothing more is delivered until signalNext() is called; changes
          // made meanwhile arrive together in the next callback.
          next = signalNext;
        },
      );
      // snippet:end flutter-observers-4
      try {
        await waitUntil(() => counts.isNotEmpty, reason: 'initial callback');
        expect(counts, [0]);

        await _insert(ditto, 'a');
        await _insert(ditto, 'b');
        await _insert(ditto, 'c');
        await holdsFor(
          () => counts.length == 1,
          const Duration(seconds: 2),
          reason: 'no delivery before signalNext',
        );

        next!();
        await waitUntil(() => counts.length > 1, reason: 'after signalNext');
        expect(counts, [0, 3]);
      } finally {
        observer.cancel();
      }
    });
  });

  testWidgets('v2 stream cancel cancels observer', (t) async {
    await withDitto(t, (ditto) async {
      // snippet:start flutter-observers-3
      // ignore: experimental_member_use
      final observer = ditto.store.registerObserverV2('SELECT * FROM probes');
      final subscription = observer.changes.listen((result) {
        // render result.items.toList()
      });
      // ...
      await subscription.cancel(); // also cancels a V2 observer
      // snippet:end flutter-observers-3
      expect(observer.isCancelled, isTrue);
    });
  });
}
