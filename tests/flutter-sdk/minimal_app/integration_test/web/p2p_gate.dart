// The published platform gate for peer-to-peer transports. No test or
// dart:io imports, so both the web probes (groups/platform_probes.dart) and
// the native probe (probes/v50/p2p_gate_test.dart) use it. Executed on web
// (Chrome) and macOS; the Android, Linux and Windows branches are untested.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

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
