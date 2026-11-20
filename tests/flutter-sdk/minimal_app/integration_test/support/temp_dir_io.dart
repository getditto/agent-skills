import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// A fresh persistence directory, so every run starts from an empty store.
Future<String?> createPersistenceDirectory() async =>
    (await Directory.systemTemp.createTemp('ditto_minimal_')).path;

/// Deletes a directory made by [createPersistenceDirectory], retrying for a
/// few seconds: on Windows, files the closed instance held can stay locked
/// briefly. On Windows a directory still locked after the retries is left
/// behind and reported on a `cleanup:` line instead of failing the test
/// (README, Windows desktop findings).
Future<void> deletePersistenceDirectory(String? path) async {
  if (path == null) return;
  final directory = Directory(path);
  for (var attempt = 1; ; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      if (attempt == 10) {
        if (!Platform.isWindows) rethrow;
        debugPrint(
          'cleanup: still locked after close: ${error.message}, '
          'errno ${error.osError?.errorCode}: $path',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
