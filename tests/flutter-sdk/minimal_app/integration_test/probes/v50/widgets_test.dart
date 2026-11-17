import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-anti-patterns-1
// Anti-pattern: the widget tree subscribes directly to an observer's
// single-subscription `changes` stream.
class LeakyCarsRepository {
  LeakyCarsRepository(Ditto ditto)
    : observer = ditto.store.registerObserver('SELECT * FROM cars');

  final StoreObserver observer;

  Stream<QueryResult> get changes => observer.changes;
}

class LeakyCarsScreen extends StatelessWidget {
  const LeakyCarsScreen({super.key, required this.repository});

  final LeakyCarsRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<QueryResult>(
    // Disposing this StreamBuilder cancels its listener but not the observer;
    // building the screen again listens a second time and throws StateError.
    stream: repository.changes,
    builder: (context, snapshot) =>
        Text('${snapshot.data?.items.length ?? 0} cars'),
  );
}
// snippet:end flutter-anti-patterns-1

// snippet:start flutter-observers-2
/// Owns the observer for as long as the data is needed, independent of any
/// one widget. Screens listen to [cars]; [dispose] stops observing.
class CarsRepository {
  CarsRepository(Ditto ditto) {
    // No onChange (it would also buffer every result in the unlistened
    // `changes` stream, 5.0.0 through 5.2.0). This class holds the one
    // `changes` listener, started right away.
    _observer = ditto.store.registerObserver('SELECT * FROM cars');
    _changes = _observer.changes.listen((result) {
      cars.value = result.items.map((item) => item.value).toList();
    });
  }

  final cars = ValueNotifier<List<Map<String, dynamic>>>(const []);
  late final StoreObserver _observer;
  late final StreamSubscription<QueryResult> _changes;

  bool get isObserving => !_observer.isCancelled;

  /// Call while Ditto is still open: the listener first, then the observer.
  Future<void> dispose() async {
    await _changes.cancel();
    _observer.cancel();
    cars.dispose();
  }
}

class CarsScreen extends StatelessWidget {
  const CarsScreen({super.key, required this.repository});

  final CarsRepository repository;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository.cars,
    builder: (context, _) => Text('${repository.cars.value.length} cars'),
  );
}
// snippet:end flutter-observers-2

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  ensureProbeBinding();

  testWidgets('reentered widget leaks v1 observer and second listen throws', (
    t,
  ) async {
    await withDitto(t, (ditto) async {
      final leaky = LeakyCarsRepository(ditto);
      try {
        await t.pumpWidget(_app(LeakyCarsScreen(repository: leaky)));
        expect(t.takeException(), isNull);

        // Leave the screen, then enter it again.
        await t.pumpWidget(_app(const SizedBox()));
        expect(leaky.observer.isCancelled, isFalse);
        await t.pumpWidget(_app(LeakyCarsScreen(repository: leaky)));
        expect(
          t.takeException(),
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Stream has already been listened to.',
          ),
        );
        expect(leaky.observer.isCancelled, isFalse);
      } finally {
        await t.pumpWidget(_app(const SizedBox()));
        leaky.observer.cancel();
      }

      // The corrected pattern: the repository owns the observer.
      final repository = CarsRepository(ditto);
      await t.pumpWidget(_app(CarsScreen(repository: repository)));
      await ditto.store.execute(
        'INSERT INTO cars DOCUMENTS (:car)',
        arguments: {
          'car': {'_id': 'car-1'},
        },
      );
      await waitUntil(() => repository.cars.value.length == 1);
      await t.pump();
      expect(find.text('1 cars'), findsOneWidget);

      await t.pumpWidget(_app(const SizedBox()));
      await t.pumpWidget(_app(CarsScreen(repository: repository)));
      expect(t.takeException(), isNull);
      expect(find.text('1 cars'), findsOneWidget);
      expect(repository.isObserving, isTrue);

      await t.pumpWidget(_app(const SizedBox()));
      await repository.dispose();
      expect(repository.isObserving, isFalse);
    });
  });
}
