// observeTransportConditions and ConnectionType.multicast: 5.1.0+.
import 'dart:async';
import 'dart:developer';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('observeTransportConditions emits within 5 s', (t) async {
    await withDitto(t, (ditto) async {
      final events = <TransportConditionEvent>[];
      final observer = ditto.observeTransportConditions(events.add);
      try {
        ditto.sync.start();
        final first = Completer<TransportConditionEvent>();
        final subscription = observer.changes.listen((event) {
          if (!first.isCompleted) first.complete(event);
        });
        try {
          TransportConditionEvent? event;
          try {
            event = await first.future.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            event = null;
          }
          log(
            'transport condition within 5 s: $event; all: $events',
            name: 'probe',
          );
          // Recorded outcome; see tests/flutter-sdk/README.md.
          expect(event, isNull);
          expect(events, isEmpty);
        } finally {
          await subscription.cancel();
        }
      } finally {
        observer.stop();
      }
    });
  });

  testWidgets('ConnectionType switch includes multicast', (t) async {
    await withDitto(t, (ditto) async {
      // snippet:start flutter-presence-4
      String label(ConnectionType type) => switch (type) {
        ConnectionType.bluetooth => 'Bluetooth',
        ConnectionType.accessPoint => 'LAN',
        ConnectionType.p2pWifi => 'Wi-Fi P2P',
        ConnectionType.webSocket => 'WebSocket',
        ConnectionType.multicast => 'Multicast', // 5.1.0+
      };
      // snippet:end flutter-presence-4
      expect(ConnectionType.values.map(label), [
        'Bluetooth',
        'LAN',
        'Wi-Fi P2P',
        'WebSocket',
        'Multicast',
      ]);
    });
  });
}
