# API traps

| Avoid | Use / observable failure |
|---|---|
| `new Ditto(identity)` on v5 | `Ditto.open(DittoConfig)`; constructor is internal. |
| `store.collection(...).find(...)` | DQL via execute/registerObserver; old query builder is removed. |
| `registerObserver(query, args, handler)` | Handler is the second argument in JS. |
| New instance on every render | One app runtime; duplicate persistence directory is locked. |
| Async observer without signalNext discipline | Explicit back-pressure; otherwise work overlaps. |
| Catch only rejected login promises | Inspect LoginResult.error too. |
| Put all data into a JSON.stringify dependency key | Memoized arguments; bigint/cycles break JSON serialization. |
| Assume local observer means remote subscription | Register the sync subscription separately. |
| Browser IndexedDB/offline-relaunch claims | WASM store is memory-only. |
| Changing paths to fix RN Fast Refresh | Full reload / disable Fast Refresh; preserve the persistent path. |

Tests exercise the exported assets rather than unmaintained copies in the harness.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
