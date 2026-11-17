// Web probes: logging export, licensing and the in-memory store.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../web_harness.dart';

void lifecycleProbes() {
  testWidgets('exportLogs throws UnsupportedError', (t) async {
    await withWebDitto((ditto) async {
      final outcome = await outcomeOf(
        () => DittoLogger.exportLogs('/logs/ditto.jsonl.gz'),
      );
      record('exportLogs', outcome);
      // Thrown synchronously at the call, not through the returned Future.
      expect(
        outcome,
        'sync UnsupportedError: Not supported on the web platform',
      );
    });
  });

  testWidgets('bad offline license on web', (t) async {
    await Ditto.init();
    final ditto = await Ditto.open(DittoConfig());
    try {
      final outcome = await outcomeOf(
        () => ditto.setOfflineOnlyLicenseToken('not-a-license'),
      );
      record('setOfflineOnlyLicenseToken(bad)', outcome);
      // Observed: an invalid token is accepted on web; nothing is thrown.
      expect(outcome, 'ok');
    } finally {
      await ditto.close();
    }
  });

  testWidgets('close then reopen in the same page loses data', (t) async {
    await withWebDitto((ditto) async {
      await ditto.store.execute(
        'INSERT INTO web_reopen DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE',
        arguments: {
          'doc': {'_id': 'kept?', 'n': 1},
        },
      );
      final written = await ditto.store.execute('SELECT * FROM web_reopen');
      record('reopen: before close', '${written.items.length} doc(s)');
      expect(written.items.length, 1);
    });
    await withWebDitto((ditto) async {
      final read = await ditto.store.execute('SELECT * FROM web_reopen');
      record('reopen: after close and open', '${read.items.length} doc(s)');
      // Observed: the in-memory store outlives close() within the page, so
      // the document is still there (it is lost on a page reload; see
      // web-probe.py web_reload_persistence).
      expect(read.items.length, 1);
    });
  });
}
