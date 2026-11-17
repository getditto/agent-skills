// snippet:start flutter-minimal-app
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

import 'temp_dir.dart';

/// Opens Ditto, observes a query, writes and reads back one document, then
/// closes everything. Returns the transcript; [onLine] sees each line as it
/// is produced.
Future<List<String>> runMinimalApp({
  required String license,
  void Function(String line)? onLine,
}) async {
  final lines = <String>[];
  void emit(String line) {
    lines.add(line);
    onLine?.call(line);
  }

  // Required on 5.0.x, automatic from 5.1.0; memoized, so always safe.
  await Ditto.init();
  final ditto = await Ditto.open(
    DittoConfig(persistenceDirectory: await createPersistenceDirectory()),
  );
  try {
    ditto.setOfflineOnlyLicenseToken(license);

    // Offline demo: no peer-to-peer radios. Web has none to turn off.
    if (!kIsWeb) {
      ditto.updateTransportConfig((config) {
        config.peerToPeer.bluetoothLE.isEnabled = false;
        config.peerToPeer.lan.isEnabled = false;
        config.peerToPeer.awdl.isEnabled = false;
      });
    }
    ditto.sync.start();

    final subscription = ditto.sync.registerSubscription('SELECT * FROM cars');
    final firstMatch = Completer<int>();
    final observer = ditto.store.registerObserver(
      'SELECT * FROM cars WHERE color = :color',
      arguments: {'color': 'blue'},
      onChange: (result) {
        final count = result.items.length;
        if (count > 0 && !firstMatch.isCompleted) firstMatch.complete(count);
      },
    );

    await ditto.store.execute(
      'INSERT INTO cars DOCUMENTS (:car)',
      arguments: {
        'car': {'make': 'Toyota', 'color': 'blue'},
      },
    );
    final count = await firstMatch.future.timeout(const Duration(seconds: 10));
    emit('observer: $count car(s)');

    final result = await ditto.store.execute(
      'SELECT * FROM cars WHERE color = :color',
      arguments: {'color': 'blue'},
    );
    final cars = result.items.toList();
    emit('read-back make: ${cars.first.value['make']}');

    final version = RegExp(r'\d+\.\d+\.\d+').firstMatch(Ditto.version);
    emit('SDK version: ${version?.group(0)}');
    emit('platform: ${Ditto.currentPlatform.name}');

    observer.cancel();
    subscription.cancel();
  } finally {
    await ditto.close();
  }
  emit('closed: ${ditto.isClosed}');
  return lines;
}
// snippet:end flutter-minimal-app
