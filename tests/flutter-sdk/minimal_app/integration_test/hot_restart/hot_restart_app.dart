// The app scripts/hot-restart.py runs with `flutter run` (debug) to record
// what a hot restart (`R`) does to an open Ditto instance. Not a test, and
// not published code. Uses 5.1.0+ API (registerObserverV2).
//
// --dart-define=HOT_RESTART_MODE=
//   v1      open the default directory, keep a V1 observer live
//   v2      the same with a V2 observer (registerObserverV2)
//   holder  open through an app-scoped holder that retries while the
//           directory is still held by the instance the restart orphaned
//
// --dart-define=HOT_RESTART_PEER=true (native only): the first run also
// listens on TCP 127.0.0.1:$_peerPort and subscribes to its collection.
// When the restarted main() cannot open the default directory, it opens a
// second instance in its own directory, connects to that port and inserts
// a document, so the orphaned instance's observer has a remote change to
// deliver after the restart, as it would from a sync peer or server.
//
// Every line it prints starts with `HR: `. Ditto logging stays at its
// default. Nothing is closed: a hot restart runs main() again without
// running dispose() or any other cleanup, which is the case under record.
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const _license = String.fromEnvironment('DITTO_LICENSE');
const _mode = String.fromEnvironment('HOT_RESTART_MODE', defaultValue: 'v1');
const _peer = bool.fromEnvironment('HOT_RESTART_PEER');
const _peerPort = 45631;

void _say(String line) => debugPrint('HR: $line');

/// App-scoped: opens Ditto once per run of main() and hands every caller the
/// same instance. A hot restart resets this static along with the rest of
/// the Dart heap, so after one it opens again; while the directory is still
/// held, it retries for up to [patience].
final class DittoHolder {
  static Future<Ditto>? _instance;

  static Future<Ditto> instance({
    Duration patience = const Duration(seconds: 20),
  }) => _instance ??= _open(patience);

  static Future<Ditto> _open(Duration patience) async {
    await Ditto.init();
    final deadline = DateTime.now().add(patience);
    for (var attempt = 1; ; attempt++) {
      try {
        final ditto = await Ditto.open(DittoConfig());
        _say('holder: open ok on attempt $attempt');
        return ditto;
      } on DittoException catch (error) {
        if (DateTime.now().isAfter(deadline)) rethrow;
        if (attempt == 1) _say('holder: attempt 1 failed: $error');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }
}

Future<void> _run() async {
  _say('start mode=$_mode web=$kIsWeb');
  final Ditto ditto;
  try {
    if (_mode == 'holder') {
      ditto = await DittoHolder.instance();
    } else {
      await Ditto.init();
      ditto = await Ditto.open(DittoConfig());
      _say('open ok');
    }
  } catch (error) {
    _say('open failed: ${error.runtimeType}: $error');
    if (_peer && !kIsWeb) await _writeFromPeer();
    return;
  }
  ditto.setOfflineOnlyLicenseToken(_license);
  if (!kIsWeb) {
    ditto.updateTransportConfig((config) {
      config.peerToPeer.bluetoothLE.isEnabled = false;
      config.peerToPeer.lan.isEnabled = false;
      config.peerToPeer.awdl.isEnabled = false;
      config.peerToPeer.wifiAware.isEnabled = false;
    });
  }
  if (_peer && !kIsWeb) {
    ditto.updateTransportConfig((config) {
      config.listen.tcp
        ..isEnabled = true
        ..interfaceIP = '127.0.0.1'
        ..port = _peerPort;
    });
    ditto.sync.registerSubscription('SELECT * FROM restarts');
  }
  ditto.sync.start();
  final Stream<QueryResult> changes;
  if (_mode == 'v2') {
    // ignore: experimental_member_use
    changes = ditto.store.registerObserverV2('SELECT * FROM restarts').changes;
  } else {
    changes = ditto.store.registerObserver('SELECT * FROM restarts').changes;
  }
  // Never cancelled: the restart orphans it.
  changes.listen((result) => _say('observer items=${result.items.length}'));
  await ditto.store.execute(
    'INSERT INTO restarts DOCUMENTS (:doc)',
    arguments: {
      'doc': {'_id': 'run-${DateTime.now().microsecondsSinceEpoch}'},
    },
  );
  // Keep writing, so a live query of this instance has changes to deliver.
  Timer.periodic(const Duration(seconds: 2), (_) {
    unawaited(
      ditto.store
          .execute(
            'UPDATE restarts SET tick = :tick',
            arguments: {'tick': DateTime.now().millisecondsSinceEpoch},
          )
          .then<void>((_) {}, onError: (Object e) => _say('tick failed: $e')),
    );
  });
  _say('ready');
}

/// After a restart: a second peer in its own directory that writes one
/// document to the orphaned instance over TCP loopback.
Future<void> _writeFromPeer() async {
  final Ditto peer;
  try {
    peer = await Ditto.open(
      DittoConfig(persistenceDirectory: 'hot-restart-peer'),
    );
  } catch (error) {
    _say('peer open failed: $error');
    return;
  }
  peer.setOfflineOnlyLicenseToken(_license);
  peer.updateTransportConfig((config) {
    config.peerToPeer.bluetoothLE.isEnabled = false;
    config.peerToPeer.lan.isEnabled = false;
    config.peerToPeer.awdl.isEnabled = false;
    config.peerToPeer.wifiAware.isEnabled = false;
    config.connect.tcpServers.add('127.0.0.1:$_peerPort');
  });
  peer.sync.registerSubscription('SELECT * FROM restarts');
  peer.sync.start();
  peer.presence.observe((graph) {
    _say('peer: ${graph.remotePeers.length} remote peer(s) connected');
  });
  await peer.store.execute(
    'INSERT INTO restarts DOCUMENTS (:doc)',
    arguments: {
      'doc': {'_id': 'from-peer-${DateTime.now().microsecondsSinceEpoch}'},
    },
  );
  _say('peer: inserted a document for the orphaned instance');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_run());
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('hot restart probe')),
    ),
  );
}
