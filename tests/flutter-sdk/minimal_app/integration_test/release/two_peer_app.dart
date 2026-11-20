// The app scripts/run-macos-release.sh builds in release mode as its second
// target. Not a test: two Ditto instances in this one process sync a document
// over TCP on 127.0.0.1, every peer-to-peer transport off. A sandboxed macOS
// release app needs `com.apple.security.network.server` to listen and
// `com.apple.security.network.client` to connect, both read from
// macos/Runner/Release.entitlements, so the transcript shows whether those
// entitlements are in the signed app.
//
// Prints `transcript: two-peer sync: <_id>` or `transcript: error: ...`, then
// `transcript: closed: true`, and exits.
import 'dart:async';
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/widgets.dart';

const _license = String.fromEnvironment('DITTO_LICENSE');

void _emit(String line) => debugPrint('transcript: $line');

Future<Ditto> _open(String directory) async {
  final ditto = await Ditto.open(DittoConfig(persistenceDirectory: directory));
  ditto.setOfflineOnlyLicenseToken(_license);
  ditto.updateTransportConfig((config) {
    config.peerToPeer.bluetoothLE.isEnabled = false;
    config.peerToPeer.lan.isEnabled = false;
    config.peerToPeer.awdl.isEnabled = false;
    config.peerToPeer.wifiAware.isEnabled = false;
  });
  return ditto;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Ditto.init();
  final root = await Directory.systemTemp.createTemp('ditto_release_');
  // No ServerSocket probe for a free port: binding one needs the same
  // entitlement this app is checking.
  final port = 40000 + pid % 20000;
  Ditto? listener;
  Ditto? connector;
  SyncSubscription? subscription;
  StoreObserver? observer;
  StreamSubscription<QueryResult>? changes;
  try {
    listener = await _open('${root.path}/listener');
    connector = await _open('${root.path}/connector');
    listener.updateTransportConfig((config) {
      config.listen.tcp
        ..isEnabled = true
        ..interfaceIP = '127.0.0.1'
        ..port = port;
    });
    connector.updateTransportConfig((config) {
      config.connect.tcpServers.add('127.0.0.1:$port');
    });
    listener.sync.start();
    connector.sync.start();

    final synced = Completer<String>();
    subscription = connector.sync.registerSubscription('SELECT * FROM cars');
    observer = connector.store.registerObserver('SELECT * FROM cars');
    changes = observer.changes.listen((result) {
      final ids = [for (final item in result.items) '${item.value['_id']}'];
      if (ids.isNotEmpty && !synced.isCompleted) synced.complete(ids.first);
    });
    await listener.store.execute(
      'INSERT INTO cars DOCUMENTS (:car)',
      arguments: {
        'car': {'_id': 'car-from-listener'},
      },
    );
    final id = await synced.future.timeout(const Duration(seconds: 30));
    _emit('two-peer sync: $id');
  } catch (error) {
    _emit('error: $error');
  } finally {
    await changes?.cancel();
    observer?.cancel();
    subscription?.cancel();
    await connector?.close();
    await listener?.close();
  }
  _emit('closed: true');
  exit(0);
}
