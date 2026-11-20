import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-connect-2
/// Closes Ditto when the app shuts down. close() is idempotent: calling it
/// again returns without doing anything.
Future<void> shutDownDitto(Ditto ditto) async {
  await ditto.close();
}
// snippet:end flutter-connect-2

void main() {
  ensureProbeBinding();

  testWidgets('close is idempotent', (t) async {
    await withDitto(t, (ditto) async {
      await shutDownDitto(ditto);
      await shutDownDitto(ditto);
      expect(ditto.isClosed, isTrue);
    });
  });

  testWidgets('api after close throws DittoClosedException', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.close();

      // `execute` is async: the call returns a Future that fails.
      late Future<QueryResult> pending;
      expect(() {
        pending = ditto.store.execute('SELECT * FROM cars');
      }, returnsNormally);
      await expectLater(pending, throwsA(isA<DittoClosedException>()));

      // Synchronous APIs throw at the call.
      expect(() => ditto.sync.start(), throwsA(isA<DittoClosedException>()));
      expect(
        () => ditto.store.registerObserver('SELECT * FROM cars'),
        throwsA(isA<DittoClosedException>()),
      );
    });
  });

  // 5.0.x Correction: close() leaves V1 observers' isCancelled false; 5.1.0+
  // reports them cancelled.
  testWidgets('v1 observer isCancelled after close, per line', (t) async {
    await withDitto(t, (ditto) async {
      final observer = ditto.store.registerObserver('SELECT * FROM cars');
      final subscription = observer.changes.listen((_) {});
      try {
        expect(observer.isCancelled, isFalse);

        await ditto.close();
        expect(observer.isCancelled, pinnedLine == '5.0' ? isFalse : isTrue);
      } finally {
        await subscription.cancel();
      }
    });
  });

  // 5.0.x Correction: close() keeps DittoLogger.customLogCallback; 5.1.0+
  // resets it to null.
  testWidgets('close and customLogCallback, per line', (t) async {
    await withDitto(t, (ditto) async {
      DittoLogger.customLogCallback = (level, message) {};
      try {
        expect(DittoLogger.customLogCallback, isNotNull);

        await ditto.close();
        expect(
          DittoLogger.customLogCallback,
          pinnedLine == '5.0' ? isNotNull : isNull,
        );
      } finally {
        // Later probes in this process must not inherit the callback.
        DittoLogger.customLogCallback = null;
      }
    });
  });
}
