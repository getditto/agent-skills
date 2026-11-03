# Observers and React

## CAP-11 Observers, diffing and back-pressure

Use the [provider and hook](../assets/DittoProvider.tsx). It waits for initialization,
surfaces startup errors, registers one subscription plus one observer per effect,
decodes before setting state, rejects rows from a previous query immediately, and
cancels handles on query changes/unmount. A catch path releases a subscription when
observer registration fails. The callback catches decode failures instead of throwing
through native bindings. Memoize argument objects and define the decoder outside render.

The default observer emits the current result set, not one event per write. Do not
assert one callback for every insert. For an expensive asynchronous consumer use
`registerObserverWithSignalNext`, complete each batch and always signal in `finally`.
`Differ` is an optional stateful aid for imperative lists; React can use decoded rows
and stable document IDs instead. Do not share a differ between unrelated queries.

The provider is an app-owned pattern inspired by the public react-ditto examples,
implemented independently with explicit lifecycle tests. Do not add `@dittolive/react-ditto`
as a dependency: these assets support web and native with the same ownership model.

Sources: <https://github.com/getditto/react-ditto/blob/master/src/DittoProvider.tsx>,
<https://react.dev/reference/react/StrictMode>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
