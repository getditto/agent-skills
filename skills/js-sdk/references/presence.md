# Presence

## CAP-13 Presence graph and connection requests

`ditto.presence.graph` contains `localPeer` and `remotePeers`. Retain the handle from
`presence.observe(graph => ...)` and call `stop()` on teardown. Peer names are display
labels, not unique IDs. Use peer keys to identify peers; metadata is not authorization.

`presence.connectionRequestHandler` is a property, not a registration function. Its
return type is `ConnectionRequestAuthorization`; check the installed type before using
it. Decisions must finish promptly and fail closed; do not await a user prompt there.
Presence of a peer or a server connection does not prove a particular document arrived.
Radio transport behavior needs physical-device verification, independently of this API.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
