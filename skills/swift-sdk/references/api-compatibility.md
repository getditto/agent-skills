# Api compatibility — Ditto

## Contents

- [Presence and peers](#presence-and-peers)
- [Combine](#combine)
- [Fixes that skip a line](#fixes-that-skip-a-line)

Topic index: [versions.md](versions.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

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
stay identifiable in the presence graph (#SDKS-3944). An exhaustive `switch` still has to
handle it — and `.unknown(os:)`, where any unrecognised value lands.

---

## Combine

There has **never** been a DQL or store-query publisher in v5. Enumerating every public
publisher at `sdk-release-5.1.0:sdks/swift/DittoSwift/*+Combine.swift` yields exactly
four: `DittoAuthenticator.StatusPublisher`, `DittoDiskUsage.DiskUsagePublisher`,
`DittoPresence.GraphPublisher` and `DittoStore.FetchAttachmentPublisher`.

4.14.6 *did* have one — `LiveQueryPublisher` in
`cocoa/DittoSwift/Combine/DittoPendingCursorOperation+Combine.swift` — but it hung off
the deprecated collection API and was itself deprecated. It and `RemotePeersPublisher`
are gone by 5.1.0. Query publishers were removed, never carried forward.

The `@available` annotation on the surviving publishers is itself version-gated:
`@available(iOS 13, macOS 10.15, macCatalyst 13, tvOS 13, watchOS 6, *)` at 4.14.6 and
5.0.3, losing `tvOS 13` at 5.1.0.

---

## Fixes that skip a line

Newer is not uniformly better. Two fixes ship in 4.14.6 **and** 5.1.0 but **not** in any
5.0.x release:

| Fix | 4.14.6 | 5.0.3 | 5.1.0 |
|---|---|---|---|
| Uncaught exceptions in SDK callbacks re-raise with the original call stack instead of a `SIGABRT` attributed to Ditto (#SDKS-3483) | yes | **no** | yes |
| Use-after-deallocation throws instead of crashing (#SPO-960) | yes | **no** | **no** |

Other line-specific facts:

- **mDNS advertised and browsed with incorrect information before 4.14.3** (#NETW-883,
  `sdk/v4/release-notes/swift.mdx`) — the LAN-discovery failure mode below that patch.
- **Do not recommend 4.14.5**; the v4 release notes identify it as regressed
  (`sdk/v4/release-notes/swift.mdx:35`). Pin 4.14.6.
- **Custom `DITIdentityProvider` implementations stalled the SDK** on the first credential
  refresh until #SDKS-3623, fixed in 5.1.0 — a 5.0.x failure mode.

---
