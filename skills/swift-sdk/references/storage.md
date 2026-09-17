# On-disk store — Ditto Swift SDK

How a Ditto store on disk behaves across the three supported version lines: where it
lives, what an upgrade does to it, and what a rollback does. The API-surface differences
are in [versions.md](versions.md); this is the part of CAP-19 that is about bytes on
disk rather than symbols.

All of the following was **executed** by `scripts/persistence-matrix.sh` in the
`getditto/agent-skills` repository, on macOS 27.0 / arm64. The reader process exits
non-zero unless the document, its field and the index all survive, so a leg that lost
data fails the run rather than printing a zero count.

## Default persistence directory

| Opened with | Default directory |
|---|---|
| 4.14.x `Ditto(identity:)` (deprecated) | `<Documents>/ditto` |
| 4.14.x `Ditto.open(config:)` | `<Application Support>/ditto-{databaseID}` |
| 5.0.x / 5.1.x `Ditto.open(config:)` | `<Application Support>/ditto-{databaseID}` |

"The default directory changed from `ditto` to `ditto-{databaseID}` in v5" is about the
**identity initializer**, not about `Ditto.open`. An app already using
`Ditto.open(config:)` on 4.14.x is already on the v5 default path — measured, both
versions reported the same absolute directory.

**An upgrading app does not silently get an empty database.** When
`persistenceDirectory` is `nil`, `DittoConfig.encode(to:)` also sends the v4 default path
as `legacy_persistence_directory`
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoConfig.swift:172-191`, byte-identical at
`sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoConfig.swift:171-179`), and Core checks
both, preferring the non-legacy path. Executed: a database written by 4.14.6's
`Ditto(identity:)` into `<Documents>/ditto` was found and read by 5.1.0 with no
`persistenceDirectory` set, and `absolutePersistenceDirectory` reported that legacy path.

Setting `persistenceDirectory` explicitly removes the ambiguity, and is what
[connect.md](connect.md) recommends.

## Upgrade and rollback

Each pair was run **directly** — writer, then reader, with no intermediate version
opening the store — and again as a chain (`4.14.6 → 5.0.3 → 5.1.0`, and
`5.1.0 → 5.0.3 → 4.14.6`). The direct runs matter because the intermediate 5.0.x open is
exactly the step the published contract says reverts the 5.1 index format.

| Written by | Read by | Result |
|---|---|---|
| 4.14.6 | 5.0.3 | document and index present |
| 4.14.6 | 5.1.0 | document and index present |
| 5.1.0 | 5.0.3 | document and index present |
| 5.1.0 | 4.14.6 | document and index present |

The reader process exits non-zero unless the document, its field and the index all
survive, so a leg that lost data fails the run rather than printing `found=0`.

This matches the published contract in
`snippets/common-release-notes/5-1-capabilities/upgrade-considerations.mdx`: 5.1 changes
the on-disk index format, and a downgrade must route through **5.0.2+ or 4.14.6+**, which
recognise the new format and revert it. During the downgrade a composite index is
replaced by one single-field index per key.

**Not verified here:** downgrading below 5.0.2 / 4.14.6, and the composite-index split —
the fixture creates a single-field index only. Composite indexes are a DQL feature; see
the `dql` skill or <https://docs.ditto.live/dql/indexing#migration>.

---
