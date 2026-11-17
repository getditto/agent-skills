// Web probes: platform detection and peer-to-peer transports.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../web_harness.dart';

// snippet:start flutter-web-1
/// Turns on the peer-to-peer transports this platform has. Web has none,
/// and enabling one there throws a DittoException (from `sync.start()` on
/// 5.2.0, from `updateTransportConfig` on 5.0.4 and 5.1.0).
/// Check `kIsWeb` first: it is a constant, so web builds drop the rest.
/// Then decide with `Ditto.currentPlatform`, never `defaultTargetPlatform`,
/// which reports the browser's host OS on web.
void enablePeerToPeer(Ditto ditto) {
  if (kIsWeb) return;
  ditto.updateTransportConfig((config) {
    config.peerToPeer.bluetoothLE.isEnabled = true;
    config.peerToPeer.lan.isEnabled = true;
    switch (Ditto.currentPlatform) {
      case SupportedPlatform.ios || SupportedPlatform.macos:
        config.peerToPeer.awdl.isEnabled = true;
      case SupportedPlatform.android:
        config.peerToPeer.wifiAware.isEnabled = true;
      case SupportedPlatform.linux ||
          SupportedPlatform.windows ||
          SupportedPlatform.web:
        break;
    }
  });
}
// snippet:end flutter-web-1

/// The four peer-to-peer transports, as `name=isEnabled`.
String _p2pState(Ditto ditto) {
  final p2p = ditto.transportConfig.peerToPeer;
  return 'bluetoothLE=${p2p.bluetoothLE.isEnabled} lan=${p2p.lan.isEnabled} '
      'awdl=${p2p.awdl.isEnabled} wifiAware=${p2p.wifiAware.isEnabled}';
}

const _allOff = 'bluetoothLE=false lan=false awdl=false wifiAware=false';

/// The outcome of enabling [transport] on web, then starting sync. 5.0.4
/// and 5.1.0 reject the config in `updateTransportConfig`; 5.2.0 accepts it
/// and `sync.start()` throws the same DittoException.
(String, String) _rejected(String transport) => switch (pinnedLine) {
  '5.0' || '5.1' => (_unsupported(transport), 'not reached'),
  _ => ('ok', _unsupported(transport)),
};

String _unsupported(String transport) =>
    'sync DittoException: DittoException(<validation> Expected valid '
    'TransportConfig. Invalid config: The following P2P transports are '
    'enabled in the transport config but are not supported in the current '
    'environment: $transport)';

/// Applies [update], then starts sync, and returns how each step ended
/// (see [outcomeOf]); `sync.start()` is not attempted when [update] throws.
Future<(String, String)> _configureThenStart(
  Ditto ditto,
  void Function(TransportConfigBuilder config) update,
) async {
  final configured = await outcomeOfVoid(
    () => ditto.updateTransportConfig(update),
  );
  if (configured != 'ok') return (configured, 'not reached');
  final started = await outcomeOfVoid(ditto.sync.start);
  return (configured, started);
}

void platformProbes() {
  testWidgets('currentPlatform is web', (t) async {
    await Ditto.init();
    record('currentPlatform', Ditto.currentPlatform.name);
    expect(kIsWeb, isTrue);
    expect(Ditto.currentPlatform, SupportedPlatform.web);
  });

  testWidgets('defaultTargetPlatform is not web on web', (t) async {
    // TargetPlatform has no web value: on web it is the browser's host OS,
    // so a capability gate on it picks a native branch.
    record('defaultTargetPlatform', defaultTargetPlatform.name);
    expect(
      defaultTargetPlatform,
      isIn(<TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]),
    );
    // The anti-pattern: gating LAN on the host OS turns it on in the browser.
    await withWebDitto((ditto) async {
      final (configured, started) = await _configureThenStart(ditto, (config) {
        config.peerToPeer.lan.isEnabled =
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows;
      });
      record(
        'defaultTargetPlatform LAN gate: updateTransportConfig',
        configured,
      );
      record('defaultTargetPlatform LAN gate: sync.start', started);
      expect((configured, started), _rejected('LAN'));
      expect(ditto.sync.isActive, isFalse);
    });
    // The rule: kIsWeb first, then Ditto.currentPlatform.
    await withWebDitto((ditto) async {
      enablePeerToPeer(ditto);
      final outcome = await outcomeOfVoid(ditto.sync.start);
      record('sync.start after enablePeerToPeer', outcome);
      expect(outcome, 'ok');
      expect(_p2pState(ditto), _allOff);
      ditto.sync.stop();
    });
  });

  testWidgets('p2p transports disabled by default', (t) async {
    await withWebDitto(p2pOff: false, (ditto) async {
      record('default transports', _p2pState(ditto));
      expect(_p2pState(ditto), _allOff);
    });
  });

  testWidgets('withAllPeerToPeerEnabled is a no-op', (t) async {
    await withWebDitto(p2pOff: false, (ditto) async {
      final before = ditto.transportConfig;
      final enabled = before.withAllPeerToPeerEnabled(true);
      expect(enabled, before);
      ditto.updateTransportConfig(
        (config) => config.setAllPeerToPeerEnabled(true),
      );
      record('after setAllPeerToPeerEnabled(true)', _p2pState(ditto));
      expect(_p2pState(ditto), _allOff);
      final outcome = await outcomeOfVoid(ditto.sync.start);
      record('sync.start after setAllPeerToPeerEnabled(true)', outcome);
      expect(outcome, 'ok');
      ditto.sync.stop();
    });
  });

  testWidgets('enabling bluetoothLE then sync.start throws DittoException', (
    t,
  ) async {
    await withWebDitto((ditto) async {
      final (configured, started) = await _configureThenStart(
        ditto,
        (config) => config.peerToPeer.bluetoothLE.isEnabled = true,
      );
      record('bluetoothLE on: updateTransportConfig', configured);
      record('bluetoothLE on: sync.start', started);
      expect((configured, started), _rejected('BluetoothLE'));
      expect(ditto.sync.isActive, isFalse);
    });
  });

  testWidgets('defaultRootDirectory is empty', (t) async {
    await Ditto.init();
    record('defaultRootDirectory', '"${Ditto.defaultRootDirectory}"');
    expect(Ditto.defaultRootDirectory, isEmpty);
    await withWebDitto((ditto) async {
      record(
        'absolutePersistenceDirectory',
        ditto.absolutePersistenceDirectory,
      );
      // Not a path: the in-memory store's name for the default config.
      expect(
        ditto.absolutePersistenceDirectory,
        'ditto-00000000-0000-0000-0000-000000000000',
      );
    });
  });
}
