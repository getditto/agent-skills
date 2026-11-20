// The native branch of the published enablePeerToPeer (web/p2p_gate.dart),
// asserted on the resulting transport config without starting sync. Runs on
// macOS; the Android, Linux and Windows branches are untested. Each
// transport is set explicitly, so the 5.0.x setAllPeerToPeerEnabled defect
// does not apply.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../web/p2p_gate.dart';
import '../harness.dart';

void main() {
  ensureProbeBinding();

  testWidgets('enablePeerToPeer sets the platform transports', (t) async {
    // withDitto turns every transport off first.
    await withDitto(t, (ditto) async {
      enablePeerToPeer(ditto);
      final p2p = ditto.transportConfig.peerToPeer;
      final state =
          'bluetoothLE=${p2p.bluetoothLE.isEnabled} lan=${p2p.lan.isEnabled} '
          'awdl=${p2p.awdl.isEnabled} wifiAware=${p2p.wifiAware.isEnabled}';
      final expected = switch (Ditto.currentPlatform) {
        SupportedPlatform.ios || SupportedPlatform.macos =>
          'bluetoothLE=true lan=true awdl=true wifiAware=false',
        SupportedPlatform.android =>
          'bluetoothLE=true lan=true awdl=false wifiAware=true',
        SupportedPlatform.linux ||
        SupportedPlatform.windows ||
        SupportedPlatform.web =>
          'bluetoothLE=true lan=true awdl=false wifiAware=false',
      };
      expect(state, expected);
      expect(ditto.sync.isActive, isFalse);
    });
  });
}
