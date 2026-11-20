import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-observers-1
/// Watches the blue cars. [onCars] receives every result as a list. Call the
/// returned function to stop, while Ditto is still open.
Future<void> Function() watchBlueCars(
  Ditto ditto,
  void Function(List<Map<String, dynamic>> cars) onCars,
) {
  // No onChange: an observer that has one also keeps every result buffered
  // in its unlistened `changes` stream (5.0.0 through 5.2.0). Listen to
  // `changes` once, right away; from 5.1.0 an observer without onChange
  // starts on that first listen.
  final observer = ditto.store.registerObserver(
    'SELECT * FROM cars WHERE color = :color',
    arguments: {'color': 'blue'},
  );
  final subscription = observer.changes.listen((result) {
    // `items` is an Iterable; copy it before handing it to the UI.
    onCars(result.items.map((item) => item.value).toList());
  });
  return () async {
    // Cancelling the listener does not cancel a V1 observer; cancel both.
    await subscription.cancel();
    observer.cancel();
  };
}
// snippet:end flutter-observers-1

Future<void> _insertCar(Ditto ditto, String id) => ditto.store.execute(
  'INSERT INTO cars DOCUMENTS (:car)',
  arguments: {
    'car': {'_id': id, 'color': 'blue'},
  },
);

void main() {
  ensureProbeBinding();

  testWidgets('v1 stream cancel does not cancel observer', (t) async {
    await withDitto(t, (ditto) async {
      var callbacks = 0;
      final observer = ditto.store.registerObserver(
        'SELECT * FROM cars',
        onChange: (_) => callbacks++,
      );
      try {
        final subscription = observer.changes.listen((_) {});
        await subscription.cancel();
        expect(observer.isCancelled, isFalse);

        // Still live: a write after the stream was cancelled reaches onChange.
        await waitUntil(() => callbacks > 0, reason: 'initial callback');
        final before = callbacks;
        await _insertCar(ditto, 'car-1');
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
      final observer = ditto.store.registerObserver('SELECT * FROM cars');
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
      final firstMatch = Completer<List<Map<String, dynamic>>>();
      final stop = watchBlueCars(ditto, (cars) {
        if (cars.isNotEmpty && !firstMatch.isCompleted) {
          firstMatch.complete(cars);
        }
      });
      try {
        await _insertCar(ditto, 'car-1');
        final cars = await firstMatch.future.timeout(
          const Duration(seconds: 10),
        );
        expect(cars.single['_id'], 'car-1');
      } finally {
        await stop();
      }
    });
  });

  // Recorded SDK defect (5.0.0 through 5.2.0): StoreObserver adds every result
  // to its single-subscription `changes` controller even when only onChange
  // consumes it, so the stream buffers them all and replays them to a late
  // listener.
  testWidgets(
    'SDK defect: v1 onChange observer buffers every result for a late listener',
    (t) async {
      await withDitto(t, (ditto) async {
        var callbacks = 0;
        final observer = ditto.store.registerObserver(
          'SELECT * FROM cars',
          onChange: (_) => callbacks++,
        );
        try {
          await waitUntil(() => callbacks == 1, reason: 'initial callback');
          for (var i = 0; i < 5; i++) {
            await _insertCar(ditto, 'car-$i');
            await waitUntil(() => callbacks == i + 2, reason: 'insert $i');
          }
          expect(callbacks, 6);

          var replayed = 0;
          final late = observer.changes.listen((_) => replayed++);
          try {
            await waitUntil(() => replayed >= 6, reason: 'replay');
            await holdsFor(
              () => replayed == 6,
              const Duration(seconds: 1),
              reason: 'exactly the six buffered results',
            );
            expect(replayed, callbacks);
          } finally {
            await late.cancel();
          }
        } finally {
          observer.cancel();
        }
      });
    },
  );

  testWidgets('observer without onChange: eager on 5.0, on first listen 5.1+', (
    t,
  ) async {
    await withDitto(t, (ditto) async {
      final observer = ditto.store.registerObserver('SELECT * FROM cars');
      try {
        await Future<void>.delayed(const Duration(seconds: 1));
        await _insertCar(ditto, 'car-1');
        await Future<void>.delayed(const Duration(seconds: 1));

        final counts = <int>[];
        final subscription = observer.changes.listen(
          (result) => counts.add(result.items.length),
        );
        try {
          // 5.0.x starts the live query at registration, so the stream holds
          // the empty initial result and the insert. 5.1.0+ starts it on this
          // listen and delivers only the current state.
          final expected = pinnedLine == '5.0' ? [0, 1] : [1];
          await waitUntil(() => counts.length >= expected.length);
          await holdsFor(
            () => counts.length == expected.length,
            const Duration(seconds: 1),
            reason: 'no further results',
          );
          expect(counts, expected);
        } finally {
          await subscription.cancel();
        }
      } finally {
        observer.cancel();
      }
    });
  });

  testWidgets('items toList for setState', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.store.execute(
        'INSERT INTO cars DOCUMENTS (:car)',
        arguments: {
          'car': {'_id': 'car-1', 'n': 1},
        },
      );
      final result = await ditto.store.execute('SELECT * FROM cars');

      expect(result.items, isA<Iterable<QueryResultItem>>());
      expect(result.items, isNot(isA<List<QueryResultItem>>()));
      final docs = result.items.map((item) => item.value).toList();
      expect(docs, isA<List<Map<String, dynamic>>>());
      expect(docs, [
        {'_id': 'car-1', 'n': 1},
      ]);
    });
  });
}
