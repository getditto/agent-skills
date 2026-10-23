# On-disk store — Ditto Swift SDK

How a Ditto store on disk behaves across the three supported version lines: where it
lives, what an upgrade does to it, and what a rollback does. The API-surface differences
are in [versions.md](versions.md); this is the part of CAP-19 that is about bytes on
disk rather than symbols.

## Default persistence directory

| Opened with | Default directory |
|---|---|
| 4.14.x `Ditto(identity:)` (deprecated) | `<Documents>/ditto` |
| 4.14.x `Ditto.open(config:)` | `<Application Support>/ditto-{databaseID}` |
| 5.0.x / 5.1.x `Ditto.open(config:)` | `<Application Support>/ditto-{databaseID}` |

"The default directory changed from `ditto` to `ditto-{databaseID}` in v5" is about the
**identity initializer**, not about `Ditto.open`. An app already using
`Ditto.open(config:)` on 4.14.x is already on the v5 default path.

**An upgrading app does not silently get an empty database.** When
`persistenceDirectory` is `nil`, v5 checks both the new default and the v4 default
(`<Documents>/ditto`), preferring the new one. A database written by 4.14.x's
`Ditto(identity:)` is found and read by 5.1.x with no `persistenceDirectory` set, and
`absolutePersistenceDirectory` reports that legacy path.

Setting `persistenceDirectory` explicitly removes the ambiguity, and is what
[connect.md](connect.md) recommends.

## Upgrade and rollback

Each pair below was written by one version and read directly by the other, with no
intermediate version opening the store, and also as a chain
(`4.14.6 → 5.0.3 → 5.1.0`, and `5.1.0 → 5.0.3 → 4.14.6`):

| Written by | Read by | Result |
|---|---|---|
| 4.14.6 | 5.0.3 | document and index present |
| 4.14.6 | 5.1.0 | document and index present |
| 5.1.0 | 5.0.3 | document and index present |
| 5.1.0 | 4.14.6 | document and index present |

This matches the published
[5.1 upgrade considerations](https://docs.ditto.live/sdk/latest/release-notes/swift):
5.1 changes the on-disk index format, and a downgrade must route through **5.0.2+ or
4.14.6+**, which recognise the new format and revert it. During the downgrade a composite
index is replaced by one single-field index per key.

Do not downgrade below 5.0.2 / 4.14.6 from a store 5.1.x has opened. Composite indexes are
a DQL feature; see the `write-dql` skill or <https://docs.ditto.live/dql/indexing#migration>.
