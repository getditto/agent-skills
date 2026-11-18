// DittoConfig.systemParameters: 5.2.0+.
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

Future<Object?> _openFailure(
  String path,
  Map<String, Object> parameters,
) async {
  try {
    final ditto = await Ditto.open(
      DittoConfig(persistenceDirectory: path, systemParameters: parameters),
    );
    await ditto.close();
  } catch (error) {
    return error;
  }
  return null;
}

void main() {
  ensureProbeBinding();

  testWidgets('unencodable system parameter throws ArgumentError', (t) async {
    await withProbeDirectory((path) async {
      final error = await _openFailure(path, {'x': double.infinity});
      expect(error, isA<ArgumentError>());
      expect(
        error.toString(),
        'Invalid argument(s): System parameter doubles must be finite',
      );
    });
  });

  testWidgets('unknown system parameter throws DittoException', (t) async {
    await withProbeDirectory((path) async {
      final error = await _openFailure(path, {'not_a_real_parameter': 1});
      expect(error, isA<DittoException>());
      expect(
        error.toString(),
        "DittoException(Invalid DittoConfig: unknown parameter "
        "'not_a_real_parameter')",
      );
    });
  });
}
