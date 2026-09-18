# Best practices — Ditto Swift SDK

Judgement calls with more than one working answer. Anything with a named symptom — a
compiler error, an exception, a crash — is in [`SKILL.md` § Anti-patterns](SKILL.md#anti-patterns)
instead, because that file is always loaded and this one is not.

## Instance ownership

**Start from the constraint, not the style.** A `Ditto` instance is genuinely app-scoped:
it owns a persistence directory, a sync session and a mesh presence. Opening a second one
against the same directory is an error, not a performance problem
([connect.md](references/connect.md#one-opened-instance-per-persistence-directory)). It has
to live for the whole app lifetime and be reachable wherever data is read.

**So the instinct to reach for a singleton is correct.** What differs per framework is the
idiomatic mechanism for expressing "one, app-lived, reachable everywhere".

| Framework | Mechanism | Why this one |
|---|---|---|
| **SwiftUI** | A `@MainActor` app model holding the instance, created once with `@StateObject` (or `@State` with `@Observable`) at the app root and injected down the tree. | Injection gives the singleton experience without a global: one property wrapper in any view, no shared static to import, exactly one instance across re-renders, and because it is injected rather than looked up, previews and tests can substitute a different instance. |
| **UIKit** | An app-scoped service owned by `AppDelegate`/`SceneDelegate` and injected into view controllers — **or a `static let shared` singleton**, which is a legitimate choice here. | UIKit has no environment-injection mechanism, so a singleton façade is the pragmatic path, not a compromise. Keep it a *thin* façade over an injectable service so a test can substitute one. |
| **AppKit** | Same as UIKit. **Window controllers own only window-scoped handles.** | The multi-window case is the hazard: closing one window must not deallocate an app-wide instance, and must not leave that window's observers running. Hold the instance with a plain `let`, not `unowned` — `unowned` is not weak, it *traps* on access after deallocation, and there is no cycle to break because Ditto holds nothing back to your controller. |

**`@EnvironmentObject` in SwiftUI and a `shared` singleton in UIKit/AppKit solve the same
problem** — app-wide reach to one long-lived instance. They are not different
architectures. A SwiftUI app does not need a singleton, and a UIKit app is not doing
something inferior by having one. Do not port a SwiftUI environment object into UIKit as a
global, and do not bolt a singleton onto a SwiftUI app that already has a composition root.

Whatever the mechanism, make it prove four things: re-entering a screen does not open a
second instance; losing a screen or a window does not stop app-required sync; observers are
cancelled at their owning scope's boundary; and a test or preview can substitute an
instance without editing production code.

**Which observation mechanism.** The SDK's minimum is not the app's deployment target.
For a new app targeting **iOS 17+ / macOS 14+, `@Observable` with `@State` and
`.environment(_:)` is the default** — it invalidates only the views that read a changed
property, where `ObservableObject` + `@Published` invalidates every observing view on
every change, which on a busy car list is the difference between a smooth and a janky
screen. `ObservableObject` / `@StateObject` / `@EnvironmentObject` is the back-deployment
path for iOS 15–16, which is what the compiled samples use so they build at the SDK's own
floor.

**`@EnvironmentObject`'s one sharp edge**, which the table above does not: a view resolved
without the object having been injected crashes at runtime with *"No ObservableObject of
type DittoAppModel found. A View.environmentObject(_:) for DittoAppModel may be missing
as an ancestor of this view."* It is a fatal crash, not a compile error, and the usual
places to hit it are exactly where a Ditto app goes — a `.sheet`, a `UIHostingController`
created from UIKit, a second `WindowGroup` on macOS, and previews. Inject at every
presentation root, not only at the app root. (`@Observable` + `.environment(_:)` has the
same failure mode.)

**Opening Ditto blocks, and a SwiftUI `App` cannot await in `init()`.** Model the launch
as a phase — `loading` / `ready(model)` / `failed(message)` — open the instance from
`.task`, and render the phase.

`Ditto.open` is `async` but does its work on the caller's executor, so `await`ing it from
a `@MainActor` model still opens the store on the main thread — a launch-watchdog
termination waiting for a large store. Wrap the open in `Task.detached` and await *that*
([connect.md](references/connect.md#open-versus-opensync)). Switching to `openSync`
changes nothing on its own; what matters is which executor the call runs on.

Compiled examples of all of this live in the `getditto/agent-skills` repository under
`tests/swift-sdk/Sources/UIPatterns/`.

## Structuring async work

- **Keep UI-facing state in a `@MainActor` model.** Its published properties are then
  written only on the main actor, and SwiftUI, UIKit and AppKit read them directly with no
  dispatch of their own. That is the whole payoff of the composition-root pattern.
- **Convert before you cross.** Extract plain Swift values from a `DittoQueryResultItem`
  and hand *those* across an isolation boundary. `[String: Any?]` is not `Sendable`.
- **Do the expensive work off the main actor.** Decoding, diffing and sorting belong on a
  background queue or in the callback itself; only the final assignment is main-actor work.
  A large result set decoded inside a main-thread callback is the usual cause of a janky
  Ditto app.
- **Hop with one consumer, not one `Task` per delivery.** Unstructured `Task`s have no
  ordering guarantee between them, so a burst of deliveries can apply out of order and
  leave the UI showing an older result. Yield into a bounded `AsyncStream`
  (`.bufferingNewest(1)`) and drain it from a single long-lived `@MainActor` task.
- **Do not wrap `Ditto` in an actor.** `Ditto` and `DittoStore` are `Sendable` on v5; an
  actor wrapper adds hops without adding safety. Reserve actors for application-owned
  mutable async state — a token store, a serialized upload queue.

## Retaining handles

Retention is about **being able to cancel**, not about keeping something alive. A store
observer or subscription lives until the owning `Ditto` does, whether or not you kept the
handle ([observers.md](references/observers.md#retaining-the-handle-is-about-cancelling-not-about-staying-alive)).

- Hold one long-lived strong `Ditto` reference at the composition root. Never retain only
  `store`, `sync`, `presence` or `auth` — they are aggregate children with weak parents.
- Keep an observer or subscription handle for exactly as long as the scope that consumes
  it, and cancel at that scope's boundary: `deinit`, `viewDidDisappear`, `.onDisappear`.
- Use `[weak self]` in callback closures. A strong `self` capture keeps a dead view
  controller alive for the life of the instance, because the observer is still running.
- Set `continuation.onTermination = { [weak observer] _ in observer?.cancel() }` when
  bridging an observer into an `AsyncStream`, so ending the stream cancels the observer
  instead of leaving it yielding into a dead one. Which paths actually run it — and which
  look like they should and do not — is in
  [observers.md](references/observers.md#where-the-callback-runs). Capture the observer
  **weakly**: the handler holds the continuation, whose storage holds `onTermination`, so
  a strong capture closes the loop. Note that a consumer which `break`s out of the loop
  does **not** run `onTermination` — the stream is still alive — so that path needs an
  explicit `cancel()`.
- Retain an attachment fetcher until its fetch completes or you stop it.
- **Read `ditto.sync.subscriptions` and `ditto.store.observers` fresh.** They are computed
  in v5; a cached snapshot never updates.

## Writes

- **Bind arguments; never interpolate.** `arguments:` exists for this, and typed `Codable`
  arguments exist for `registerObserver` and `registerSubscription`.
- **A transaction is for atomicity, not for speed.** Reach for one when several statements
  must land together or not at all. A single `INSERT` is already atomic.
- **Batch related writes into one transaction** rather than awaiting a series of
  `ditto.store.execute` calls — each of those opens its own one-off transaction.
- Decide up front whether a field is a `String` or a number, because the Swift type that
  comes back depends on what was stored
  ([store.md](references/store.md#numbers-do-not-have-one-swift-type)). Timestamps are
  ISO-8601 strings or integer epochs, never `Date`.

## Reads and observers

- **One observer per screen's worth of data, not one per row.** Each observer costs a live
  query in the SDK, and the callbacks are independent — ten observers on the same
  collection all wake up on every write to it.
- **Prefer a narrow query over filtering in Swift.** `WHERE` runs in the store; a
  `filter` in the callback re-runs on every delivery and still paid for the wide result.
- **Reach for `handlerWithSignalNext` when the handler does real work.** It turns "fire as
  fast as changes arrive" into "fire as fast as this app can keep up", at the cost of
  coalescing — the next delivery is the latest state, not every intermediate one.
- **Prefer a diffable data source in UIKit and AppKit**
  (`UITableViewDiffableDataSource`, `NSTableViewDiffableDataSource`), which compute the
  diff from a snapshot themselves. Reach for `DittoDiffer` only when something else needs
  the raw index sets — and never replay its `moves` into `NSTableView`
  ([observers.md](references/observers.md#dittodiffer)). In SwiftUI, `ForEach` over
  `Identifiable` data already diffs; adding a differ makes the framework diff twice and
  uses neither result.
- Use `execute` for a one-shot read where the current local state is genuinely enough, and
  an observer for anything the UI displays. `execute` does not wait for sync.

## Error handling

- Catch `DittoError` specifically. Its `LocalizedError` message is usually the only thing
  that says *which* statement or argument was wrong.
- **Distinguish the three classes**: code bugs (`queryInvalid`, `queryNotSupported`,
  `transactionReadOnly`) that no retry fixes; operator problems (`licenseTokenExpired`,
  `failedToAuthenticate`) that must be surfaced; and transient I/O that is worth a backoff.
- Do not treat "offline" as an error. `sync.start()` succeeds with no network and Ditto
  reconnects on its own; read connectivity from the presence graph instead.

## Sync handling

- **Start sync once, at launch, after authentication is configured.** Stopping and
  restarting sync discards mesh state and makes reconnection slower; it is not a way to
  save battery between screens.
- **`sync.stop()` is the "work offline" switch**, not a teardown. The local store stays
  fully usable.
- **Register subscriptions after `sync.start()`, and `ALTER SYSTEM` sync scopes before
  it.** The scopes ordering is a documented requirement, not a preference
  ([sync.md](references/sync.md#sync-scopes-are-dql-not-a-swift-type)).
- Keep the subscription set small and stable. Every subscription is a standing request to
  every peer; churn costs more than breadth.

## Performance

- The shape that matters most is **how much data each observer's query returns**, because
  that cost is paid on every delivery, not once.
- Index the fields a hot query filters or orders by
  ([store.md](references/store.md#cap-10-indexing)).
- **On 5.1.x, stop guessing which index is missing — ask.** `ADVISE <statement>` plans
  the statement without executing it and returns the `CREATE INDEX` statements the
  planner wants, each with the reason it wants them;
  `ADVISE AND PROVISION <statement>` creates them. Both run through
  `ditto.store.execute` like any other DQL (**executed**), and the recommendation is a
  ready-to-run composite index rather than a hint:

  ```swift
  let result = try await ditto.store.execute(
      query: "ADVISE SELECT * FROM cars WHERE mileage > 100 ORDER BY make"
  )
  // result.items[0].value["advice"] ->
  //   {
  //     "statement": "SELECT * FROM cars WHERE mileage > 100 ORDER BY make",
  //     "suggestedIndexes": [{
  //        "collection": "cars",
  //        "reason": "order by on `make`; range predicates on `mileage`",
  //        "statement": "CREATE INDEX IF NOT EXISTS adv_cars_make_mileage
  //                      ON default:`cars` (`make` ASC, `mileage` ASC)"
  //     }]
  //   }
  // ADVISE AND PROVISION returns the same entries under `createdIndexes`, not
  // `suggestedIndexes`.
  ```

  Reach for `ADVISE` first and `EXPLAIN` second: `ADVISE` tells you what is missing,
  `EXPLAIN` tells you what the planner did with what it has. On **4.14.x and 5.0.x
  `ADVISE` is a parse error** — `queryInvalid("… Unexpected token ADVISE …")`
  (**executed**) — so guard it by version. The grammar, the shape of the advice
  document and how to read `EXPLAIN` all belong to the `dql` skill, or
  <https://docs.ditto.live/dql/advise> and <https://docs.ditto.live/dql/explain>.
- `dematerialize()` a result item once you have extracted what you need, so the native
  copy is freed rather than held for the result's lifetime.
- Evict data the device no longer needs
  ([store.md](references/store.md#cap-17-device-storage-management-and-eviction)).
  An unbounded local store is the slow failure mode on long-lived devices.

## Common mistakes

- Treating `sync.isActive` as "connected". It means "sync was started".
- Building a new `DittoTransportConfig()` instead of mutating through
  `updateTransportConfig` — the fresh value has every peer-to-peer transport off.
- Putting a `Ditto` instance in a view model that the view owns, so a screen dismissal
  deallocates it.
- Assuming an observer callback is on the main queue. It is not on 5.0.x, and the same code
  is then correct on two lines and crashes on the third.
- Reporting failures with `print`. A `registerObserver` that throws during screen setup
  means the screen silently never populates; use `os.Logger` and surface the failure into
  the model's state so the UI can show it.
