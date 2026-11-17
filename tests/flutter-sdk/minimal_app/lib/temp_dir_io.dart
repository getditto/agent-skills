import 'dart:io';

/// A fresh persistence directory, so every run starts from an empty store.
Future<String?> createPersistenceDirectory() async =>
    (await Directory.systemTemp.createTemp('ditto_')).path;
