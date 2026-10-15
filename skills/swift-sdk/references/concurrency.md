# Concurrency and threading

## Contents

- [Where each callback runs](#where-each-callback-runs)
- [The eight rules](#the-eight-rules)
- [Starting Ditto exactly once from SwiftUI](#starting-ditto-exactly-once-from-swiftui)
- [Crossing the actor boundary without losing ordering](#crossing-the-actor-boundary-without-losing-ordering)

Which thread or actor every SDK callback arrives on, and what that forces the calling
code to do. The load-bearing rules are summarised in
[`SKILL.md` § Concurrency and threading model](../SKILL.md#concurrency-and-threading-model);
this file carries the per-API table and the reasoning.

## Where each callback runs

| API | Where its callback runs |
|---|---|
| `Ditto.open(config:)` | `async throws`, and **nonisolated**, so it runs on the cooperative pool rather than the caller's actor. Awaiting it from `@MainActor` does not block the main thread (**executed**). |
| `Ditto.openSync(config:)` | `throws`; blocks the calling thread for the whole open — on the main thread that is a launch-watchdog risk (**executed**). |
| `store.execute(query:arguments:)` | `async throws` and nonisolated, like `open`: it leaves your actor, then occupies one cooperative-pool thread for the whole statement — there is no suspension point inside it. Fine for ordinary statements; a very large one is worth keeping off a saturated pool. |
| `store.registerObserver(…, deliverOn:)`, `store.fetchAttachment(…, deliverOn:)` | the given `DispatchQueue`, default `.main` — **`registerObserver` ignores it on 5.0.x** |
| `sync.registerSubscription` | synchronous, `throws`; no callback |
| `presence.observe(didChangeHandler:)`, `DittoLogger.setCustomLogCallback` | an SDK thread; not `@Sendable`, not main-queue-guaranteed |
| `auth.login(…, completion:)` | an SDK thread; the completion **is** `@Sendable` on 5.0.x and 5.1.x, and is not on 4.14.x |
| `auth.expirationHandler` | `async`, off the main actor; `@Sendable` on 5.0.x and 5.1.x, not on 4.14.x |
| `presence.connectionRequestHandler` | an SDK thread; `@Sendable` on 5.0.x and 5.1.x, not on 4.14.x |

## The eight rules

1. **Never assume a callback is on the main actor.** `deliverOn:` is honoured on 4.14.6
   and 5.1.0 and silently ignored on 5.0.3, where using it with Swift concurrency is a
   documented crash (#SDKS-3856). Hop explicitly inside the handler and one source file
   is correct on all three lines.
2. **Convert before you cross.** `DittoQueryResultItem.value` is `[String: Any?]`, which
   is not `Sendable`. Extract into a value type *inside* the callback and send that.
   Subscripting that dictionary yields `Any??`, so `value["x"] as? String` is `nil` for a
   present field — collapse with `?? nil` first.
3. **Do the expensive work in the callback, not after the hop.** Decoding, diffing and
   sorting belong off the main actor; only the final assignment is main-actor work. A
   large result set decoded in a main-thread callback is the most common cause of a
   janky Ditto app.
4. **Hop with one consumer, not one `Task` per delivery.** Unstructured `Task`s have no
   ordering guarantee, so a burst can apply out of order and leave the UI on a stale
   result. Yield into an `AsyncStream(bufferingPolicy: .bufferingNewest(1))` and drain it
   from a single long-lived `@MainActor` task. The one exception is
   `handlerWithSignalNext`, where holding the signal across the hop means only one
   delivery is ever in flight — see
   [`observers.md`](observers.md#back-pressure-handler-versus-handlerwithsignalnext).
5. **Do not wrap `Ditto` in an actor.** `Ditto` and `DittoStore` are `Sendable` on v5;
   an actor adds hops without adding safety. Use actors for your own mutable async state,
   such as token acquisition.
6. **On 4.14.x, `@preconcurrency import DittoSwift`** — that line predates the `Sendable`
   conformances, and Swift 6 language mode rejects the same code without it.
7. **With `handlerWithSignalNext` only, `signalNext()` must be called exactly once per
   delivery**, from whichever context finishes the work; put the `defer` first in the
   hopped body.
8. **`auth.expirationHandler` must not touch UI state** — it is `@Sendable`, `async`, and
   runs off the main actor. It has no caller to rethrow to, so log failures there; never
   assign to `@Published` state from inside it.

## Starting Ditto exactly once from SwiftUI

Call the start path from SwiftUI's `.task`, not from `App.init()`. `.task` can run more
than once, and a second open on the same directory throws
`storeError(.persistenceDirectoryLocked)`.

**A `guard` alone does not prevent that.** The guard is checked before the first `await`,
so two callers both pass it and both proceed to open. Store the task *synchronously* and
await that instead:

```swift
private var startTask: Task<Void, Error>?

func start() async throws {
    if let startTask { return try await startTask.value }
    let task = Task { try await self.reallyStart() }   // no await before this line
    startTask = task
    try await task.value
}
```

`Ditto.open` is nonisolated `async` (SE-0338), so it leaves the caller's actor: awaiting
it from `@MainActor` does **not** block the main thread — measured at a 6 ms stall over a
120 ms open. `Ditto.openSync` on the main actor blocks for the full duration.
`Task.detached` around either buys nothing; it is the same cooperative pool.

Install `auth.expirationHandler` **before** `sync.start()`, or start throws
`DittoError.authenticationError(.expirationHandlerMissing)`. Await the login inside the
handler — it is `async` precisely so the SDK can wait for it, and a handler that
dispatches and returns leaves sync unauthenticated with nothing reporting it. Bound it
and retry: [`connect.md`](connect.md#cap-04-authentication-and-identity).

## Crossing the actor boundary without losing ordering

The observer handler, the stream and the consumer form a retain cycle through
`onTermination`, so the observer must be captured weakly:

```swift
let (updates, continuation) = AsyncStream<[String]>.makeStream(
    bufferingPolicy: .bufferingNewest(1))
let observer = try ditto.store.registerObserver(query: q, arguments: a) { result in
    continuation.yield(result.items.compactMap { item in
        defer { item.dematerialize() }
        return item.value["make"] as? String   // [String: Any?] is not Sendable
    })
}
// handler -> continuation -> onTermination -> observer would otherwise cycle
continuation.onTermination = { [weak observer] _ in observer?.cancel() }
let consumer = Task { @MainActor [weak self] in
    for await makes in updates { self?.makes = makes }
}
```

Teardown is the reverse of setup: `consumer?.cancel()`, `observer?.cancel()`,
`subscription?.cancel()`, `ditto?.sync.stop()`. See
[`lifetimes.md`](lifetimes.md).

A complete, compiled version of this shape is in
[`../examples/swiftui-app.md`](../examples/swiftui-app.md).
