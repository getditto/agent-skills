// registerObserverV2 and registerObserverWithSignalNext: 5.1.0+, @experimental.
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-observers-4
/// 5.1.0+: hands each result to [render] and asks for the next one only
/// when [render] has finished. Changes made meanwhile arrive together in
/// the next result. Cancel the returned observer while Ditto is open.
// ignore: experimental_member_use
StoreObserverV2 observeCarsPaced(
  Ditto ditto,
  Future<void> Function(QueryResult result) render,
) {
  // ignore: experimental_member_use
  return ditto.store.registerObserverWithSignalNext(
    'SELECT * FROM cars',
    onChange: (result, signalNext) {
      // Nothing more is delivered until signalNext() is called.
      unawaited(render(result).whenComplete(signalNext));
    },
  );
}
// snippet:end flutter-observers-4

// snippet:start flutter-observers-3
/// 5.1.0+: a V2 observer stops when its stream listener is cancelled, so
/// cancelling the subscription is the whole cleanup.
class CarsFeed {
  CarsFeed(Ditto ditto, void Function(List<Map<String, dynamic>> cars) onCars)
    // ignore: experimental_member_use
    : _observer = ditto.store.registerObserverV2('SELECT * FROM cars') {
    _subscription = _observer.changes.listen((result) {
      onCars(result.items.map((item) => item.value).toList());
    });
  }

  // ignore: experimental_member_use
  final StoreObserverV2 _observer;
  late final StreamSubscription<QueryResult> _subscription;

  bool get isActive => !_observer.isCancelled;

  /// Cancels the listener, and with it the V2 observer.
  Future<void> cancel() => _subscription.cancel();
}
// snippet:end flutter-observers-3

Future<void> _insertCar(Ditto ditto, String id) => ditto.store.execute(
  'INSERT INTO cars DOCUMENTS (:car)',
  arguments: {
    'car': {'_id': id},
  },
);

void main() {
  ensureProbeBinding();

  testWidgets('signalNext gates delivery and coalesces', (t) async {
    await withDitto(t, (ditto) async {
      final counts = <int>[];
      final release = Completer<void>();
      final observer = observeCarsPaced(ditto, (result) async {
        counts.add(result.items.length);
        // The first render waits until the test releases it.
        await release.future;
      });
      try {
        await waitUntil(() => counts.isNotEmpty, reason: 'initial callback');
        expect(counts, [0]);

        await _insertCar(ditto, 'car-1');
        await _insertCar(ditto, 'car-2');
        await _insertCar(ditto, 'car-3');
        await holdsFor(
          () => counts.length == 1,
          const Duration(seconds: 2),
          reason: 'no delivery while render runs',
        );

        release.complete();
        await waitUntil(() => counts.length > 1, reason: 'after signalNext');
        await holdsFor(
          () => counts.length == 2,
          const Duration(seconds: 1),
          reason: 'one coalesced callback',
        );
        expect(counts, [0, 3]);
      } finally {
        observer.cancel();
      }
    });
  });

  testWidgets('v2 stream cancel cancels observer', (t) async {
    await withDitto(t, (ditto) async {
      final seen = <int>[];
      final feed = CarsFeed(ditto, (cars) => seen.add(cars.length));
      await waitUntil(() => seen.isNotEmpty, reason: 'initial result');
      expect(feed.isActive, isTrue);

      await feed.cancel();
      expect(feed.isActive, isFalse);
    });
  });
}
