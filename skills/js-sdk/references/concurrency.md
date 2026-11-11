# JavaScript concurrency

| API | Application contract |
|---|---|
| `init`, `Ditto.open`, `store.execute`, `store.transaction` | Await promises; do not use synchronous opening on a UI path. |
| `registerObserver` | Handler returns void on the JS runtime; returning a promise does not establish application back-pressure. |
| `registerObserverWithSignalNext` | Call `signalNext()` in a `finally` after processing, including failed processing. |
| `setExpirationHandler`, `auth.login` | Await installation and login; handle both thrown errors and `LoginResult.error`. |
| `presence.observe`, `auth.observeStatus` | Short JS callbacks; retain observer and stop it at teardown. |
| `cancel`, `stop` | Synchronous handle cleanup; guard callbacks against late delivery. |
| `Ditto.close` | Await shutdown before reopening the same directory. |

Decode only the projected fields needed by the screen. Avoid blocking JS with huge
JSON serializations. Marshal plain decoded values to React state; TypeScript generics
are not runtime validation. No Swift actor or Kotlin coroutine API belongs here.
Transactions must use `tx.execute`, never a nested transaction or `store.execute`
inside their callback; those can wait on the write lock held by the outer transaction.
Do not await UI input or a network request while holding a write transaction.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
