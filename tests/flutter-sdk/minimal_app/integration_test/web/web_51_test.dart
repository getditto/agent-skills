// The 5.1.0+ Flutter Web probes, a separate `flutter drive` target because
// DittoSyncPermissions and registerObserverWithSignalNext do not exist on
// 5.0.x (version-gated code is split by file, never by `skip:`):
//
//   tests/flutter-sdk/scripts/run-fixture.sh minimal_app chrome 5.1 \
//     integration_test/web/web_51_test.dart
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_harness.dart';

void main() {
  ensureWebProbeBinding();

  testWidgets('DittoSyncPermissions requiredPermissions is empty', (t) async {
    await Ditto.init();
    final permissions = DittoSyncPermissions();
    final required = await permissions.requiredPermissions();
    record('requiredPermissions', required);
    expect(required, isEmpty);
  });

  testWidgets('registerObserverWithSignalNext works on web', (t) async {
    await withWebDitto((ditto) async {
      final counts = <int>[];
      // No onChange: the test holds the one `changes` listener.
      // ignore: experimental_member_use
      final observer = ditto.store.registerObserverWithSignalNext(
        'SELECT * FROM web_signal_next',
      );
      var gate = Completer<void>();
      final changes = observer.changes.listen((result) {
        counts.add(result.items.length);
        unawaited(
          gate.future.then((_) {
            if (!observer.isCancelled) observer.signalNext();
          }),
        );
      });
      try {
        await waitUntil(() => counts.isNotEmpty, reason: 'initial result');
        for (var i = 0; i < 3; i++) {
          await ditto.store.execute(
            'INSERT INTO web_signal_next DOCUMENTS (:doc)',
            arguments: {
              'doc': {'_id': 'doc-$i'},
            },
          );
        }
        // Nothing more arrives until signalNext().
        await holdsFor(() => counts.length == 1, const Duration(seconds: 2));
        final first = gate;
        gate = Completer<void>()..complete();
        first.complete();
        await waitUntil(() => counts.length >= 2, reason: 'coalesced result');
        record('signalNext item counts', counts);
        expect(counts, [0, 3]);
      } finally {
        await changes.cancel();
        observer.cancel();
      }
    });
  });
}
