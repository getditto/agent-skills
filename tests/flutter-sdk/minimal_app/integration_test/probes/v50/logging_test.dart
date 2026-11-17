import 'dart:io';

import 'package:ditto_live/ditto_live.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exportLogs writes file and existing path throws DittoError', (
    t,
  ) async {
    await withDitto(t, (ditto) async {
      DittoLogger.isEnabled = true; // the harness turns logging off
      final directory = await Directory.systemTemp.createTemp('ditto_logs_');
      try {
        final path = '${directory.path}/ditto.log';
        final written = await DittoLogger.exportLogs(path);
        expect(written, greaterThan(0));
        expect(File(path).existsSync(), isTrue);
        expect(File(path).lengthSync(), greaterThan(0));

        await expectLater(
          DittoLogger.exportLogs(path),
          throwsA(isA<DittoError>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
