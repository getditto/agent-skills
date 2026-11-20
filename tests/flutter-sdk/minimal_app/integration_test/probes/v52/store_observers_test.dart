// Store.observers: 5.2.0+.
import 'dart:developer';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-observers-5
/// 5.2.0+: logs every V1 observer that has not been cancelled, including
/// ones whose `changes` listener is gone. Call it to look for leaks; returns
/// their queries.
List<String> logLiveObservers(Ditto ditto) {
  final queries = [
    for (final observer in ditto.store.observers) observer.queryString,
  ];
  log('${queries.length} live observer(s): $queries', name: 'ditto');
  return queries;
}
// snippet:end flutter-observers-5

void main() {
  ensureProbeBinding();

  testWidgets(
    'Store.observers contains a live v1 observer after its stream is cancelled',
    (t) async {
      await withDitto(t, (ditto) async {
        final observer = ditto.store.registerObserver('SELECT * FROM cars');
        final subscription = observer.changes.listen((_) {});
        await subscription.cancel();

        expect(logLiveObservers(ditto), ['SELECT * FROM cars']);
        expect(ditto.store.observers, contains(observer));
        expect(observer.isCancelled, isFalse);

        observer.cancel();
        expect(logLiveObservers(ditto), isEmpty);

        await ditto.close();
        expect(ditto.store.observers, isEmpty);
      });
    },
  );
}
