// Two Ditto instances in one process, each in its own temporary directory,
// with every peer-to-peer transport off. A listens on TCP 127.0.0.1:<port>;
// B connects to it. Nothing else can reach either peer.
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

const _peerTimeout = Duration(seconds: 20);
const _quietWindow = Duration(seconds: 5);

Future<void> _withTwoPeers(
  WidgetTester t,
  Future<void> Function(Ditto a, Ditto b, String aKey) body, {
  ConnectionRequestHandler Function(String aKey)? bHandler,
}) async {
  final port = await freeLoopbackPort();
  await withDitto(t, (a) async {
    await withDitto(t, (b) async {
      // snippet:start flutter-presence-3
      a.updateTransportConfig((config) {
        config.listen.tcp
          ..isEnabled = true
          ..interfaceIP = '127.0.0.1'
          ..port = port;
      });
      b.updateTransportConfig((config) {
        config.connect.tcpServers.add('127.0.0.1:$port');
      });
      // snippet:end flutter-presence-3
      final aKey = a.presence.graph.localPeer.peerKey;
      if (bHandler != null) {
        b.presence.connectionRequestHandler = bHandler(aKey);
      }
      a.sync.start();
      b.sync.start();
      await body(a, b, aKey);
    });
  });
}

/// Inserts a document on [a] and reports whether [b] has it, through a
/// subscription and an observer on [b].
Future<void Function()> _replicate(
  Ditto a,
  Ditto b,
  void Function(bool arrived) onState,
) async {
  final subscription = b.sync.registerSubscription('SELECT * FROM probes');
  final observer = b.store.registerObserver(
    'SELECT * FROM probes',
    onChange: (result) => onState(result.items.isNotEmpty),
  );
  await a.store.execute(
    'INSERT INTO probes DOCUMENTS (:doc)',
    arguments: {
      'doc': {'_id': 'from-a'},
    },
  );
  return () {
    observer.cancel();
    subscription.cancel();
  };
}

String _label(ConnectionType type) => switch (type) {
  ConnectionType.bluetooth => 'bluetooth',
  ConnectionType.accessPoint => 'accessPoint',
  ConnectionType.p2pWifi => 'p2pWifi',
  ConnectionType.webSocket => 'webSocket',
  // ConnectionType gains `multicast` in 5.1.0; this arm keeps the switch
  // exhaustive on every line (on 5.0.x it is unreachable).
  // ignore: unreachable_switch_case
  _ => 'other',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('B sees A within 20 s', (t) async {
    await _withTwoPeers(t, (a, b, aKey) async {
      // snippet:start flutter-presence-1
      final seen = Completer<Peer>();
      final observer = b.presence.observe((graph) {
        for (final peer in graph.remotePeers) {
          if (peer.peerKey == aKey && !seen.isCompleted) seen.complete(peer);
        }
      });
      // snippet:end flutter-presence-1
      try {
        final peer = await seen.future.timeout(_peerTimeout);
        expect(peer.peerKey, aKey);
      } finally {
        observer.stop();
      }
    });
  });

  testWidgets('doc written on A syncs to B', (t) async {
    await _withTwoPeers(t, (a, b, aKey) async {
      var arrived = false;
      final stop = await _replicate(a, b, (state) => arrived = state);
      try {
        await waitUntil(() => arrived, timeout: _peerTimeout);
      } finally {
        stop();
      }
    });
  });

  testWidgets('handler deny blocks', (t) async {
    final askedByA = Completer<void>();
    await _withTwoPeers(
      t,
      bHandler:
          (aKey) => (request) async {
            if (request.peerKey == aKey && !askedByA.isCompleted) {
              askedByA.complete();
            }
            // snippet:start flutter-presence-2
            return request.peerKey == aKey
                ? ConnectionRequestAuthorization.deny
                : ConnectionRequestAuthorization.allow;
            // snippet:end flutter-presence-2
          },
      (a, b, aKey) async {
        await askedByA.future.timeout(_peerTimeout);
        var arrived = false;
        final stop = await _replicate(a, b, (state) => arrived = state);
        try {
          await holdsFor(() => !arrived, _quietWindow, reason: 'denied');
        } finally {
          stop();
        }
      },
    );
  });

  testWidgets('handler throw denies', (t) async {
    final asked = Completer<void>();
    await _withTwoPeers(
      t,
      bHandler:
          (_) => (request) async {
            if (!asked.isCompleted) asked.complete();
            throw StateError('handler failed');
          },
      (a, b, aKey) async {
        await asked.future.timeout(_peerTimeout);
        var arrived = false;
        final stop = await _replicate(a, b, (state) => arrived = state);
        try {
          await holdsFor(() => !arrived, _quietWindow, reason: 'denied');
        } finally {
          stop();
        }
      },
    );
  });

  testWidgets('ConnectionType switch compiles', (t) async {
    await withDitto(t, (ditto) async {
      expect(ConnectionType.values.take(4).map(_label), [
        'bluetooth',
        'accessPoint',
        'p2pWifi',
        'webSocket',
      ]);
      // Four values on 5.0.x; 5.1.0 adds multicast (see v51).
      expect(ConnectionType.values, hasLength(pinnedLine == '5.0' ? 4 : 5));
    });
  });
}
