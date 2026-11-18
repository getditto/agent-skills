import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-sync-1
/// Syncs the cars of [color] from other peers until the returned
/// subscription is cancelled. A subscription query cannot use LIMIT or
/// ORDER BY: registering one throws.
SyncSubscription subscribeToCars(Ditto ditto, String color) =>
    ditto.sync.registerSubscription(
      'SELECT * FROM cars WHERE color = :color',
      arguments: {'color': color},
    );
// snippet:end flutter-sync-1

// snippet:start flutter-sync-2
/// Inserts [car] and returns the ID of the local commit that holds it.
/// Compare it with a peer's `synced_up_to_local_commit_id` in the
/// `system:data_sync_info` collection to see whether that peer has it.
Future<int?> insertCarCommit(Ditto ditto, Map<String, dynamic> car) async {
  final result = await ditto.store.execute(
    'INSERT INTO cars DOCUMENTS (:car)',
    arguments: {'car': car},
  );
  return result.commitID; // null for a query that changed nothing
}
// snippet:end flutter-sync-2

Object? _thrownBy(void Function() call) {
  try {
    call();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  ensureProbeBinding();

  testWidgets('registerSubscription is listed until cancelled', (t) async {
    await withDitto(t, (ditto) async {
      final subscription = subscribeToCars(ditto, 'blue');
      expect(
        subscription.queryString,
        'SELECT * FROM cars WHERE color = :color',
      );
      expect(subscription.queryArguments, {'color': 'blue'});
      expect(subscription.isCancelled, isFalse);
      expect(ditto.sync.subscriptions, contains(subscription));

      subscription.cancel();
      expect(subscription.isCancelled, isTrue);
      expect(ditto.sync.subscriptions, isNot(contains(subscription)));
      subscription.cancel(); // a second cancel is a no-op
    });
  });

  testWidgets('a dropped subscription handle stays registered', (t) async {
    await withDitto(t, (ditto) async {
      subscribeToCars(ditto, 'red'); // handle discarded
      final listed = ditto.sync.subscriptions;
      expect(listed.map((s) => s.queryString), [
        'SELECT * FROM cars WHERE color = :color',
      ]);
      for (final subscription in listed) {
        subscription.cancel();
      }
      expect(ditto.sync.subscriptions, isEmpty);
    });
  });

  for (final query in [
    'SELECT * FROM cars LIMIT 10',
    'SELECT * FROM cars ORDER BY color',
  ]) {
    testWidgets('subscription with "$query" throws', (t) async {
      await withDitto(t, (ditto) async {
        final error = _thrownBy(() => ditto.sync.registerSubscription(query));
        expect(error, isA<DittoException>());
        expect(
          error.toString(),
          'DittoException(<dql> Unsupported feature: Limit or Order by)',
        );
        expect(ditto.sync.subscriptions, isEmpty);
      });
    });
  }

  testWidgets('commitID on a write, null on a read', (t) async {
    await withDitto(t, (ditto) async {
      final commit = await insertCarCommit(ditto, {'_id': 'car-1'});
      expect(commit, isNotNull);
      final read = await ditto.store.execute('SELECT * FROM cars');
      expect(read.commitID, isNull);
      final next = await insertCarCommit(ditto, {'_id': 'car-2'});
      expect(next, greaterThan(commit!));
    });
  });

  // 5.0.x: SyncSubscription.isCancelled reads the native flag only, so it
  // stays false after close(); 5.1.0+ also reports a closed Ditto.
  testWidgets('subscription isCancelled after close, per line', (t) async {
    await withDitto(t, (ditto) async {
      final subscription = subscribeToCars(ditto, 'blue');
      await ditto.close();
      expect(subscription.isCancelled, pinnedLine == '5.0' ? isFalse : isTrue);
    });
  });
}
