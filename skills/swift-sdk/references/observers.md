# Observers, diffing and back-pressure — Ditto Swift SDK

This is where most Ditto Swift apps live, and where correct-looking code leaks, stalls or
janks. Read [`SKILL.md` § Concurrency and threading model](../SKILL.md#concurrency-and-threading-model)
first; this file is the detail.

## Contents

- Registering
- Retaining the handle is about cancelling, not about staying alive
- Where the callback runs
- An observer scoped to a selection
- Back-pressure: `handler` versus `handlerWithSignalNext`
- `DittoDiffer`
- There is no DQL observation publisher in Combine

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

This is the shape to use; everything below explains a part of it.

```swift
/// Extracted inside the callback, because `item.value` is `[String: Any?]` — not
/// `Sendable`, and it must not cross an isolation boundary.
///
/// Non-failable on purpose. A `DittoDiffer`'s index sets are computed over the raw
/// items, so dropping a row here desynchronises them from the data source; and a
/// malformed document can arrive from any peer at any schema version.
struct Car: Identifiable, Sendable, Equatable {
    let id: String, make: String, mileage: Int
    init(_ value: [String: Any?]) {
        self.id = Car.identity(of: value["_id"] ?? nil)
        self.make = value["make"] as? String ?? "Unknown"
        self.mileage = (value["mileage"] as? NSNumber)?.intValue ?? 0
    }

    /// `_id` need not be a `String` — a composite (map) `_id` is a supported Ditto
    /// pattern — and a positional fallback is not an identity.
    ///
    /// Switch rather than `as? String ?? String(describing:)`: a `[String: Any?]`
    /// subscript yields `Any??`, so the shorter form stringifies the inner optional and
    /// every non-`String` id comes out as `Optional(…)`. **Executed** — see
    /// `tests/swift-sdk` (`Car derives identity from a non-String _id`).
    static func identity(of rawID: Any?) -> String {
        switch rawID {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        case .none: return ""
        case .some(let other): return String(describing: other)
        }
    }
}

// `.bufferingNewest(1)`: the default is `.unbounded`, which lets a fast observer queue
// a backlog of results the UI will never display.
let (updates, continuation) = AsyncStream<[Car]>.makeStream(bufferingPolicy: .bufferingNewest(1))

let observer = try ditto.store.registerObserver(query: "SELECT * FROM cars") { result in
    // Off the main actor on 5.0.x, on `.main` elsewhere. Decode here either way — this
    // is the expensive part and it does not belong on the main thread.
    continuation.yield(result.items.map { item in
        defer { item.dematerialize() }
        return Car(item.value)
    })
}

// `[weak observer]`, or handler -> continuation storage -> onTermination -> observer
// is a retain cycle.
continuation.onTermination = { [weak observer] _ in observer?.cancel() }

// ONE consumer. A `Task { @MainActor in … }` per delivery has no ordering relation
// between deliveries, so an older result can be applied last and pin the UI to stale
// data. A single `for await` loop is ordered by construction.
let consumer = Task { @MainActor [weak model] in
    for await cars in updates { model?.cars = cars }
}
// … later: consumer.cancel(), which terminates the stream and cancels the observer.
```

Never carry a `DittoQueryResultItem`'s `value` (`[String: Any?]`, not `Sendable`) into a
`Task { @MainActor in … }`. Extract first.

**`map`, not `compactMap`** — and therefore the non-failable initializer above.
`compactMap` over a failable `init?` drops rows, which desynchronises a `DittoDiffer`'s
index sets from the data source; `map` over a failable initializer does not compile at
all, because it yields `[Car?]`. Where there is no differ — as in
[`examples/minimal-app.md`](../examples/minimal-app.md) — a failable initializer with
`compactMap` is fine.

**`onTermination` fires when the stream terminates — not when the consumer walks away.**
It runs on `continuation.finish()` (**executed**), on cancellation while the consumer is
suspended in the loop (**executed**), and when the last reference to the stream is
released. It does **not** run because a consumer `break`s out of the loop, returns early,
or never starts iterating (**executed**): the stream is still alive and the observer keeps
firing into it. Those paths need an explicit `cancel()`, or a scope that releases the
stream.

### An observer scoped to a selection

The common shape in a real app: a list screen observes everything, and a detail screen
observes **one** selected thing. The detail observer has to be created when the selection
happens and cancelled when the screen goes away — it cannot be app-lived, because its
query depends on what the user tapped.

A complete, compiled version is [`examples/swiftui-app.md`](../examples/swiftui-app.md).
Four things about it are not obvious:

**1. The owner starts empty and is started on appear.** `@Observable` + `@State` requires
a no-argument `init`, but the `Ditto` handle and the selected id only exist once a row is
tapped. So the store is constructed by `@State` and given its inputs in `.onAppear`:

```swift
@State private var tasks = ProjectTasksStore()      // no arguments available yet
…
.onAppear { try? tasks.start(ditto: store.ditto, projectID: project.id) }
.onDisappear { tasks.stop() }
```

**2. `start` must be idempotent.** `.onAppear` can run more than once for the same
screen. Registering twice leaves the first observer running forever with nothing
cancelling it. Guard on the identity you are already observing, and re-target rather than
stack when it differs:

```swift
if self.projectID == projectID, observer != nil { return }
stop()
```

**3. You usually cannot cancel from `deinit`.** A `@MainActor @Observable` owner has
actor-isolated stored properties, and `deinit` is nonisolated — so touching the observer
handle there does not compile under Swift 6 without isolated-deinit gymnastics. This is
why `.onDisappear` is the practical answer in SwiftUI, not merely one of three equals.
`deinit` remains correct for a non-isolated owner, and `viewDidDisappear` for UIKit.

**4. `.task(id:)` is the alternative, and it cancels for you.** If the screen keeps the
selection in state rather than being pushed per-selection, key the work to the id and let
SwiftUI tear it down on change or disappearance:

```swift
.task(id: project.id) {
    // cancelled automatically when project.id changes or the view goes away
    for await next in bridge.stream { tasks = next }
}
```

Use `.onAppear`/`.onDisappear` when the observer handle outlives a single `await`, and
`.task(id:)` when the whole consumption loop is the unit of work.

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

**This is the one place a `Task` per delivery is correct**, and it is worth being explicit
about why, because the rule above and [`SKILL.md`](../SKILL.md#concurrency-and-threading-model)
rule 4 both forbid the shape. Holding `signalNext` *inside* the hopped body means the SDK
does not deliver again until that task has finished, so there is never more than one in
flight and there is nothing to reorder. Take the `defer { signalNext() }` out of the
hopped body — signal in the outer handler instead — and the guarantee is gone: deliveries
overlap, and you are back to the unordered anti-pattern with no warning. With the plain
`handler:` form there is no such interlock, so use the single-consumer stream above.

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
[versions.md](versions.md#sendable-closure-aliases-two-arrive-in-50-the-rest-in-510).

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
consume — but **not** `NSTableView`'s, and not a minimal edit script. Two properties
decide whether you can use it at all — the first **reproduced by hand** on all three
lines, the second read from AppKit's own contract:

- **`moves` is a full permutation.** Moving one row to the front of a three-row list
  emits `(2→0), (0→1), (1→2)` — a move for every row whose index changed. Correct for
  `performBatchUpdates`, whose `at:` indices are pre-update and `to:` post-update. It
  does mean the call count scales with how far a row moved rather than with how many
  rows changed — measured at n=3; the cost at list scale follows from that, it was not
  itself measured.
- **`NSTableView.moveRow(at:to:)` applies immediately and sequentially** (AppKit's
  documented behaviour, not something this repo measures), so replaying
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

The hand-rolled bridge is the one at the top of this section. Its bounded buffering,
`onTermination` teardown and value extraction are exercised at runtime by the fixture's
`ObserverBridgeTests`.

Cancellation differs between the two styles: a Combine subscription is cancelled by
releasing its `AnyCancellable`, while an observer is cancelled by calling `cancel()` on
the handle. Releasing an observer handle does nothing.

The `@available` annotation on the four publishers is version-gated — see
[versions.md](versions.md#combine).
