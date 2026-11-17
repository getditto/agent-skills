import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('v1 stream cancel does not cancel observer', (t) async {
    await withDitto(t, (ditto) async {
      var callbacks = 0;
      final observer = ditto.store.registerObserver(
        'SELECT * FROM probes',
        onChange: (_) => callbacks++,
      );
      try {
        final subscription = observer.changes.listen((_) {});
        await subscription.cancel();
        expect(observer.isCancelled, isFalse);

        // Still live: a write after the stream was cancelled reaches onChange.
        await waitUntil(() => callbacks > 0, reason: 'initial callback');
        final before = callbacks;
        await ditto.store.execute(
          'INSERT INTO probes DOCUMENTS (:doc)',
          arguments: {
            'doc': {'_id': 'a'},
          },
        );
        await waitUntil(() => callbacks > before, reason: 'post-cancel write');
        expect(observer.isCancelled, isFalse);
      } finally {
        observer.cancel();
      }
      expect(observer.isCancelled, isTrue);
    });
  });

  testWidgets('changes second listen throws StateError', (t) async {
    await withDitto(t, (ditto) async {
      final observer = ditto.store.registerObserver('SELECT * FROM probes');
      try {
        final first = observer.changes.listen((_) {});
        expect(() => observer.changes.listen((_) {}), throwsStateError);
        await first.cancel();
        expect(() => observer.changes.listen((_) {}), throwsStateError);
      } finally {
        observer.cancel();
      }
    });
  });

  testWidgets('observer fires without ORDER BY', (t) async {
    await withDitto(t, (ditto) async {
      // snippet:start flutter-observers-1
      final firstMatch = Completer<List<Map<String, dynamic>>>();
      final observer = ditto.store.registerObserver(
        'SELECT * FROM probes WHERE color = :color',
        arguments: {'color': 'blue'},
        onChange: (result) {
          // `items` is an Iterable; copy it before handing it to the UI.
          final docs = result.items.map((item) => item.value).toList();
          if (docs.isNotEmpty && !firstMatch.isCompleted) {
            firstMatch.complete(docs);
          }
        },
      );
      // snippet:end flutter-observers-1
      try {
        await ditto.store.execute(
          'INSERT INTO probes DOCUMENTS (:doc)',
          arguments: {
            'doc': {'_id': 'a', 'color': 'blue'},
          },
        );
        final docs = await firstMatch.future.timeout(
          const Duration(seconds: 10),
        );
        expect(docs.single['_id'], 'a');
      } finally {
        observer.cancel();
      }
    });
  });

  testWidgets('items toList for setState', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.store.execute(
        'INSERT INTO probes DOCUMENTS (:doc)',
        arguments: {
          'doc': {'_id': 'a', 'n': 1},
        },
      );
      final result = await ditto.store.execute('SELECT * FROM probes');

      expect(result.items, isA<Iterable<QueryResultItem>>());
      expect(result.items, isNot(isA<List<QueryResultItem>>()));
      final docs = result.items.map((item) => item.value).toList();
      expect(docs, isA<List<Map<String, dynamic>>>());
      expect(docs, [
        {'_id': 'a', 'n': 1},
      ]);
    });
  });
}
