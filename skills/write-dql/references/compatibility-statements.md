# Compatibility statements — Ditto

## Contents

- [4.1 Top-level statements](#41-top-level-statements)
- [4.2 `INSERT ... ON ID CONFLICT` actions](#42-insert--on-id-conflict-actions)
- [4.7 Indexing and planner directives](#47-indexing-and-planner-directives)

Topic index: [versions.md](versions.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

### 4.1 Top-level statements

| Statement                                | 4.14.x | 5.0.x | 5.1.x | Notes                                                                                             |
| ---------------------------------------- | :----: | :---: | :---: | ------------------------------------------------------------------------------------------------- |
| `SELECT` / `WITH`                        |   ✓    |   ✓   |   ✓   | Identical surface.                                                                                |
| `INSERT INTO COLLECTION`                 |   ✓    |   ✓   |   ✓   | `INITIAL DOCUMENTS` and standard `DOCUMENTS` both supported.                                      |
| `INSERT INTO <coll> SELECT …`            |   ✗    |   ✗   |   ✓   | Insert-from-select. Parse error (`expected DOCUMENTS or VALUES`) on 4.14.x / 5.0.x. See [`statements.md`](statements.md) §1.9. |
| `UPDATE COLLECTION ... SET/UNSET/APPLY`  |   ✓    |   ✓   |   ✓   | See [`statements.md`](statements.md) §2 and [`types-mutators.md`](types-mutators.md).             |
| `EVICT FROM`                             |   ✓    |   ✓   |   ✓   | Local-only purge; no tombstone.                                                                   |
| `DELETE FROM`                            |   ✓    |   ✓   |   ✓   | Logical delete; produces tombstone.                                                               |
| `TOMBSTONE FROM`                         |   ✗    |   ✗   |   ✗   | **Rejected on every tested SDK version** with `Tombstone is not supported` — it is a deprecated Big-Peer-only statement and the Small Peer refuses it after parsing. Use `DELETE`. |
| `ALTER SYSTEM SET/RESET <param>`         |   ✓    |   ✓   |   ✓   | Used to flip `dql_strict_mode` and other engine flags.                                            |
| `SHOW <param>` / `SHOW ALL`              |   ✓    |   ✓   |   ✓   | `SHOW INDEXES` is **not** present on any SDK version.                                                    |
| `SHOW ALL LIKE/ILIKE … [ESCAPE …]`       |   ✗    |   ✗   |   ✓   | The filter clause is 5.1-only; parse error on 4.14.x / 5.0.x. Case-sensitive. See [`statements.md`](statements.md) §8. |
| `SYNC CONTEXT ... SELECT/SHOW`           |   ✓    |   ✓   |   ✓   | Remote query wrapper. Big Peer only — not executable from a Small Peer.                           |
| `CREATE INDEX [IF NOT EXISTS]`           |   ✓    |   ✓   |   ✓   | Single-column and nested-path. Composite is 5.1-only — see §4.7.                                  |
| `DROP INDEX [IF EXISTS]`                 |   ✓    |   ✓   |   ✓   |                                                                                                   |
| `EXPLAIN SELECT`                         |   ✓    |   ✓   |   ✓   | Plan inspection without execution.                                                                |
| `EXPLAIN` on DML (`INSERT`/`UPDATE`/`DELETE`/`EVICT`) | ✗ | ✗ |   ✓   | 4.14.x / 5.0.x raise `Explain DML is not supported`. See [`statements.md`](statements.md) §6.     |
| `PROFILE <stmt>`                         |   ✗    |   ✓   |   ✓   | **SDK 5.0+**. Leading keyword form; sets `#profile` on the request.                               |
| `ADVISE <stmt>` / `ADVISE AND PROVISION` |   ✗    |   ✗   |   ✓   | Parse error on 4.14.x / 5.0.x. See [`indexing.md`](indexing.md) §9.                               |
| `INNER JOIN` / `LEFT [OUTER] JOIN`       |   ✗    |   ✗   |   ✓   | Right-side match key must be `_id` or indexed. See [`select.md`](select.md) §14.                  |
| `RIGHT [OUTER] JOIN`                     |   ✗    |   ✗   |   ✓   | Works and is fully functional on 5.1.x. `FULL OUTER` and `CROSS` are rejected on every SDK version.       |
| `RETURNING` on `INSERT` / `UPDATE`       |   ✗    |   ✗   |   ✓   | See [`statements.md`](statements.md) §§1.8, 2.5.                                                  |
| `RETURNING` on `DELETE` / `EVICT`        |   ✗    |   ✗   |   ✓   | See [`statements.md`](statements.md) §§4.4, 5.4.                                                  |

### 4.2 `INSERT ... ON ID CONFLICT` actions

| Action                          | 4.14.x | 5.0.x | 5.1.x | Notes                                                            |
| ------------------------------- | :----: | :---: | :---: | ---------------------------------------------------------------- |
| `FAIL` (default)                |   ✓    |   ✓   |   ✓   | Default when omitted.                                            |
| `DO NOTHING`                    |   ✓    |   ✓   |   ✓   |                                                                  |
| `DO UPDATE`                     |   ✓    |   ✓   |   ✓   | Canonical name.                                                  |
| `DO UPDATE_LOCAL_DIFF`          |   ✓    |   ✓   |   ✓   | **SDK 4.12+**. AST variant `DoUpdateDifferent`.                  |
| `DO MERGE`                      |   ✓    |   ✓   |   ✓   | Alias for `DO UPDATE` on every tested SDK version; not a distinct mode. |

### 4.7 Indexing and planner directives

| Feature                                            | 4.14.x | 5.0.x | 5.1.x | Notes                                                                       |
| -------------------------------------------------- | :----: | :---: | :---: | ----------------------------------------------------------------------------- |
| `CREATE INDEX [IF NOT EXISTS]`, single-column      |   ✓    |   ✓   |   ✓   | Both `… name ON coll (keys)` and `… coll.name (keys)` spellings work.        |
| `CREATE INDEX` on a nested path (`ratings.imdb`)   |   ✓    |   ✓   |   ✓   |                                                                             |
| `CREATE INDEX` composite (multi-column)            |   ✗    |   ✗   |   ✓   | 4.14.x / 5.0.x: `not implemented yet : composite indexes` (runtime, not parse). |
| `INCLUDE MISSING` / `EXCLUDE MISSING` index keys   |   ✗    |   ✗   |   ✗   | **Rejected on every tested SDK version** (`not implemented yet`). See [`indexing.md`](indexing.md) §1.2. |
| `DROP INDEX [IF EXISTS]`                           |   ✓    |   ✓   |   ✓   | Both spellings.                                                             |
| `#index`, `#max_scans`, `#max_inlist`, `#intersects`, `#prefer_order`, `#disable_index_scan` | ✓ | ✓ | ✓ | The six directives present in the 4.14 planner.                             |
| `#max_serial_ranges`, `#disable_covering`, `#disable_special`, `#disable_intersect_eo`, `#auto_use_ids`, `#reprepare` | ✗ | ✓ | ✓ | **SDK 5.0+.** Absent from the 4.14 planner registry — see the warning below. |
| `#profile` planner directive                       |   ✗    |   ✓   |   ✓   | 4.14 defines the key but emits no profile row; 5.0+ emits `~request_profile`. |
| `USE IDS 'a'` / `USE IDS 'a', 'b'` on `SELECT`     |   ✓    |   ✓   |   ✓   | Comma-separated multi-id **works on every SDK version**.                           |
| `USE IDS ('a', 'b')` (parenthesised tuple)         |   ✗    |   ✗   |   ✗   | Rejected everywhere — it parses as one tuple expression. Use the comma form. |
| `USE IDS LIST ['a', 'b']`                          |   ✗    |   ✓   |   ✓   | **SDK 5.0+**.                                                               |
| Automatic `_id` equality rewrite                   |   ✗    |   ✓   |   ✓   | 5.0+: `WHERE _id = '…'` rewrites to `idScan`. 5.1.x also rewrites `WHERE _id IN (…)`. |
| `USE IDS` on `UPDATE`                              |   ✗    |   ✗   |   ✓   | 5.1.x only, and **only before `SET`** (`UPDATE coll USE IDS 'x' SET …`). Applies correctly. |
| `USE IDS` on `DELETE` / `EVICT`                    |   ✗    |   ✗   |   ✗   | Parse error on 4.14.x / 5.0.x; not supported on mutations. Use `WHERE _id IN (…)`. |
| `USE IDS` on `TOMBSTONE`                           |   ✗    |   ✗   |   ✗   | `TOMBSTONE` itself is unavailable on every SDK version.                            |
| `ADVISE` / `ADVISE AND PROVISION`                  |   ✗    |   ✗   |   ✓   | See [`indexing.md`](indexing.md) §9.                                        |

> **Planner directives fail silently.** An unrecognised directive — including a misspelling, an unknown collection name, or a wrong-typed value — is **accepted without error and ignored** on every version. "It didn't error" therefore proves nothing about support. The only reliable check is to diff `EXPLAIN` plans against the same query without the directive: a honoured directive changes the plan shape, an ignored one leaves it byte-identical.
