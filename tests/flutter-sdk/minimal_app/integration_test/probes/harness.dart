// Shared setup for the native behavior probes. Compiles against ditto_live
// 5.0.4 and later, so it uses only the 5.0 API.
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');

/// `--dart-define=PROBE_DEFAULT_LOGGING=true` leaves Ditto logging at its
/// default (on) instead of turning it off in [withDitto].
const probeDefaultLogging = bool.fromEnvironment('PROBE_DEFAULT_LOGGING');

/// The pinned ditto_live line of this run, e.g. `5.0`.
String get pinnedLine {
  final match = RegExp(r'^(\d+\.\d+)\.').firstMatch(expectedVersion);
  if (match == null) {
    throw StateError('pass --dart-define=DITTO_VERSION=<x.y.z>');
  }
  return match.group(1)!;
}

/// Opens a Ditto instance in a fresh temporary directory, runs [body], and
/// always closes the instance and deletes the directory afterwards.
///
/// Ditto logging is disabled unless [probeDefaultLogging] (see below). The offline license is set for small-peers-only configs (the default).
/// With [p2pOff] every peer-to-peer transport (Bluetooth LE, LAN, AWDL,
/// Wi-Fi Aware) is disabled before [body] runs; [body] starts sync itself.
Future<void> withDitto(
  WidgetTester t,
  Future<void> Function(Ditto ditto) body, {
  bool p2pOff = true,
  DittoConfigConnect? connect,
}) async {
  expect(license, isNotEmpty, reason: 'pass --dart-define=DITTO_LICENSE');
  // Required on 5.0.x, automatic from 5.1.0; memoized.
  await Ditto.init();
  // Workaround, not a recommendation (README, Findings that changed a
  // research lead, entry 1): when one process closes Ditto and opens it
  // again, a native handle (an internal Transaction, a SyncSubscription)
  // finalized by the GC after close() logs from inside the GC finalizer and
  // aborts (5.0.4) or deadlocks (5.1.0, 5.2.0) the process on macOS debug.
  // Logging off keeps the suite runnable. --dart-define=
  // PROBE_DEFAULT_LOGGING=true keeps Ditto's default (logging on) instead.
  if (!probeDefaultLogging) DittoLogger.isEnabled = false;
  final directory = await Directory.systemTemp.createTemp('ditto_probe_');
  final ditto = await Ditto.open(
    connect == null
        ? DittoConfig(persistenceDirectory: directory.path)
        : DittoConfig(persistenceDirectory: directory.path, connect: connect),
  );
  try {
    if (connect == null) ditto.setOfflineOnlyLicenseToken(license);
    if (p2pOff) disablePeerToPeer(ditto);
    await body(ditto);
  } finally {
    await ditto.close();
    await directory.delete(recursive: true);
  }
}

/// Turns off every peer-to-peer transport the 5.0 API can name. Multicast
/// (5.1+) is off by default.
void disablePeerToPeer(Ditto ditto) {
  ditto.updateTransportConfig((config) {
    config.peerToPeer.bluetoothLE.isEnabled = false;
    config.peerToPeer.lan.isEnabled = false;
    config.peerToPeer.awdl.isEnabled = false;
    config.peerToPeer.wifiAware.isEnabled = false;
  });
}

/// Completes when [condition] holds, polling every 50 ms; fails after
/// [timeout].
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after $timeout${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Fails as soon as [condition] stops holding during [window]. A bounded
/// negative check: "nothing arrives within [window]".
Future<void> holdsFor(
  bool Function() condition,
  Duration window, {
  String? reason,
}) async {
  final deadline = DateTime.now().add(window);
  while (DateTime.now().isBefore(deadline)) {
    if (!condition()) fail('condition broke within $window: ${reason ?? ''}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue, reason: reason);
}

/// A TCP port that was free a moment ago on 127.0.0.1.
Future<int> freeLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
