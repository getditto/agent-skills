import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('close is idempotent', (t) async {
    await withDitto(t, (ditto) async {
      // snippet:start flutter-connect-2
      await ditto.close();
      await ditto.close(); // a second close returns without doing anything
      // snippet:end flutter-connect-2
      expect(ditto.isClosed, isTrue);
    });
  });

  testWidgets('api after close throws DittoClosedException', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.close();

      // `execute` is async: the call returns a Future that fails.
      late Future<QueryResult> pending;
      expect(() {
        pending = ditto.store.execute('SELECT * FROM probes');
      }, returnsNormally);
      await expectLater(pending, throwsA(isA<DittoClosedException>()));

      // Synchronous APIs throw at the call.
      expect(() => ditto.sync.start(), throwsA(isA<DittoClosedException>()));
      expect(
        () => ditto.store.registerObserver('SELECT * FROM probes'),
        throwsA(isA<DittoClosedException>()),
      );
    });
  });
}
