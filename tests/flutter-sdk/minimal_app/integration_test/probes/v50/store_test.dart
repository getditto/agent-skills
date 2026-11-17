import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

Future<int> _count(Ditto ditto) async =>
    (await ditto.store.execute('SELECT * FROM probes')).items.length;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transaction throw rolls back', (t) async {
    await withDitto(t, (ditto) async {
      // snippet:start flutter-store-2
      final attempt = ditto.store.transaction((tx) async {
        await tx.execute(
          'INSERT INTO probes DOCUMENTS (:doc)',
          arguments: {
            'doc': {'_id': 'a'},
          },
        );
        // Any exception thrown by the callback rolls the transaction back
        // and is rethrown to the caller.
        throw StateError('abort');
      });
      // snippet:end flutter-store-2
      await expectLater(attempt, throwsStateError);
      expect(await _count(ditto), 0);
    });
  });

  testWidgets('rollback action rolls back', (t) async {
    await withDitto(t, (ditto) async {
      // snippet:start flutter-store-3
      final action = await ditto.store.transaction((tx) async {
        await tx.execute(
          'INSERT INTO probes DOCUMENTS (:doc)',
          arguments: {
            'doc': {'_id': 'a'},
          },
        );
        // Returning rollback discards the writes; any other value commits.
        return TransactionCompletionAction.rollback;
      });
      // snippet:end flutter-store-3
      expect(action, TransactionCompletionAction.rollback);
      expect(await _count(ditto), 0);
    });
  });

  testWidgets('store.execute inside transaction throws', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.store.transaction((tx) async {
        await expectLater(
          ditto.store.execute('SELECT * FROM probes'),
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
      // snippet:start flutter-store-1
      final result = await ditto.store.execute(
        'INSERT INTO probes DOCUMENTS (:doc)',
        arguments: {
          'doc': {'_id': 'a', 'color': 'blue'},
        },
      );
      final ids = result.mutatedDocumentIDs(); // a method, not a getter
      // snippet:end flutter-store-1
      expect(ids, ['a']);
    });
  });

  testWidgets('CREATE INDEX and EVICT via execute succeed', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.store.execute(
        'INSERT INTO probes DOCUMENTS (:doc)',
        arguments: {
          'doc': {'_id': 'a', 'color': 'blue'},
        },
      );
      // snippet:start flutter-store-4
      await ditto.store.execute(
        'CREATE INDEX IF NOT EXISTS probes_color ON probes (color)',
      );
      // snippet:end flutter-store-4
      // snippet:start flutter-store-5
      final evicted = await ditto.store.execute(
        'EVICT FROM probes WHERE color = :color',
        arguments: {'color': 'blue'},
      );
      // snippet:end flutter-store-5
      expect(evicted.mutatedDocumentIDs(), ['a']);
      expect(await _count(ditto), 0);
    });
  });
}
