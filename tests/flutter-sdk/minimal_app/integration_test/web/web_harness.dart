// Shared setup for the Flutter Web probes (`flutter drive -d chrome`). No
// dart:io: web has no filesystem, so there is no temporary directory, and
// every instance uses `persistenceDirectory: null` (the in-memory store).
// Compiles against ditto_live 5.0.4 and later. Self-contained: a web
// `flutter drive` target's directory is its app root, so it cannot import
// files above integration_test/web/ (such as probes/harness.dart, which
// also needs dart:io). The shared helpers below mirror that harness.
import 'dart:async';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');

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

/// The lines this run reports. The driver (test_driver/integration_test.dart)
/// prints each as `transcript: <line>`, so the drive log keeps every observed
/// value next to the pass/fail result.
final List<String> transcript = <String>[];

late IntegrationTestWidgetsFlutterBinding _binding;

/// [ensureProbeBinding] plus the transcript channel. Call first in `main`.
void ensureWebProbeBinding() {
  _binding = ensureProbeBinding();
}

/// Adds `<probe>: <value>` to the transcript the driver prints.
void record(String probe, Object? value) {
  transcript.add('$probe: $value');
  _binding.reportData = <String, dynamic>{'transcript': transcript};
}

/// Runs [action] and describes how it ended: `ok`, `ok: <value>`,
/// `sync <Type>: <message>` (thrown at the call) or `async <Type>: <message>`
/// (the returned Future failed). Probes assert this string, so a change in
/// either the error type, its text or when it is thrown breaks them.
Future<String> outcomeOf(FutureOr<Object?> Function() action) async {
  final FutureOr<Object?> pending;
  try {
    pending = action();
  } catch (error) {
    return 'sync ${error.runtimeType}: ${_message(error)}';
  }
  if (pending is! Future<Object?>) {
    return pending == null ? 'ok' : 'ok: $pending';
  }
  try {
    final value = await pending;
    return value == null ? 'ok' : 'ok: $value';
  } catch (error) {
    return 'async ${error.runtimeType}: ${_message(error)}';
  }
}

/// [outcomeOf] for a `void` call: its value is ignored (5.0.4's
/// `sync.start()` is declared `void` but returns `true` at run time).
Future<String> outcomeOfVoid(void Function() action) => outcomeOf(() {
  action();
  return null;
});

String _message(Object error) => switch (error) {
  UnsupportedError(:final message) => '$message',
  _ => '$error',
};

/// Opens Ditto with `persistenceDirectory: null`, runs [body], and always
/// closes the instance. Sets the offline license. With [p2pOff] (the default)
/// every peer-to-peer transport is turned off, one by one, before [body];
/// on web they are already off, but the probes follow the native rule.
/// Ditto logging stays at its default: the native harness turns it off only
/// to work around a native GC-finalizer defect.
Future<void> withWebDitto(
  Future<void> Function(Ditto ditto) body, {
  bool p2pOff = true,
}) async {
  expect(license, isNotEmpty, reason: 'pass --dart-define=DITTO_LICENSE');
  // Required on 5.0.x, automatic from 5.1.0; memoized.
  await Ditto.init();
  final ditto = await Ditto.open(DittoConfig());
  try {
    ditto.setOfflineOnlyLicenseToken(license);
    if (p2pOff) disablePeerToPeer(ditto);
    await body(ditto);
  } finally {
    await ditto.close();
  }
}
