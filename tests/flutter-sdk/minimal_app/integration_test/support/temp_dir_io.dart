import 'dart:io';

/// A fresh persistence directory, so every run starts from an empty store.
Future<String?> createPersistenceDirectory() async =>
    (await Directory.systemTemp.createTemp('ditto_minimal_')).path;

/// Deletes a directory made by [createPersistenceDirectory].
Future<void> deletePersistenceDirectory(String? path) async {
  if (path != null) await Directory(path).delete(recursive: true);
}
