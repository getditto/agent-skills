// registerObserverV2 and registerObserverWithSignalNext: 5.1.0+, @experimental.
import 'dart:async';
import 'dart:developer';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-observers-4
/// 5.1.0+: hands each result to [render] and asks for the next one only
/// when [render] has finished. Changes made meanwhile arrive together in
/// the next result. [cancel] stops observing; call it while Ditto is open.
class PacedCarsFeed {
  PacedCarsFeed(Ditto ditto, this._render)
    // No onChange: with one, every result is also buffered in the unlistened
    // `changes` stream (5.1.0, 5.2.0). This class holds the one listener.
    // ignore: experimental_member_use
    : _observer = ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM cars',
      ) {
    _changes = _observer.changes.listen(
      (result) => unawaited(_renderThenSignal(result)),
    );
  }

  final Future<void> Function(QueryResult result) _render;
  // ignore: experimental_member_use
  final StoreObserverV2 _observer;
  late final StreamSubscription<QueryResult> _changes;

  Future<void> _renderThenSignal(QueryResult result) async {
    try {
      await _render(result);
    } catch (error, stackTrace) {
      log('render failed', name: 'cars', error: error, stackTrace: stackTrace);
    } finally {
      // Nothing more is delivered until signalNext() is called.
      if (!_observer.isCancelled) _observer.signalNext();
    }
  }

  /// Cancels the listener, and with it the V2 observer.
  Future<void> cancel() => _changes.cancel();
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
      var renders = 0;
      final feed = PacedCarsFeed(ditto, (result) async {
        counts.add(result.items.length);
        renders++;
        // The first render waits until the test releases it, then fails:
        // the feed must still ask for the next result.
        if (renders == 1) {
          await release.future;
          throw StateError('render failed');
        }
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
        await feed.cancel();
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

  // Recorded SDK defect (5.1.0, 5.2.0): like V1, StoreObserverV2 adds every
  // result to its single-subscription `changes` controller even when only
  // onChange consumes it, so a late listener receives them all. In auto mode
  // (registerObserverV2) the unlistened stream is not paused, so delivery
  // continues; with signal-next, onChange signals each time here.
  for (final mode in ['registerObserverV2', 'registerObserverWithSignalNext']) {
    testWidgets(
      'SDK defect: $mode onChange observer buffers every result for a late '
      'listener',
      (t) async {
        await withDitto(t, (ditto) async {
          var callbacks = 0;
          // ignore: experimental_member_use
          final StoreObserverV2 observer = mode == 'registerObserverV2'
              // ignore: experimental_member_use
              ? ditto.store.registerObserverV2(
                  'SELECT * FROM cars',
                  onChange: (_) => callbacks++,
                )
              // ignore: experimental_member_use
              : ditto.store.registerObserverWithSignalNext(
                  'SELECT * FROM cars',
                  onChange: (_, signalNext) {
                    callbacks++;
                    signalNext();
                  },
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
  }
}
