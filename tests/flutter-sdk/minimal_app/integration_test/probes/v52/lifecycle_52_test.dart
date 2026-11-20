// DittoEncryptionException and DittoEncryptionErrorReason: 5.2.0+.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

void main() {
  ensureProbeBinding();

  testWidgets('DittoEncryptionException type exists', (t) async {
    await withDitto(t, (ditto) async {
      bool isEncryptionFailure(Object error) =>
          error is DittoEncryptionException;

      expect(isEncryptionFailure(DittoClosedException()), isFalse);
      expect(DittoEncryptionErrorReason.values.map((r) => r.name), [
        'keyRequired',
        'keyUnexpected',
        'keyInvalid',
        'unsupportedScheme',
        'metadataCorrupt',
      ]);
    });
  });
}
