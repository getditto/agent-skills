import 'dart:developer';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

// snippet:start flutter-errors-1
/// Runs [query] and returns its items, or null when Ditto rejects it.
/// DittoException (a rejected query, a closed instance) and DittoError (an
/// internal failure) are unrelated types, so a handler names each one.
Future<List<Map<String, dynamic>>?> tryQuery(Ditto ditto, String query) async {
  try {
    final result = await ditto.store.execute(query);
    return result.items.map((item) => item.value).toList();
  } on DittoException catch (error) {
    log('query rejected: $error', name: 'ditto');
    return null;
  } on DittoError catch (error, stackTrace) {
    log('Ditto failed', name: 'ditto', error: error, stackTrace: stackTrace);
    rethrow;
  }
}
// snippet:end flutter-errors-1

Future<Object?> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  ensureProbeBinding();

  testWidgets('DQL syntax error is a DittoException', (t) async {
    await withDitto(t, (ditto) async {
      expect(await tryQuery(ditto, 'SELECT * FROM cars'), isEmpty);
      final error = await _failureOf(() => ditto.store.execute('SELEC * FROM'));
      expect(
        error.toString(),
        'DittoException(<dql> Invalid query: `DQL parser error: Unexpected '
        'token SELEC at line 1 column 1 near "SELEC * FROM"; expected a DQL '
        "statement`. For more information on Ditto's query language see: "
        'https://ditto.com/link/dql-guide)',
      );
      expect(error, isA<DittoException>());
      expect(await tryQuery(ditto, 'SELEC * FROM'), isNull);
    });
  });

  testWidgets('mutation in a read-only transaction throws', (t) async {
    await withDitto(t, (ditto) async {
      final error = await _failureOf(
        () => ditto.store.transaction(
          isReadOnly: true,
          (tx) => tx.execute(
            'INSERT INTO cars DOCUMENTS (:car)',
            arguments: {
              'car': {'_id': 'car-1'},
            },
          ),
        ),
      );
      expect(error, isA<DittoException>());
      expect(
        error.toString(),
        'DittoException(<store> A mutating DQL query was attempted using a '
        'read-only transaction.)',
      );
      expect((await ditto.store.execute('SELECT * FROM cars')).items, isEmpty);
    });
  });

  testWidgets('registerObserver with a non-SELECT query throws', (t) async {
    await withDitto(t, (ditto) async {
      Object? error;
      try {
        ditto.store.registerObserver('DELETE FROM cars').cancel();
      } catch (e) {
        error = e;
      }
      expect(error, isA<DittoException>());
      expect(
        error.toString(),
        'DittoException(<dql> Unsupported feature: non-SELECT statement in '
        'store observer)',
      );
    });
  });

  // 5.0.x and 5.1.0 open with a passphrase (the dartdoc calls it internal
  // and undocumented; whether the store is encrypted is not checked here).
  // 5.2.0 rejects it.
  testWidgets('experimental passphrase, per line', (t) async {
    await withProbeDirectory((path) async {
      final config = DittoConfig(
        persistenceDirectory: path,
        experimental: const DittoConfigExperimental(passphrase: 'secret'),
      );
      if (pinnedLine == '5.2') {
        final error = await _failureOf(() => Ditto.open(config));
        expect(error, isA<DittoException>());
        expect(
          error.toString(),
          'DittoException(Invalid DittoConfig: Passphrase-based encryption is '
          'no longer supported. Remove the `experimental.passphrase` entry '
          'from the Ditto config and use an encryption key instead.)',
        );
      } else {
        final ditto = await Ditto.open(config);
        await ditto.close();
      }
    });
  });
}
