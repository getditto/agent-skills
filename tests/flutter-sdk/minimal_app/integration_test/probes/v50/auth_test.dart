import 'dart:developer';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// `.invalid` never resolves (RFC 6761), so these probes need no network.
const _server = DittoConfigConnectServer(url: 'https://REPLACE_ME.invalid');

// snippet:start flutter-connect-1
/// Starts sync against a Ditto server. [fetchToken] returns a token from your
/// identity provider. With a server connect config, sync.start() throws
/// DittoException unless an expiration handler is set first.
Future<void> startServerSync(
  Ditto ditto,
  Future<String> Function() fetchToken,
) async {
  await ditto.auth.setExpirationHandler((ditto, timeUntilExpiration) async {
    // The handler can run after close() (seen on 5.0.4); login() would
    // throw DittoClosedException.
    if (ditto.isClosed) return;
    try {
      final response = await ditto.auth.login(
        token: await fetchToken(),
        provider: 'REPLACE_ME_WITH_YOUR_PROVIDER',
      );
      // A rejected login is reported here, not thrown.
      final error = response.exception;
      if (error != null) log('Ditto login failed: $error', name: 'auth');
    } catch (error) {
      // Thrown: fetchToken() failed, or Ditto closed while logging in.
      log('Ditto login threw: $error', name: 'auth');
    }
  });
  ditto.sync.start();
}
// snippet:end flutter-connect-1

/// `auth.login` against [_server], per pinned line. Asserted exactly.
const _loginFailure = {
  '5.0': 'DittoException(Error logging in. Status code 1. Client info: null)',
  '5.1': 'DittoException(Error logging in. Status code 1. Client info: null)',
  '5.2': 'DittoException(Error logging in. Status code 1. Client info: null)',
};

void main() {
  ensureProbeBinding();

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
      await startServerSync(ditto, () async => 'REPLACE_ME_WITH_A_TOKEN');
      expect(ditto.sync.isActive, isTrue);

      final response = await ditto.auth
          .login(
            token: 'REPLACE_ME',
            provider: Authenticator.developmentProvider,
          )
          .timeout(const Duration(seconds: 20));
      log('login response: ${response.exception}', name: 'probe');
      expect(_loginFailure, contains(pinnedLine));
      expect(
        response.exception,
        isA<DittoException>().having(
          (e) => e.toString(),
          'toString()',
          _loginFailure[pinnedLine],
        ),
      );
    });
  });
}
