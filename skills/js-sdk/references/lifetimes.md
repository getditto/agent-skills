# Ownership and teardown

| Resource | Owner | Release |
|---|---|---|
| Ditto instance | Application/account runtime | `close()` after application operations finish |
| Store observer | Hook/screen or repository | `cancel()` |
| Sync subscription | Data scope, possibly shared app scope | `cancel()` |
| Presence/auth observer | Diagnostics/session | `stop()` |
| Attachment fetcher | Transfer/task | `stop()` if abandoned |

[DittoProvider](../assets/DittoProvider.tsx) borrows the runtime; React effects own
only query handles. The application explicitly owns shutdown. Creating a runtime
inside render starts independent owners and causes `store/persistence-directory-locked`.
Do not add a `useRef` flag to skip Strict Mode's second effect: it conceals cleanup
bugs. Memoize query arguments and keep decoders stable, or every render replaces the
query. Changing account unmounts consumers before closing their owner.

JS results have their own lifetime model; do not copy Swift/Kotlin instructions that
claim every item becomes invalid at callback return. The examples immediately decode
rows to keep UI independent of SDK objects and to bound retained memory.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
