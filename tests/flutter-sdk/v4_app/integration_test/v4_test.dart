import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:v4_app/v4_app.dart';

const license = String.fromEnvironment('DITTO_LICENSE');
const expectedVersion = String.fromEnvironment('DITTO_VERSION');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // integration_test defaults to no timeout; a hang must fail the run.
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));

  testWidgets('v4 open, write and read back', (tester) async {
    expect(license, isNotEmpty, reason: 'pass --dart-define=DITTO_LICENSE');
    expect(
      expectedVersion,
      isNotEmpty,
      reason: 'pass --dart-define=DITTO_VERSION',
    );

    // An absolute, fresh directory per run; 4.14 resolves a relative one
    // against the app's Documents directory.
    final directory = await Directory.systemTemp.createTemp('ditto_v4_');
    final List<String> lines;
    try {
      lines = await runV4App(
        license: license,
        persistenceDirectory: directory.path,
      );
    } finally {
      await _delete(directory);
    }
    for (final line in lines) {
      debugPrint('transcript: $line');
    }
    binding.reportData = {'transcript': lines};

    expect(lines, [
      'v4 read-back make: Toyota',
      'v4 SDK version: $expectedVersion',
      'v4 closed: true',
    ]);
  });
}

/// Deletes [directory], retrying for a few seconds while the closed
/// instance's files are released.
Future<void> _delete(Directory directory) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 10) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
