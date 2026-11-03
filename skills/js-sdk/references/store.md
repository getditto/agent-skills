# Store operations

## CAP-08 Querying the store: executing DQL

[Task operations](../assets/tasks.ts) provide tested parameterized insert/upsert,
update, delete, and decoding. `await store.execute(query, arguments)` returns a
`QueryResult`; read `result.items.map(item => item.value)`. Bind values as `:name`;
allowlist identifiers because collection names are not value parameters.
An interface is not assignable to every SDK argument map: pass `{ task: { ...task } }`
so TypeScript sees the document's fields. Check untrusted synchronized values at runtime.
Choose string UUID IDs explicitly; a generated DQL ID need not match your string decoder.
Large integers can be `bigint`; `JSON.stringify` is not a universal Ditto serializer.

## CAP-09 Transactions

`await store.transaction(async tx => { ... })` uses `tx.execute` for each statement.
Return `'rollback'` to discard changes; return `'commit'` or a successful result to
commit. An uncaught error rolls back. Catching an error inside the callback allows
subsequent work and a commit, so do not swallow a failure you mean to roll back.

## CAP-10 Indexing

Issue `CREATE INDEX IF NOT EXISTS tasks_title ON tasks (title)` through execute.
Create indexes once in initialization/schema setup, not inside every render.
The fixture checks the indexed query's result. Composite indexes, JOIN, RETURNING,
and ADVISE require the 5.1+ DQL feature set; do not emit them for older targets.

## CAP-17 Device storage management and eviction

`EVICT FROM tasks WHERE _id = :id` removes local data without synchronizing a delete.
Cancel or narrow the relevant subscription first or peers can send it back. `DELETE`
is a synchronized mutation. A stopped observer is neither eviction nor unsubscribe.
Browser eviction cannot create disk persistence. Never manipulate an open SDK directory.

For grammar use `write-dql`, or <https://docs.ditto.live/dql/dql>.
For document/CRDT semantics use `data-modeling`, or
<https://docs.ditto.live/key-concepts/document-model>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
