import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Driver for `flutter drive -d chrome`; prints the transcript the test reports.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final transcript = data?['transcript'];
    if (transcript is List<Object?>) {
      for (final line in transcript) {
        stdout.writeln('transcript: $line');
      }
    }
  },
);
