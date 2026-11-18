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
      expect(await diskUsage(ditto), isA<Map<String, Object?>>());
      const documented = [
        'fs_device_available',
        'fs_device_total',
        'fs_usage_attachment',
        'fs_usage_auth',
        'fs_usage_replication',
        'fs_usage_store',
        'fs_usage_total',
      ];
      final started = DateTime.now();
      var usage = <String, Object?>{};
      while (!documented.every(usage.containsKey) &&
          DateTime.now().difference(started) < const Duration(seconds: 90)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        usage = await diskUsage(ditto);
      }
      debugPrint(
        'PROBE disk usage after '
        '${DateTime.now().difference(started).inSeconds} s: $usage',
      );
      // Recorded: empty right after open; the keys arrive within seconds,
      // not all at once.
      expect(usage.keys, containsAll(documented));
      expect(
        usage['fs_usage_total'],
        isA<int>().having((v) => v, 'bytes', greaterThan(0)),
      );
    });
  });
}
