import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-store-1
/// Inserts [car] and returns the IDs of the documents the statement changed.
/// IDs are `dynamic`: an `_id` can be a string, number, map or other value.
Future<List<dynamic>> insertCar(Ditto ditto, Map<String, dynamic> car) async {
  final result = await ditto.store.execute(
    'INSERT INTO cars DOCUMENTS (:car)',
    arguments: {'car': car},
  );
  return result.mutatedDocumentIDs(); // a method, not a getter
}
// snippet:end flutter-store-1

// snippet:start flutter-store-2
/// Inserts [order] and its [lines] together, or neither.
Future<void> saveOrder(
  Ditto ditto,
  Map<String, dynamic> order,
  List<Map<String, dynamic>> lines,
) async {
  await ditto.store.transaction((tx) async {
    await tx.execute(
      'INSERT INTO orders DOCUMENTS (:order)',
      arguments: {'order': order},
    );
    if (lines.isEmpty) {
      // Any exception thrown by the callback rolls the transaction back and
      // is rethrown to the caller of transaction().
      throw ArgumentError.value(lines, 'lines', 'an order needs a line');
    }
    for (final line in lines) {
      await tx.execute(
        'INSERT INTO order_lines DOCUMENTS (:line)',
        arguments: {'line': line},
      );
    }
  });
}
// snippet:end flutter-store-2

// snippet:start flutter-store-3
/// Inserts [car] only if no car has the same plate; returns whether it did.
Future<bool> insertCarIfNewPlate(Ditto ditto, Map<String, dynamic> car) async {
  final action = await ditto.store.transaction((tx) async {
    await tx.execute(
      'INSERT INTO cars DOCUMENTS (:car)',
      arguments: {'car': car},
    );
    final same = await tx.execute(
      'SELECT * FROM cars WHERE plate = :plate',
      arguments: {'plate': car['plate']},
    );
    // Returning rollback discards the writes; any other value commits.
    return same.items.length > 1
        ? TransactionCompletionAction.rollback
        : TransactionCompletionAction.commit;
  });
  return action == TransactionCompletionAction.commit;
}
// snippet:end flutter-store-3

// snippet:start flutter-store-4
/// Speeds up queries that filter cars by color.
Future<void> createColorIndex(Ditto ditto) => ditto.store.execute(
  'CREATE INDEX IF NOT EXISTS cars_color ON cars (color)',
);
// snippet:end flutter-store-4

// snippet:start flutter-store-5
/// Evicts the cars of [color] from the local store; returns their IDs.
Future<List<dynamic>> evictCars(Ditto ditto, String color) async {
  final evicted = await ditto.store.execute(
    'EVICT FROM cars WHERE color = :color',
    arguments: {'color': color},
  );
  return evicted.mutatedDocumentIDs();
}
// snippet:end flutter-store-5

Future<int> _count(Ditto ditto, String collection) async =>
    (await ditto.store.execute('SELECT * FROM $collection')).items.length;

void main() {
  ensureProbeBinding();

  testWidgets('transaction throw rolls back', (t) async {
    await withDitto(t, (ditto) async {
      await expectLater(
        saveOrder(ditto, {'_id': 'order-1'}, const []),
        throwsArgumentError,
      );
      expect(await _count(ditto, 'orders'), 0);

      await saveOrder(
        ditto,
        {'_id': 'order-2'},
        [
          {'_id': 'line-1', 'order': 'order-2'},
        ],
      );
      expect(await _count(ditto, 'orders'), 1);
      expect(await _count(ditto, 'order_lines'), 1);
    });
  });

  testWidgets('rollback action rolls back', (t) async {
    await withDitto(t, (ditto) async {
      expect(
        await insertCarIfNewPlate(ditto, {'_id': 'car-1', 'plate': 'ABC'}),
        isTrue,
      );
      expect(
        await insertCarIfNewPlate(ditto, {'_id': 'car-2', 'plate': 'ABC'}),
        isFalse,
      );
      expect(await _count(ditto, 'cars'), 1);
    });
  });

  testWidgets('store.execute inside transaction throws', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.store.transaction((tx) async {
        await expectLater(
          ditto.store.execute('SELECT * FROM cars'),
          throwsA(
            isA<DittoException>().having(
              (e) => e.toString(),
              'toString()',
              contains(
                'Attempting to use `ditto.store.execute` while in a '
                'transaction scope',
              ),
            ),
          ),
        );
      });
    });
  });

  testWidgets('mutatedDocumentIDs is a method', (t) async {
    await withDitto(t, (ditto) async {
      expect(await insertCar(ditto, {'_id': 'car-1', 'color': 'blue'}), [
        'car-1',
      ]);
    });
  });

  testWidgets('CREATE INDEX and EVICT via execute succeed', (t) async {
    await withDitto(t, (ditto) async {
      await insertCar(ditto, {'_id': 'car-1', 'color': 'blue'});
      await createColorIndex(ditto);
      expect(await evictCars(ditto, 'blue'), ['car-1']);
      expect(await _count(ditto, 'cars'), 0);
    });
  });
}
