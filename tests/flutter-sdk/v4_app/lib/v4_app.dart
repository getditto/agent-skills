// ditto_live 4.14.x only: OfflinePlaygroundIdentity and SiteID are deprecated
// there and removed in 5.0.
// ignore_for_file: deprecated_member_use

import 'package:ditto_live/ditto_live.dart';

// snippet:start flutter-v4-open
/// ditto_live 4.14.x: an identity object instead of a DittoConfig, and
/// startSync() on the instance instead of sync.start().
Future<Ditto> openV4Ditto({
  required String license,
  String persistenceDirectory = 'ditto',
  void Function(TransportConfig config)? transports,
}) async {
  await Ditto.init();
  final ditto = await Ditto.open(
    identity: OfflinePlaygroundIdentity(
      appID: 'REPLACE_ME_WITH_YOUR_APP_ID',
      siteID: SiteID.fromInt(2),
    ),
    persistenceDirectory: persistenceDirectory,
  );
  ditto.setOfflineOnlyLicenseToken(license);
  if (transports != null) ditto.updateTransportConfig(transports);
  ditto.startSync();
  return ditto;
}
// snippet:end flutter-v4-open

/// Opens a 4.14 instance, writes one car, reads it back and closes. Returns
/// the transcript.
Future<List<String>> runV4App({
  required String license,
  required String persistenceDirectory,
}) async {
  final lines = <String>[];
  final ditto = await openV4Ditto(
    license: license,
    persistenceDirectory: persistenceDirectory,
    // Offline fixture: no peer-to-peer radios before sync starts.
    transports: (config) {
      config.peerToPeer.bluetoothLE.isEnabled = false;
      config.peerToPeer.lan.isEnabled = false;
      config.peerToPeer.awdl.isEnabled = false;
      config.peerToPeer.wifiAware.isEnabled = false;
    },
  );
  try {
    await ditto.store.execute(
      'INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE',
      arguments: {
        'car': {'_id': 'blue-toyota', 'make': 'Toyota', 'color': 'blue'},
      },
    );
    final result = await ditto.store.execute(
      'SELECT * FROM cars WHERE color = :color',
      arguments: {'color': 'blue'},
    );
    lines.add('v4 read-back make: ${result.items.first.value['make']}');
    final version = RegExp(r'\d+\.\d+\.\d+').firstMatch(Ditto.version);
    lines.add('v4 SDK version: ${version?.group(0)}');
  } finally {
    ditto.stopSync();
    await ditto.close();
  }
  lines.add('v4 closed: ${ditto.isClosed}');
  return lines;
}
