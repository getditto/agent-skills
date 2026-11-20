/// Web has no filesystem: `null` lets Ditto use its in-memory store.
Future<String?> createPersistenceDirectory() async => null;

/// Nothing to delete on web.
Future<void> deletePersistenceDirectory(String? path) async {}
