# Error handling

## CAP-16 Error handling

Await store promises and catch `unknown`; narrow with `error instanceof DittoError`
when dispatching on SDK `code`. Do not parse English error messages for program logic.

| Symptom/code | Response |
|---|---|
| `authentication/expiration-handler-missing` | Await handler installation before sync.start. |
| `store/persistence-directory-locked` | Find the second owner; stop/close it, preserve the store. |
| Invalid DQL / missing parameter | Fix query/arguments; don't retry deterministic errors. |
| Login resolves with `result.error` | Show authentication failure and use bounded session retry. |
| JS module loads but native module is missing | Rebuild native binary with autolinking; Expo Go cannot load it. |
| Browser WASM fetch/compile fails | Check version-matched WASM URL, MIME, CORS and CSP. |
| Process abort before JS catch | Inspect native startup environment/logs; JS cannot catch a native abort. |

A development host setting `NO_COLOR=1` caused a native 5.2.0 logger startup abort in
this fixture. Its launcher normalizes this boolean to `true` before loading the native
module. Keep this test-environment issue distinct from application error handling.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
