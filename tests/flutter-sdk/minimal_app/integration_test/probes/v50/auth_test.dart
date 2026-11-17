import 'dart:developer';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

// `.invalid` never resolves (RFC 6761), so these probes need no network.
const _server = DittoConfigConnectServer(url: 'https://REPLACE_ME.invalid');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'server connect without expiration handler: sync.start throws DittoException',
    (t) async {
      await withDitto(t, connect: _server, (ditto) async {
        expect(() => ditto.sync.start(), throwsA(isA<DittoException>()));
        expect(ditto.sync.isActive, isFalse);
      });
    },
  );

  testWidgets('login failure in AuthResponse.exception', (t) async {
    await withDitto(t, connect: _server, (ditto) async {
      // snippet:start flutter-connect-1
      await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
        // The handler can be delivered after close(); login() would throw.
        if (ditto.isClosed) return;
        final response = await ditto.auth.login(
          token: 'REPLACE_ME_WITH_A_TOKEN',
          provider: 'REPLACE_ME_WITH_YOUR_PROVIDER',
        );
        // login() reports failure here rather than throwing.
        final error = response.exception;
        if (error != null) log('Ditto login failed: $error', name: 'auth');
      });
      ditto.sync.start(); // throws DittoException without the handler
      // snippet:end flutter-connect-1
      expect(ditto.sync.isActive, isTrue);

      final response = await ditto.auth
          .login(
            token: 'REPLACE_ME',
            provider: Authenticator.developmentProvider,
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('login response: ${response.exception}');
      expect(response.exception, isA<DittoException>());
    });
  });
}
