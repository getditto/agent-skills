# API compatibility — Ditto Swift SDK

## Contents

- [Presence and peers](#presence-and-peers)
- [Combine](#combine)

Presence and Combine renames between 4.14.x and v5. Every other per-line difference, and
the known issues on each line, are in [versions.md](versions.md).

## Presence and peers

| 4.14.x | v5 |
|---|---|
| `DittoPeer.peerKeyString` | `peerKey` |
| `DittoPeer.isConnectedToDittoCloud` | `isConnectedToDittoServer` |
| `DittoPeer.osV2` | `os` |
| `DittoConnection.peerKeyString1` / `2` | `peer1` / `peer2` |
| `ditto.observePeers` / `observePeersV2` | `presence.observe(didChangeHandler:)` |
| `DittoRemotePeer`, `DittoAddress`, `DittoConnectionPriority`, `approximateDistanceInMeters` | removed |

`DittoPeerOS.tvOS` is **deprecated but retained** in 5.1.0 so peers on older tvOS SDKs
stay identifiable in the presence graph. An exhaustive `switch` still has to handle it —
and `.unknown(os:)`, where any unrecognised value lands.

---

## Combine

v5 has no DQL or store-query publisher. The public publishers in 5.1.0 are exactly four:
`DittoAuthenticator.StatusPublisher`, `DittoDiskUsage.DiskUsagePublisher`,
`DittoPresence.GraphPublisher` and `DittoStore.FetchAttachmentPublisher`.

4.14.x has `LiveQueryPublisher`, but it belongs to the deprecated collection API and is
itself deprecated. It and `RemotePeersPublisher` are gone by 5.1.0. For query results,
use a store observer — see [observers.md](observers.md).

The surviving publishers are annotated
`@available(iOS 13, macOS 10.15, macCatalyst 13, tvOS 13, watchOS 6, *)` on 4.14.6 and
5.0.3; 5.1.0 drops `tvOS 13`.
