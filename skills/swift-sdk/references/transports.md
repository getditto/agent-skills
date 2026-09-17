# Transports — Ditto Swift SDK

This file names Swift's transport **types, fields and update API**. *Which* transport to
prefer, what each radio can do on each platform, and the cost of changing transports at
runtime belong to the `ditto-mesh-networking` skill, or
<https://docs.ditto.com/sdk/latest/sync/customizing-transport-configurations>.

Permission and entitlement declarations are in [setup.md](setup.md).

## CAP-06 Customizing transports

The configuration is one value type, `DittoTransportConfig`, with four groups:

```swift
public struct DittoTransportConfig: Sendable, Codable, Equatable {
    public var peerToPeer: DittoPeerToPeer   // bluetoothLE, lan, awdl, multicastBeta (5.1)
    public var connect: DittoConnect         // tcpServers, webSocketURLs, retryInterval
    public var listen: DittoListen           // tcp, http
    public var global: DittoGlobalConfig     // syncGroup, routingHint
}
```

### Always mutate through `updateTransportConfig`

```swift
ditto.updateTransportConfig { config in
    config.peerToPeer.bluetoothLE.isEnabled = false
    config.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
}
```

`updateTransportConfig` reads the live configuration, hands you an `inout` copy, and
writes it back. Changes take effect immediately; sync itself still does not begin until
`ditto.sync.start()`.

**Never assign a freshly constructed `DittoTransportConfig()`.** A live instance has
every peer-to-peer transport **enabled**; a default-constructed value has them all
**disabled**. Both were measured:

| | `ditto.transportConfig` on a live instance | `DittoTransportConfig()` |
|---|---|---|
| `peerToPeer.bluetoothLE.isEnabled` | `true` | `false` |
| `peerToPeer.lan.isEnabled` | `true` | `false` |
| `peerToPeer.awdl.isEnabled` | `true` | `false` |

```swift
// WRONG — silently turns the whole mesh off.
var config = DittoTransportConfig()
config.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
ditto.transportConfig = config
```

**Symptom:** no compile error, no runtime error, `ditto.sync.isActive == true`, and the
device never discovers a peer again.

### Measured defaults on a fresh instance

| Field | Default |
|---|---|
| `peerToPeer.bluetoothLE.isEnabled` | `true` |
| `peerToPeer.lan.isEnabled` | `true` |
| `peerToPeer.lan.isMDNSEnabled` | `true` |
| `peerToPeer.lan.isMulticastEnabled` | `true` |
| `peerToPeer.awdl.isEnabled` | `true` |
| `connect.tcpServers` / `connect.webSocketURLs` | empty |
| `connect.retryInterval` | `5.0` seconds |
| `listen.tcp.isEnabled` / `listen.http.isEnabled` | `false` |
| `listen.tcp.port` / `listen.http.port` | `4040` / `80` |
| `listen.http.webSocketSync` | `false` — **was `true` in v4** |
| `global.syncGroup` / `global.routingHint` | `0` |

`listen.http.webSocketSync` flipping to `false` in v5 is the one that breaks a working v4
app: anything that relied on the v4 default must now set it explicitly. See
[versions.md](versions.md#store-results-and-errors).

### Disabling cloud sync while keeping the mesh

```swift
ditto.updateTransportConfig { config in
    config.connect.webSocketURLs = []
}
```

Source: `sdk/latest/deployment/testing.mdx`.

### The setter is fatal, not throwing

Assigning a configuration Ditto Core rejects calls `fatalError`, not `throw`
(`sdk-release-5.1.0:sdks/swift/DittoSwift/Ditto.swift:357-372`). Validate values —
particularly ports, interface IPs and URL strings — before assigning them.

### Transport conditions

`DittoTransportCondition` and `DittoConditionSource` are the Swift types; their **values
and cross-language naming** are `ditto-mesh-networking`'s. Both are `UInt32`-backed
enums with `CustomStringConvertible`.

### Connection types

`DittoConnectionType` is a `String`-backed, `CaseIterable` enum:
`.bluetooth`, `.accessPoint`, `.p2pWiFi`, `.webSocket`, and — **from 5.1.0 only** —
`.multicast`. An exhaustive `switch` written against 5.1.0 does not compile against 5.0.3
and vice versa (**verified**: `DittoConnectionType.allCases` contains `Multicast` on
5.1.0 and does not on 5.0.3 or 4.14.6).

The multicast transport itself is a private beta with hard prerequisites — see
[preview.md](preview.md).
