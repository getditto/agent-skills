/// Web has no filesystem: `null` lets Ditto use its in-memory store.
Future<String?> createPersistenceDirectory() async => null;
