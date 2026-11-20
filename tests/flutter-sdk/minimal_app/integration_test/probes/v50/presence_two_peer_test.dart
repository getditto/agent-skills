// Two Ditto instances in one process, each in its own temporary directory,
// with every peer-to-peer transport off. The listener accepts TCP on
// 127.0.0.1:<port>; the other instance connects to it. Nothing else can reach
// either peer.
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-presence-3
/// Accepts TCP connections from other peers on [port]. The default
/// [interfaceIP], `[::]`, is the SDK's: every interface.
void listenForPeers(Ditto ditto, int port, {String interfaceIP = '[::]'}) {
  ditto.updateTransportConfig((config) {
    config.listen.tcp
      ..isEnabled = true
      ..interfaceIP = interfaceIP
      ..port = port;
  });
}

/// Connects to a peer that listens at [hostAndPort], e.g. `10.0.0.5:4040`.
void connectToPeer(Ditto ditto, String hostAndPort) {
  ditto.updateTransportConfig((config) {
    config.connect.tcpServers.add(hostAndPort);
  });
}
// snippet:end flutter-presence-3

// snippet:start flutter-presence-1
/// Completes with the remote peer [peerKey] once presence reports it. Stop
/// the returned observer when you no longer need it.
(PresenceObserver, Future<Peer>) waitForPeer(Ditto ditto, String peerKey) {
  final seen = Completer<Peer>();
  final observer = ditto.presence.observe((graph) {
    for (final peer in graph.remotePeers) {
      if (peer.peerKey == peerKey && !seen.isCompleted) seen.complete(peer);
    }
  });
  return (observer, seen.future);
}
// snippet:end flutter-presence-1

// snippet:start flutter-presence-2
/// Refuses connections from [blockedPeerKey] and accepts every other peer.
/// Install with `ditto.presence.connectionRequestHandler = blockPeer(key)`.
/// A handler that throws refuses the connection too.
ConnectionRequestHandler blockPeer(String blockedPeerKey) =>
    (request) async => request.peerKey == blockedPeerKey
    ? ConnectionRequestAuthorization.deny
    : ConnectionRequestAuthorization.allow;
// snippet:end flutter-presence-2

const _peerTimeout = Duration(seconds: 20);
const _quietWindow = Duration(seconds: 5);

/// Opens a listening peer and a connecting peer on loopback; [body] gets
/// both and the listener's peer key.
Future<void> _withTwoPeers(
  WidgetTester t,
  Future<void> Function(Ditto listener, Ditto connector, String listenerKey)
  body, {
  ConnectionRequestHandler Function(String listenerKey)? connectorHandler,
}) async {
  final port = await freeLoopbackPort();
  await withDitto(t, (listener) async {
    await withDitto(t, (connector) async {
      listenForPeers(listener, port, interfaceIP: '127.0.0.1');
      connectToPeer(connector, '127.0.0.1:$port');
      final listenerKey = listener.presence.graph.localPeer.peerKey;
      if (connectorHandler != null) {
        connector.presence.connectionRequestHandler = connectorHandler(
          listenerKey,
        );
      }
      listener.sync.start();
      connector.sync.start();
      await body(listener, connector, listenerKey);
    });
  });
}

/// Inserts a car on [from] and reports the car IDs [to] holds, through a
/// subscription and an observer on [to].
Future<Future<void> Function()> _replicate(
  Ditto from,
  Ditto to,
  void Function(List<String> ids) onIds,
) async {
  final subscription = to.sync.registerSubscription('SELECT * FROM cars');
  final observer = to.store.registerObserver('SELECT * FROM cars');
  final changes = observer.changes.listen((result) {
    onIds([for (final item in result.items) item.value['_id'] as String]);
  });
  await from.store.execute(
    'INSERT INTO cars DOCUMENTS (:car)',
    arguments: {
      'car': {'_id': 'car-from-listener'},
    },
  );
  return () async {
    await changes.cancel();
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
  ensureProbeBinding();

  testWidgets('B sees A within 20 s', (t) async {
    await _withTwoPeers(t, (listener, connector, listenerKey) async {
      final (observer, seen) = waitForPeer(connector, listenerKey);
      try {
        final peer = await seen.timeout(_peerTimeout);
        expect(peer.peerKey, listenerKey);
      } finally {
        observer.stop();
      }
    });
  });

  testWidgets('doc written on A syncs to B', (t) async {
    await _withTwoPeers(t, (listener, connector, listenerKey) async {
      var ids = <String>[];
      final stop = await _replicate(listener, connector, (now) => ids = now);
      try {
        await waitUntil(() => ids.isNotEmpty, timeout: _peerTimeout);
        expect(ids, ['car-from-listener']);
      } finally {
        await stop();
      }
    });
  });

  testWidgets('handler deny blocks', (t) async {
    final asked = <String>[];
    await _withTwoPeers(
      t,
      connectorHandler: (listenerKey) {
        final block = blockPeer(listenerKey);
        return (request) {
          asked.add(request.peerKey);
          return block(request);
        };
      },
      (listener, connector, listenerKey) async {
        await waitUntil(() => asked.isNotEmpty, timeout: _peerTimeout);
        expect(asked.first, listenerKey);
        var ids = <String>[];
        final stop = await _replicate(listener, connector, (now) => ids = now);
        try {
          await holdsFor(() => ids.isEmpty, _quietWindow, reason: 'denied');
        } finally {
          await stop();
        }
      },
    );
  });

  testWidgets('handler throw denies', (t) async {
    final asked = <String>[];
    await _withTwoPeers(
      t,
      connectorHandler: (_) => (request) async {
        asked.add(request.peerKey);
        throw StateError('handler failed');
      },
      (listener, connector, listenerKey) async {
        await waitUntil(() => asked.isNotEmpty, timeout: _peerTimeout);
        expect(asked.first, listenerKey);
        var ids = <String>[];
        final stop = await _replicate(listener, connector, (now) => ids = now);
        try {
          await holdsFor(() => ids.isEmpty, _quietWindow, reason: 'denied');
        } finally {
          await stop();
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
