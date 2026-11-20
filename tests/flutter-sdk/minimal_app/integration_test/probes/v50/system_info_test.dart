import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-observability-1
/// Reads how many bytes Ditto uses on disk, per component (`fs_usage_store`,
/// `fs_usage_attachment`, `fs_usage_total`, ...). The Flutter SDK has no
/// disk-usage API; the local `system:system_info` collection reports it once
/// Ditto's periodic disk observer has run, so the map can be empty at first.
Future<Map<String, Object?>> diskUsage(Ditto ditto) async {
  final result = await ditto.store.execute(
    "SELECT * FROM system:system_info WHERE key LIKE 'fs_%'",
  );
  return {
    for (final item in result.items)
      item.value['key'] as String: item.value['value'],
  };
}
// snippet:end flutter-observability-1

void main() {
  ensureProbeBinding();

  testWidgets('system:system_info reports disk usage', (t) async {
    await withDitto(t, (ditto) async {
      await ditto.store.execute(
        'INSERT INTO cars DOCUMENTS (:car)',
        arguments: {
          'car': {'_id': 'car-1'},
        },
      );
      // Recorded, not asserted: right after open this has been empty.
      final first = await diskUsage(ditto);
      debugPrint('PROBE disk usage right after open: $first');
      // The usage keys arrive on every platform, within seconds and not all
      // at once.
      const usageKeys = [
        'fs_usage_attachment',
        'fs_usage_auth',
        'fs_usage_replication',
        'fs_usage_store',
        'fs_usage_total',
      ];
      // The device keys arrive on desktop and on the Android emulator. On the
      // iOS Simulator they never did (README, 2026-11-19).
      const deviceKeys = ['fs_device_available', 'fs_device_total'];
      final platform = Ditto.currentPlatform;
      final reportsDevice = switch (platform) {
        SupportedPlatform.macos ||
        SupportedPlatform.linux ||
        SupportedPlatform.windows ||
        SupportedPlatform.android => true,
        _ => false,
      };
      Future<Map<String, Object?>> poll(
        List<String> keys,
        Duration limit,
      ) async {
        final started = DateTime.now();
        var usage = await diskUsage(ditto);
        while (!keys.every(usage.containsKey) &&
            DateTime.now().difference(started) < limit) {
          await Future<void>.delayed(const Duration(seconds: 1));
          usage = await diskUsage(ditto);
        }
        debugPrint(
          'PROBE disk usage after '
          '${DateTime.now().difference(started).inSeconds} s: $usage',
        );
        return usage;
      }

      var usage = await poll(usageKeys, const Duration(seconds: 90));
      expect(usage.keys, containsAll(usageKeys));
      expect(
        usage['fs_usage_total'],
        isA<int>().having((v) => v, 'bytes', greaterThan(0)),
      );

      // Where they arrive, wait for the device keys. Elsewhere give them
      // 20 s, then record what is there.
      usage = await poll(
        deviceKeys,
        Duration(seconds: reportsDevice ? 90 : 20),
      );
      final present = deviceKeys.where(usage.containsKey).toList();
      debugPrint('PROBE device keys on ${platform.name}: $present');
      if (reportsDevice) {
        expect(present, deviceKeys);
      } else if (platform == SupportedPlatform.ios) {
        expect(present, isEmpty);
      }
    });
  });
}
