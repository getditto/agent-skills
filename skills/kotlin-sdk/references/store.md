# Store: executing DQL, transactions, indexing and eviction — Ditto Kotlin SDK

## Contents

- [CAP-08 Querying the store: executing DQL](#cap-08-querying-the-store-executing-dql)
- [CAP-09 Transactions](#cap-09-transactions)
- [CAP-10 Indexing](#cap-10-indexing)
- [CAP-17 Device storage management and eviction](#cap-17-device-storage-management-and-eviction)

DQL *grammar and semantics* (JOINs, CRDT merge behavior, which clauses a
subscription allows, etc.) belong to the `write-dql` skill if installed,
otherwise <https://docs.ditto.live/dql/dql>. This file covers the Kotlin call
shape, argument binding, result handling and resource lifetimes.

v5 API shown throughout (`com.ditto:ditto-kotlin`, imports under
`com.ditto.kotlin.*`). Short `(4.14.x: …)` notes flag where the v4 SDK
(`live.ditto:ditto`, Android-only) differs; full v4 tables live in
[versions.md](versions.md).

## CAP-08 Querying the store: executing DQL

### The three `execute` result shapes (v5)

All store reads and writes go through `ditto.store.execute` / `executeRaw` — six
`execute` overloads and three `executeRaw` (Map vs `Dictionary` arguments, plus
reified `@Serializable` variants — **[source-verified]** `DittoStore.kt`). All
are `suspend`. The overload you pick determines the result lifecycle:

```kotlin
// 1. No handler — returns Unit. Use for writes (INSERT/UPDATE/DELETE/EVICT,
//    CREATE INDEX, ALTER SYSTEM). Still suspends until the query finishes.
ditto.store.execute(
    query = "UPDATE cars SET color = :color WHERE _id = :id",
    arguments = mapOf("color" to "green", "id" to id),
)

// 2. Handler — RECOMMENDED for reads. The DittoQueryResult is auto-closed when
//    the lambda returns; the lambda's return value is yours to keep.
val color: String? = ditto.store.execute(
    query = "SELECT * FROM cars WHERE _id = :id",
    arguments = mapOf("id" to id),
) { result ->
    result.items.firstOrNull()?.value?.get("color")?.stringOrNull
}

// 3. executeRaw — manual lifecycle. YOU must close the result (use .use { }).
ditto.store.executeRaw("SELECT * FROM cars").use { result ->
    result.items.map { it.jsonString() }
}
```

(4.14.x: `store.execute(query, args)` returns `DittoQueryResult` directly and
must be closed manually; there is no handler overload. `executeBlocking()` was
removed in v5 — use `runBlocking { store.execute(...) }` if you must.)

> **The handler/observer result lifetime is the #1 crash source.**
> `DittoQueryResult` and its `DittoQueryResultItem`s are managed native
> resources. As soon as the handler lambda returns, they are closed. Returning
> `result.items` (or anything referencing an item) out of the lambda, or
> storing items in a field/`StateFlow`, throws
> `IllegalStateException: Query result item has already been closed.` on the
> next access. Extract plain Kotlin data — strings, numbers, decoded data
> classes — *inside* the lambda.

(sdk/latest/crud/read, sdk/latest/migration-guides/kotlin-v4)

### Binding arguments

Use `:name` placeholders in the DQL string and pass values via `arguments`,
keyed by the placeholder name without the `:`. **Never** string-interpolate
values into a query — it is both an injection risk and a source of malformed
DQL at runtime:

```kotlin
// ❌ Wrong
ditto.store.execute("SELECT * FROM cars WHERE color = '$color'")

// ✅ Correct — arguments accept Map<String, Any?> (recommended),
//    DittoCborSerializable.Dictionary, or a @Serializable type (v5).
ditto.store.execute(
    query = "SELECT * FROM cars WHERE color = :color",
    arguments = mapOf("color" to "blue"),
) { result -> /* ... */ }
```

v5 adds inline reified overloads that serialize `@Serializable` argument types
automatically (no `.toDittoCbor()` call needed):

```kotlin
@Serializable
data class CarArgs(val color: String)

ditto.store.execute("SELECT * FROM cars WHERE color = :color", CarArgs("red")) { result ->
    // ...
}
```

Nested maps bind document-valued arguments (e.g. `INSERT INTO cars DOCUMENTS
(:newCar)` with `mapOf("newCar" to mapOf("color" to "blue"))`).

(sdk/latest/crud/read, sdk/latest/crud/create, sdk/latest/migration-guides/kotlin-v4)

### Reading values out of a result

`result.items` is a lazy-loaded list of `DittoQueryResultItem` — each item's
value materializes into memory on first access (`item.isMaterialized`,
`item.materialize()`, `item.dematerialize()` to release it).

**`item.value` is a `DittoCborSerializable.Dictionary`, not a
`Map<String, Any?>`.** Kotlin casts like `item.value["color"] as String` throw
`ClassCastException` at runtime. Index with a String key — which returns a
non-null `DittoCborSerializable` — then chain a typed accessor:

| Accessor | Returns |
| - | - |
| `.string` / `.stringOrNull` | `String` / `String?` |
| `.intOrNull`, `.longOrNull`, `.doubleOrNull` | numbers (`*OrNull` for possibly-absent/wrong-type fields) |
| `.booleanOrNull` | `Boolean?` |
| `.listOrNull` | list value |
| `.dictionaryOrNull` | nested dictionary |
| `.attachmentTokenOrNull` | attachment token |
| `.isNull` | whether the stored value is null |

Note the asymmetry: the subscript never returns null for a missing key; it is
the `*OrNull` accessor that yields `null` for absent or wrong-typed fields.

```kotlin
val itemValueColor: String? = ditto.store.execute("SELECT * FROM cars LIMIT 1") { result ->
    result.items.firstOrNull()?.let { it.value["color"].stringOrNull }
}
```

For anything with a real schema, prefer `item.jsonString()` plus
kotlinx.serialization — it is type-safe and sidesteps the CBOR type mapping in
one step:

```kotlin
@Serializable
data class Car(val _id: String, val color: String)

private val carJson = Json { ignoreUnknownKeys = true }

val cars: List<Car> = ditto.store.execute("SELECT * FROM cars") { result ->
    result.items.map { carJson.decodeFromString<Car>(it.jsonString()) }
}
```

Raw encodings are also available per item: `item.cborData(): ByteArray` and
`item.jsonString(): String` (neither result is cached — each call re-encodes).

For write statements executed with the handler overload, read the affected IDs
from `result.mutatedDocumentIds()` inside the lambda:

```kotlin
ditto.store.execute(
    query = "INSERT INTO cars DOCUMENTS (:newCar)",
    arguments = mapOf("newCar" to mapOf("_id" to "123", "color" to "blue")),
) { result ->
    // mutatedDocumentIds() returns Set<DittoCborSerializable> — unwrap with an accessor
    println(result.mutatedDocumentIds().first().stringOrNull) // "123"
}
```

(sdk/latest/crud/read, sdk/latest/crud/create, sdk/latest/crud/delete,
sdk/latest/migration-guides/kotlin-v4, sdk/latest/migration-guides/kotlin-dql)

## CAP-09 Transactions

Available since 4.11. `store.transaction` groups multiple DQL statements into
one atomic, serializable-isolation commit — all statements succeed or none do,
and consecutive statements see the same snapshot:

```kotlin
val result = ditto.store.transaction(hint = "transaction example") { transaction ->
    transaction.execute("/* query 1 */") { queryResult1 -> }
    transaction.execute("/* query 2 */") { queryResult2 -> }

    // Complete by returning a DittoTransaction.Result<T>
    DittoTransaction.Result.Commit() // or DittoTransaction.Result.Rollback
}
```

The generic form returns a value out of the committed transaction — extract
plain Kotlin data inside the block (the same closed-result rules as CAP-08
apply to `transaction.execute` handlers):

```kotlin
val result = ditto.store.transaction(hint = "count cars") { transaction ->
    val rowsJson: List<String> = transaction.execute("SELECT * FROM cars") { queryResult ->
        queryResult.items.map { it.jsonString() }
    }
    DittoTransaction.Result.Commit(rowsJson)
}

when (result) {
    is DittoTransaction.Result.Commit -> result.value.forEach(::println)
    DittoTransaction.Result.Rollback -> { /* nothing committed */ }
}
```

Semantics to know:

- **Throwing rolls back.** An uncaught error anywhere in the block (or while
  committing) implicitly rolls the transaction back and rethrows to the caller.
  An error from `transaction.execute` that you catch inside the block does
  *not* abort the transaction — it keeps running.
- **Read-only transactions.** `isReadOnly = true` allows many concurrent
  read-only transactions (including alongside a read-write one); executing a
  mutating statement (`UPDATE`, `DELETE`, …) inside one throws:

  ```kotlin
  ditto.store.transaction(hint = "Read-only transaction", isReadOnly = true) { transaction ->
      // SELECTs only
      DittoTransaction.Result.Commit()
  }
  ```

- **One read-write transaction at a time.** A second read-write transaction
  waits for the first to finish — keep blocks short. Never start a read-write
  transaction from inside another one (deadlock: the inner waits on the outer,
  the outer on the inner). Always set `hint`; Ditto logs warnings tagged with
  it if a transaction runs longer than ~10 s.
- **Only use the `transaction` object inside the block.** Calling
  `ditto.store.execute(...)` (a mutating statement in particular) inside a
  transaction block runs in its own implicit transaction and can deadlock —
  Ditto does not prevent this; you must avoid it:

  ```kotlin
  ditto.store.transaction { transaction ->
      transaction.execute("/* query 1 */") // ✅ OK
      ditto.store.execute("/* query 2 */") // ⚠️ Avoid this
      DittoTransaction.Result.Commit()
  }
  ```

- `transaction.info` (`DittoTransactionInfo`) exposes `id`, `hint` and
  `isReadOnly`. `ditto.close()` waits for pending transactions to complete.

(4.14.x: `store.transaction { txn -> DittoTransactionCompletionAction.Commit }` —
the v4 enum is `Commit` / `Rollback`; there is no `Abort` (**[source-verified]**
v4 `DittoTransactionCompletionAction.kt` — the migration guide's "Abort" is a
Swift-ism). v4 also had a generic value-returning `transaction` overload;
`store.write(block)` write transactions were removed in v5.)

Replication caveat: peers whose subscriptions cover only part of a
transaction's changes receive only that part — see the `sync-subscriptions`
skill.

(sdk/latest/crud/transactions, sdk/latest/migration-guides/kotlin-v4)

## CAP-10 Indexing

Indexes are DQL statements run through the same `execute` call — the no-handler
overload (returns `Unit`) is the right one:

```kotlin
// Single-field index
ditto.store.execute("CREATE INDEX idx_cars_color ON cars (color)")

// Index on a nested field path
ditto.store.execute("CREATE INDEX idx_cars_location ON cars (_id.locationId)")

// Composite (multi-column) index — 5.1.x only
ditto.store.execute("CREATE INDEX idx_cars_color_year ON cars (color, year)")

// List and drop
val indexRows = ditto.store.execute("SELECT * FROM system:indexes") { result ->
    result.items.map { it.jsonString() }
}
ditto.store.execute("DROP INDEX idx_cars_color ON cars")
```

(Composite/multi-column `CREATE INDEX` requires 5.1.x; on 4.14.x and 5.0.x only
single-field indexes are supported.)

Create indexes on fields used in observer and query `WHERE` clauses, and create
them **before** registering the observers that rely on them — DQL observers
supporting aggregates and projections otherwise fall back to full scans.

For query-plan inspection, `EXPLAIN <statement>` and `EXPLAIN <statement>
#profile` run through `execute` like any other statement; read the plan rows
from the handler. From 5.1.x, `ADVISE <statement>` names the index a statement
is missing (and `ADVISE AND PROVISION` creates it) — both are rejected by the
parser on 4.14.x/5.0.x, so gate them on the SDK version. Which queries an index
actually helps, composite-index column order, and EXPLAIN/ADVISE output shapes
belong to the `write-dql` skill or <https://docs.ditto.live/dql/indexing>,
<https://docs.ditto.live/dql/explain>, <https://docs.ditto.live/dql/advise>.

(sdk/latest/migration-guides/kotlin-dql, dql/indexing, dql/explain, dql/advise)

## CAP-17 Device storage management and eviction

`EVICT` removes documents from **this peer's** local store only — unlike
`DELETE` (a soft delete that propagates tombstones through the mesh), eviction
deletes nothing for other peers; it just frees local disk:

```kotlin
ditto.store.execute(
    query = "EVICT FROM cars WHERE _id = :id",
    arguments = mapOf("id" to id),
)

// Evict everything matching a condition, e.g. past a TTL:
ditto.store.execute(
    query = "EVICT FROM orders WHERE createdAt <= :ttl",
    arguments = mapOf("ttl" to ttl),
)
```

`EVICT` goes through the same `store.execute` call as CAP-08 — the no-handler
overload. (4.14.x: the legacy `store.collection("cars").findById(id).evict()`
API maps to `EVICT FROM cars WHERE _id = :id`.)

Rules of engagement:

- **Cancel affected subscriptions first.** If a live subscription still matches
  the evicted documents, sync pulls them straight back — an evict/resync loop
  that burns memory and bandwidth. Cancel or narrow the subscription, evict,
  then re-subscribe with criteria that do not overlap the evicted set. The
  store-level semantics (what eviction means for the mesh, subscription
  interaction) belong to the `sync-subscriptions` and `write-dql` skills or
  <https://docs.ditto.live/dql/evict>.
- **Evict on a schedule, no more than once per day.** Eviction triggers a full
  resync with every connected peer; run it during quiet periods.
- The docs' Kotlin coverage here is thin — the device-storage-management page
  shows EVICT via `store.execute` in JS/Java snippets only; the Kotlin samples
  above are the same statement through the v5 Kotlin `execute` overloads.
- The companion TTL pattern (Big Peer flags `evictionFlag` via the HTTP API;
  Small Peers evict flagged docs and subscribe to unflagged ones) is documented
  at <https://docs.ditto.live/sdk/latest/sync/device-storage-management>.
- There is no Kotlin-specific storage-limit configuration on the SDK; how much
  disk the store is using is `ditto.diskUsage` — see
  [observability.md](observability.md) (CAP-15).

(sdk/latest/sync/device-storage-management, sdk/latest/crud/delete,
sdk/latest/migration-guides/kotlin-dql, dql/evict)
