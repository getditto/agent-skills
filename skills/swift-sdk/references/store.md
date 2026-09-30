# Store: DQL, transactions, indexing and eviction — Ditto Swift SDK

DQL *grammar and semantics* belong to the `dql` skill, or <https://docs.ditto.live/dql/dql>.
This file is the Swift call shape and the Swift-side decoding rules.

## Contents

- CAP-08 Querying the store: executing DQL
- CAP-09 Transactions
- CAP-10 Indexing
- CAP-17 Device storage management and eviction

## CAP-08 Querying the store: executing DQL

```swift
let result = try await ditto.store.execute(
    query: "SELECT * FROM cars WHERE mileage > :minimumMileage ORDER BY mileage",
    arguments: ["minimumMileage": 100]
)
for item in result.items {
    print(item.value["make"] as? String ?? "?")
}
```

`execute` is `async throws` and returns `DittoQueryResult`. It reads **only the local
store** and does not wait for a subscription to catch up; use an observer for that.

**Always bind arguments.** `arguments:` takes `[String: Any?]` keyed by the placeholder
name without the leading `:`. Interpolating values into the query string is how a
malformed identifier becomes a `queryInvalid` at runtime, and is never necessary.

**On v5 only**, there is a `Codable` overload on `registerObserver` and
`registerSubscription` for typed arguments; `execute` itself always takes the dictionary
form. 4.14.6 ships the dictionary overloads alone
(`sdk-release-4.14.6:cocoa/DittoSwift/Store/DittoStore.swift:155,200`), so code using the
typed form does not compile on the LTS line — see
[versions.md](versions.md#store-results-and-errors).

### Reading values out of a result item

**Subscripting yields a DOUBLE optional.** `value` is `[String: Any?]`, so
`value["name"]` has type `Any??` — the outer optional is "was the key present", the inner
one is "was the stored value null". `value["name"] as? String` casts the *outer* optional
and is `nil` for a field that is present and perfectly valid. Collapse it first:

```swift
let name = (value["name"] ?? nil) as? String        // correct
let name = value["name"] as? String                 // WRONG — nil for a present field
```

This applies to **every** field, not just `_id`. It is the same class of trap as reading a
number with `as? Double`, and it fails the same way: no error, no log, a row that renders
empty or gets dropped by a `guard let`.

`DittoQueryResultItem.value` is `[String: Any?]`. It materializes lazily on first access,
and `dematerialize()` releases the cached Swift representation. **The item stays usable**
— `value` re-materializes on the next read (**executed**).

```swift
for item in result.items {
    defer { item.dematerialize() }     // free the native copy as soon as we are done
    guard let make = item.value["make"] as? String else { continue }
    // …
}
```

`[String: Any?]` is **not** `Sendable`. Extract into a value type before crossing a
concurrency boundary — this is the single most important rule when an observer callback
feeds a `@MainActor` model. See [observers.md](observers.md).

### Numbers do not have one Swift type

**Executed on 4.14.6, 5.0.3 and 5.1.0.** A stored value comes back as the narrowest CBOR
type that holds it:

| Stored | Swift type in `item.value` |
|---|---|
| `120` | `Int` |
| `9_007_199_254_740_993` | `Int` — integers keep full 64-bit precision |
| `19_999.5` (exactly representable in binary32) | **`Float`** |
| `0.1` (not representable in binary32) | **`Double`** |

So `value["price"] as? Double` returns `nil` for some rows and a value for others, in the
same column, depending on the number stored. The failure is silent: a `guard let` just
skips the row.

```swift
// WRONG — nil whenever the stored value fits in a Float.
let price = value["price"] as? Double

// CORRECT — NSNumber bridges every numeric width.
let price = (value["price"] as? NSNumber)?.doubleValue

// BETTER — decode the item's JSON with Codable and let the decoder widen.
struct Car: Codable { let _id: String; let make: String; let price: Double }
let car = try JSONDecoder().decode(Car.self, from: item.jsonData())
```

**Booleans are the exception, and are simpler than you would guess from the above.** A
stored `true`/`false` comes back as a plain Swift `Bool` on all three lines, so
`(value["isDone"] ?? nil) as? Bool` is correct and sufficient — no `NSNumber` dance
(**executed**). Only numbers need the widening treatment.

`item.jsonData()` and `item.cborData()` give the raw encodings. `jsonData()` plus
`Codable` is the recommended path for anything with a real schema: it is type-safe, it
handles the numeric widths, and it produces a `Sendable` value in one step.

### `Date` is not a DQL type

**Executed.** Passing a `Date` does not throw. It is stored as
`{"__type": "date_epoch_timestamp", "__value": <seconds>}`, which will not compare
against anything a query expects. Store an ISO-8601 `String` or an integer epoch instead.

**Format it with `Date.ISO8601FormatStyle`, not a stored `ISO8601DateFormatter`.** The
obvious way to write that conversion is a `static let` formatter, and in Swift 6 language
mode that is a compile ERROR, not a warning: *"static property … is not concurrency-safe
because non-'Sendable' type 'ISO8601DateFormatter' may have shared mutable state"*. The
format style is a value type and needs no shared instance:

```swift
let stamp = Date.now.formatted(.iso8601)                    // String, Swift 6 clean
let date  = try Date(stamp, strategy: .iso8601)             // back again
```

An argument type the SDK genuinely cannot encode — an arbitrary `NSObject` subclass, for
instance — throws `DittoError.storeError(.queryArgumentsInvalid)` (**executed**).

## CAP-09 Transactions

Two forms. The first decides commit or rollback from the returned action:

```swift
try await ditto.store.transaction(hint: "check-in") { transaction in
    try await transaction.execute(
        query: "INSERT INTO cars DOCUMENTS (:car)",
        arguments: ["car": ["_id": "car-1", "make": "Toyota"]]
    )
    return DittoTransactionCompletionAction.commit   // or .rollback
}
```

The generic form commits automatically and returns your own value:

```swift
let count: Int = try await ditto.store.transaction(hint: "count") { transaction in
    let result = try await transaction.execute(query: "SELECT * FROM cars")
    return result.items.count
}
```

- **A scope that throws rolls back and rethrows** (**executed**).
- `isReadOnly: true` rejects a mutation with
  `DittoError.storeError(.transactionReadOnly(message:))` (**executed**).
- `hint:` is a label that shows up in diagnostics.
- `DittoTransactionScope` is `@Sendable`, so anything captured in the closure must be
  `Sendable`.
- `transaction.info` is a public `DittoTransactionInfo`, but its `id`, `hint` and
  `isReadOnly` members are **not public** — outside the SDK the value can be printed and
  compared, not destructured.

Execute statements on the `transaction`, never on `ditto.store`, inside the scope:
`ditto.store.execute` opens its own one-off transaction, so a write sent there is not part
of the enclosing one.

## CAP-10 Indexing

Indexes are DQL, run through the same `execute` call (**executed**):

```swift
try await ditto.store.execute(query: "CREATE INDEX cars_mileage ON cars (mileage)")
try await ditto.store.execute(query: "DROP INDEX cars_mileage ON cars")
```

`SELECT * FROM system:indexes` lists them.

**From 5.1.x, `ADVISE` names the index you are missing** (**executed**):

```swift
// Plans the statement without executing it; creates nothing.
let advice = try await ditto.store.execute(
    query: "ADVISE SELECT * FROM cars WHERE mileage > 100 ORDER BY make"
)

// Same analysis, then runs the recommended CREATE INDEX statements.
try await ditto.store.execute(
    query: "ADVISE AND PROVISION SELECT * FROM cars WHERE mileage > 100 ORDER BY make"
)
```

**The key name differs by form**, which is easy to miss because the entries are
identical:

| Statement | Result key |
|---|---|
| `ADVISE …` | `items[0].value["advice"]["suggestedIndexes"]` |
| `ADVISE AND PROVISION …` | `items[0].value["advice"]["createdIndexes"]` |

Both also carry `advice.statement`, the echoed query. Reading `suggestedIndexes` after
provisioning returns `nil`. **Executed** — the fixture asserts each form's key is
present and the other's is absent, so a future rename fails the harness.

**Executed**: `ADVISE` leaves `system:indexes` empty, and `ADVISE AND PROVISION` does
not. On 4.14.x and 5.0.x both forms are rejected by the parser with
`storeError(.queryInvalid("… Unexpected token ADVISE …"))` (**executed**), so gate them
on the version.

Which columns deserve an index, composite indexes (5.1.x), how the planner chooses what
to recommend, `EXPLAIN` and `#profile` belong to the `dql` skill or
<https://docs.ditto.live/dql/indexing> and <https://docs.ditto.live/dql/advise>.

An index created by one version survives being opened by another, in both directions —
see [storage.md](storage.md#upgrade-and-rollback), where each pair is run directly.

## CAP-17 Device storage management and eviction

`EVICT` removes documents from **this** peer's store without deleting them for anyone
else:

```swift
try await ditto.store.execute(
    query: "EVICT FROM cars WHERE mileage > :threshold",
    arguments: ["threshold": 100_000]
)
```

**Executed**: the evicted documents are gone from local `SELECT` results.

Cancel or narrow any subscription that still matches the documents before evicting them.
Why that matters, and what eviction means for the rest of the mesh, belong to the
`sync-subscriptions` skill or
<https://docs.ditto.live/sdk/latest/sync/device-storage-management>.

How much disk the store is using is `ditto.diskUsage` — see
[observability.md](observability.md).
