import 'dart:io';

/// A fresh persistence directory, so every run starts from an empty store.
Future<String?> createPersistenceDirectory() async =>
    (await Directory.systemTemp.createTemp('ditto_minimal_')).path;

/// Deletes a directory made by [createPersistenceDirectory], retrying for a
/// few seconds: on Windows, files the closed instance held can stay locked
/// briefly.
Future<void> deletePersistenceDirectory(String? path) async {
  if (path == null) return;
  final directory = Directory(path);
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
