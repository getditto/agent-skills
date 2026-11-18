// Shared setup for the native behavior probes. Compiles against ditto_live
// 5.0.4 and later, so it uses only the 5.0 API.
import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');

/// `--dart-define=PROBE_DEFAULT_LOGGING=true` leaves Ditto logging at its
/// default (on) instead of turning it off in [withDitto].
const probeDefaultLogging = bool.fromEnvironment('PROBE_DEFAULT_LOGGING');

/// The longest a single probe may run. integration_test defaults to no
/// timeout, so a hang would stall the run until the outer `timeout` in
/// run-fixture.sh.
const probeTimeout = Timeout(Duration(minutes: 2));

/// Initializes the integration-test binding with [probeTimeout] as the
/// per-test timeout. Call first in every probe file's `main`.
IntegrationTestWidgetsFlutterBinding ensureProbeBinding() =>
    IntegrationTestWidgetsFlutterBinding.ensureInitialized()
      ..defaultTestTimeout = probeTimeout;

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
/// Ditto logging is disabled unless [probeDefaultLogging] (see below). The
/// offline license is set for small-peers-only configs (the default). With
/// [p2pOff] every peer-to-peer transport (Bluetooth LE, LAN, AWDL, Wi-Fi
/// Aware) is disabled, one by one, before [body] runs; [body] starts sync
/// itself.
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
  final Ditto ditto;
  try {
    ditto = await Ditto.open(
      connect == null
          ? DittoConfig(persistenceDirectory: directory.path)
          : DittoConfig(persistenceDirectory: directory.path, connect: connect),
    );
  } catch (_) {
    await _deleteDirectory(directory);
    rethrow;
  }
  try {
    if (connect == null) ditto.setOfflineOnlyLicenseToken(license);
    if (p2pOff) disablePeerToPeer(ditto);
    await body(ditto);
  } finally {
    await ditto.close();
    await _deleteDirectory(directory);
  }
}

/// Deletes [directory], retrying for a few seconds: on Windows, files the
/// closed instance held can stay locked briefly. On Windows a directory still
/// locked after the retries is left behind and reported on the
/// `cleanup:` line instead of failing the probe (README, Windows desktop
/// findings): the probe's own assertions have already run.
Future<void> _deleteDirectory(Directory directory) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      if (attempt == 10) {
        if (!Platform.isWindows) rethrow;
        debugPrint(
          'cleanup: still locked after close: ${error.message}, '
          'errno ${error.osError?.errorCode}: ${directory.path}',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

/// Turns off every peer-to-peer transport the 5.0 API can name, one by one:
/// on 5.0.x, `setAllPeerToPeerEnabled(false)` leaves AWDL and Wi-Fi Aware on.
/// Multicast (5.1+) is off by default.
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
