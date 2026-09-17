# Observers, diffing and back-pressure — Ditto Swift SDK

This is where most Ditto Swift apps live, and where correct-looking code leaks, stalls or
janks. Read [`SKILL.md` § Concurrency and threading model](../SKILL.md#concurrency-and-threading-model)
first; this file is the detail.

## CAP-11 Observers, diffing and back-pressure

### Registering

```swift
let observer = try ditto.store.registerObserver(
    query: "SELECT * FROM cars WHERE mileage > :minimumMileage ORDER BY mileage",
    arguments: ["minimumMileage": 100]
) { result in
    // fires once immediately with the current result, then on every change
}
```

- The query **must be a `SELECT`**. Anything else throws
  `DittoError.storeError(.queryNotSupported(message:))` (**executed**).
- Invalid DQL throws `.queryInvalid(message:)`; an argument the SDK cannot encode throws
  `.queryArgumentsInvalid` (**executed**).
- Arguments are bound, never interpolated. A `Codable` overload takes a typed struct.
- The first callback arrives with the current result set — it is not "changes only".

### Retaining the handle is about cancelling, not about staying alive

> *"You'll have to keep it to be able to cancel the observation. Otherwise it will remain
> active until the owning `Ditto` object goes out of scope."*
> — `sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStore.swift:209-211`

Dropping a `DittoStoreObserver` does **not** stop it. It keeps firing, and it keeps
everything its closure captured alive, for the whole life of the `Ditto` instance. The
observable symptom is a leak plus duplicate work, not a missing update.

```swift
observer.cancel()
observer.isCancelled   // true
```

**Executed**, against a second uncancelled observer on the same query as a positive
control: once that control had seen a write made *after* the cancellation, the cancelled
observer's delivery count was unchanged, and it had disappeared from
`ditto.store.observers`.

`ditto.store.observers` is **computed** in v5, so a cached snapshot goes stale — read it
at the point of use. See [sync.md](sync.md#dittosyncsubscriptions-is-computed-do-not-cache-it).

### Where the callback runs

| | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| `deliverOn:` honoured | yes | **no** | yes |

**Executed on all three lines.** On 5.0.3 the parameter is accepted and ignored, and the
published symptom is *"a crash when used with Swift concurrency"* (#SDKS-3856). Full
detail: [versions.md](versions.md#deliveron-is-ignored-on-50x).

**Write handlers that do not depend on `deliverOn:`.** Do the work in the handler, then
hop explicitly:

```swift
let observer = try ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
    // Off the main actor on 5.0.x, on `.main` elsewhere. Decode here either way —
    // this is the expensive part and it does not belong on the main thread.
    let cars = result.items.compactMap { item -> Car? in
        defer { item.dematerialize() }
        return Car(item.value)
    }
    Task { @MainActor in
        model.cars = cars       // plain Sendable values cross the boundary
    }
}
```

Never carry a `DittoQueryResultItem`'s `value` (`[String: Any?]`, not `Sendable`) into a
`Task { @MainActor in … }`. Extract first.

### Back-pressure: `handler` versus `handlerWithSignalNext`

The `handler:` form signals for the next result automatically when the closure returns.
The `handlerWithSignalNext:` form hands you a `DittoSignalNext` closure and delivers
nothing further until you call it.

```swift
let observer = try ditto.store.registerObserver(
    query: "SELECT * FROM cars"
) { [weak self] result, signalNext in
    Task { @MainActor [weak self] in
        // FIRST statement in the body, so nothing below can skip it.
        defer { signalNext() }
        self?.apply(result.items)
    }
}
```

The invariant is **exactly one signal per delivery, from whichever context finishes the
work** — not "before the handler returns". Signalling after the UI work is the whole
point of the back-pressure form. Putting the `defer` at the top of the hopped body is
what makes an early return or a thrown error unable to wedge the observer.

Use `handlerWithSignalNext` whenever the handler does real work — decoding a large result
set, writing to another database, driving an animation. It converts *"fire as fast as
changes arrive"* into *"fire as fast as this app can keep up"*.

**While the handler holds `signalNext`, intervening changes are coalesced.** The next
callback carries the latest state, not a queue of every intermediate change. **Executed**:
with `signalNext` held, three inserts produced no deliveries at all; releasing it produced
a single delivery reporting all three rows — never one reporting 1 or 2.

Consequences to design for:

- An app using `signalNext` must be correct against "latest state". It must not treat
  callbacks as an event log, and must not assume it sees every intermediate value.
- **Forgetting to call `signalNext()` stops the observer forever.** No error, no log, no
  crash — updates simply never arrive again. Put it in a `defer` so early returns and
  error paths cannot skip it, and call it exactly once.

`DittoSignalNext` is `@Sendable` from 5.1.0 and a plain closure at 5.0.3 and 4.14.6 — see
[versions.md](versions.md#sendable-closure-aliases-arrive-in-510).

### `DittoDiffer`

```swift
public final class DittoDiffer {
    public init()
    public func diff(_ items: [DittoQueryResultItem]) -> DittoDiff
}

public struct DittoDiff {
    public let insertions: IndexSet
    public let deletions: IndexSet
    public let updates: IndexSet
    public let moves: [(from: Int, to: Int)]
}
```

That is deliberately the shape `UITableView` and `UICollectionView` batch updates
consume — but **not** `NSTableView`'s, and not a minimal edit script. Two measured
properties decide whether you can use it at all:

- **`moves` is a full permutation.** Moving one row to the front of a three-row list
  emits `(2→0), (0→1), (1→2)` — a move for every row whose index changed. Correct for
  `performBatchUpdates`, whose `at:` indices are pre-update and `to:` post-update, but it
  means one reorder in a 500-row list issues ~500 `moveRow` calls per delivery.
- **`NSTableView.moveRow(at:to:)` applies immediately and sequentially**, so replaying
  that same permutation walks `[a,b,c] → [c,a,b] → [a,c,b] → [a,b,c]` and lands back
  where it started while the model says `[c,a,b]`. Permanently stale rows, no crash, no
  log. **Do not replay `DittoDiffer.moves` into `NSTableView`** without first converting
  the permutation to sequential moves — or use `NSTableViewDiffableDataSource`, which
  does it for you.

**It is stateful.** `diff(_:)` compares against *the last array passed to that same
differ*, so one differ belongs to exactly one observer and is never shared between
observers or reused across queries. Identity is the `_id` field.

**The first call reports every item as an insertion** (**executed**) — the differ starts
empty, so initial load is a full population, not an animated insert of N rows. Subsequent
calls behave as expected: an unchanged result reports nothing, one added document reports
one insertion at its index, and an in-place field change reports one update (all
**executed**).

| | Use `DittoDiffer` | Skip it |
|---|---|---|
| **UIKit / AppKit** | Only when something that is *not* a diffable data source needs raw index sets. | **Usually skip at the skill's iOS 15 minimum.** `UITableViewDiffableDataSource` / `NSTableViewDiffableDataSource` compute the diff from a snapshot themselves, which makes the desynchronisation hazard below structurally impossible. |
| **SwiftUI** | Rarely. | **Usually skip.** `ForEach` over `Identifiable` data already diffs and animates. Running `DittoDiffer` and then handing SwiftUI an array makes the framework diff a second time — you pay twice and use neither result. |

**Two rules when you do use it, and both are easy to get wrong:**

1. **The array you hand the data source must be 1:1 with the array you handed the
   differ.** The index sets are computed over the raw `[DittoQueryResultItem]`. Drop one
   row between the two — a `compactMap` whose element initializer is failable is the
   usual way — and `performBatchUpdates` raises *"Invalid update: invalid number of rows
   in section 0"*. A malformed document can arrive from any peer at any schema version,
   so **map, never filter**.
2. **Reloads do not belong inside the batch.** `performBatchUpdates` treats deletes and
   inserts as one atomic transition, and a reload of a row that also moved is undefined.
   Apply `diff.updates` in the completion handler, against post-update indices.
   `NSTableView.reloadData(forRowIndexes:columnIndexes:)` is not a batch operation at
   all and must run after `endUpdates()`.

**Reset the differ whenever you re-register the observer.** Its baseline is the last
array it saw, so a differ reused across a cancel/re-register computes the first new diff
against stale state and produces index sets that do not match the view.

Costs, stated plainly:

- **Memory.** The differ retains the previous item set for the comparison, so a diffed
  observer holds roughly two result sets' worth of identity state for its whole lifetime,
  not as a transient spike.
- **Ordering constraint.** `diff(_:)` takes `[DittoQueryResultItem]`, so the items must
  still be materialized when it runs. That conflicts with the "extract and dematerialize
  promptly" rule unless you get the order right: **diff first, then extract, then
  dematerialize.** Dematerializing first is the natural reading of the two rules in
  isolation and it is wrong.
- **CPU.** One extra comparison pass per delivery, on top of the query — which is exactly
  when `handlerWithSignalNext` should be throttling deliveries. Use the two together.
- **Robustness.** `diff(_:)` decodes its result with `try!`
  (`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoDiffer.swift:43`), so a decode failure is
  a crash rather than a throw.
- **Thread safety.** `DittoDiffer` conforms to `Sendable`, so the compiler will let you
  call `diff(_:)` from two isolation domains — but it is mutable, stateful and not
  thread-safe. Call it from exactly one. The same caveat applies to
  `DittoQueryResultItem`, which is `Sendable` with a lazily materialized cache.

Compiled examples of both shapes — the diffable-data-source default and the corrected
`DittoDiffer` variant — live in the `getditto/agent-skills` repository under
`tests/swift-sdk/Sources/UIPatterns/`, and are built for iOS, the iOS Simulator, Mac
Catalyst and macOS against all three supported versions.

### There is no DQL observation publisher in Combine

Enumerating every public publisher at
`sdk-release-5.1.0:sdks/swift/DittoSwift/*+Combine.swift` yields exactly four:

| Publisher | Emits |
|---|---|
| `DittoAuthenticator.StatusPublisher` | `DittoAuthenticationStatus` |
| `DittoDiskUsage.DiskUsagePublisher` | `DittoDiskUsageItem` |
| `DittoPresence.GraphPublisher` | `DittoPresenceGraph` |
| `DittoStore.FetchAttachmentPublisher` | `DittoAttachmentFetchEvent`, with `.progress()` and `.completed()` |

**`store.observePublisher(query:)` does not exist.** Neither does any other query
publisher — the symmetry an agent expects from the other three aggregates is not there,
and 4.14.6's `LiveQueryPublisher` hung off the deprecated collection API and is gone. For
DQL observation, `registerObserver` is the only API on every supported line, and bridging
it into SwiftUI or Combine state by hand is the intended pattern, not a workaround.

```swift
// Bridging an observer into an AsyncStream is the idiomatic hand-rolled form.
// `.bufferingNewest(1)` is not optional: the default is `.unbounded`, and an observer
// that fires faster than the consumer drains will queue every intermediate result and
// then process a backlog that is already stale.
let (updates, continuation) = AsyncStream<[Car]>.makeStream(
    bufferingPolicy: .bufferingNewest(1)
)
let observer = try ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
    continuation.yield(result.items.map { item in
        defer { item.dematerialize() }
        return Car(item.value)
    })
}
// Tie the two lifetimes together, or a cancelled consumer leaves the observer firing
// into a dead stream for the life of the `Ditto` instance.
continuation.onTermination = { _ in observer.cancel() }

// ONE consumer task. A `Task { @MainActor in … }` per delivery has no ordering
// guarantee between deliveries, so an older result can land last and pin the UI to
// stale data. A single `for await` loop is ordered by construction.
let consumer = Task { @MainActor [weak model] in
    for await cars in updates { model?.cars = cars }
}
// … later
consumer.cancel()   // onTermination cancels the observer
```

Cancellation differs between the two styles: a Combine subscription is cancelled by
releasing its `AnyCancellable`, while an observer is cancelled by calling `cancel()` on
the handle. Releasing an observer handle does nothing.

The `@available` annotation on the four publishers is version-gated — see
[versions.md](versions.md#combine).
