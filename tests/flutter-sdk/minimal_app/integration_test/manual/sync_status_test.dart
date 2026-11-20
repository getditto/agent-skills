// Manual probe, not run by CI or run-probes.sh: two instances over TCP
// loopback; the writer polls system:data_sync_info until the reader has
// confirmed the write's commit ID. A poll can hang (README, Manual records,
// "system:data_sync_info while peers connect"), so CI does not run this file.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../probes/harness.dart';
import '../probes/v50/sync_test.dart' show insertCarCommit, subscribeToCars;

// snippet:start flutter-sync-3
/// Whether a peer has confirmed every local commit up to [commitID], per the
/// local-only `system:data_sync_info` collection (one document per peer).
Future<bool> isSyncedTo(Ditto ditto, int commitID) async {
  final info = await ditto.store.execute('SELECT * FROM system:data_sync_info');
  return info.items.any((item) {
    final documents = item.value['documents'] as Map<String, dynamic>?;
    final syncedUpTo = documents?['synced_up_to_local_commit_id'];
    return syncedUpTo is int && syncedUpTo >= commitID;
  });
}
// snippet:end flutter-sync-3

const _peer = Duration(seconds: 20);

void main() {
  ensureProbeBinding();

  testWidgets('system:data_sync_info reaches the write commitID', (t) async {
    final port = await freeLoopbackPort();
    await withDitto(t, (writer) async {
      await withDitto(t, (reader) async {
        writer.updateTransportConfig((config) {
          config.listen.tcp
            ..isEnabled = true
            ..interfaceIP = '127.0.0.1'
            ..port = port;
        });
        reader.updateTransportConfig((config) {
          config.connect.tcpServers.add('127.0.0.1:$port');
        });
        final subscription = subscribeToCars(reader, 'blue');
        writer.sync.start();
        reader.sync.start();
        try {
          final commit = await insertCarCommit(writer, {
            '_id': 'car-1',
            'color': 'blue',
          });
          expect(commit, isNotNull);
          final deadline = DateTime.now().add(_peer);
          var polls = 0;
          while (true) {
            polls++;
            debugPrint('PROBE poll $polls');
            if (await isSyncedTo(writer, commit!)) break;
            if (DateTime.now().isAfter(deadline)) fail('not synced in $_peer');
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          debugPrint('PROBE synced after $polls polls');
          final info = await writer.store.execute(
            'SELECT * FROM system:data_sync_info',
          );
          final peer = info.items.single.value;
          expect(peer['_id'], reader.presence.graph.localPeer.peerKey);
          expect(peer['is_ditto_server'], isFalse);
          expect(
            (peer['documents'] as Map<String, dynamic>)['sync_session_status'],
            'Connected',
          );
        } finally {
          subscription.cancel();
        }
      });
    });
  });
}
