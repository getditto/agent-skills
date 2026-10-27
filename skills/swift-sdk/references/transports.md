# Transports — Ditto Swift SDK

This file names Swift's transport **types, fields and update API**. *Which* transport to
prefer, what each radio can do on each platform, and the cost of changing transports at
runtime belong to the `ditto-mesh-networking` skill, or
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>.

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

**Never assign a freshly constructed `DittoTransportConfig()`** — see the table below
for why.

```swift
// WRONG — silently turns the whole mesh off.
var config = DittoTransportConfig()
config.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
ditto.transportConfig = config
```

**Symptom:** no compile error, no runtime error, `ditto.sync.isActive == true`, and the
device never discovers a peer again. A live instance has every peer-to-peer transport
enabled; a default-constructed value has them all disabled.

### The one Swift-specific default that matters here

**Which transports Ditto turns on by default, and why, belongs to
`ditto-mesh-networking`** — see that skill, or
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>. The
Swift-specific fact, and the reason for the anti-pattern above, is that *the two values
disagree*:

| Field | `ditto.transportConfig` on a live instance | `DittoTransportConfig()` |
|---|---|---|
| `peerToPeer.bluetoothLE.isEnabled` | `true` | **`false`** |
| `peerToPeer.lan.isEnabled` | `true` | **`false`** |
| `peerToPeer.awdl.isEnabled` | `true` | **`false`** |
| `peerToPeer.lan.isMDNSEnabled` | `true` | `true` — *does not differ* |
| `peerToPeer.lan.isMulticastEnabled` | `true` | `true` — *does not differ* |

Only the three `isEnabled` flags flip, which is exactly why assigning a fresh config
kills the mesh: the LAN sub-flags stay on but are inert while `lan.isEnabled` is false.
The remaining struct defaults are `connect.retryInterval` `5.0`, `listen.tcp.port`
`4040`, `listen.http.port` `80`, `global.syncGroup`/`routingHint` `0`, and empty
`connect` collections.

One version-gated default is genuinely this skill's: **the `DittoHTTPListenConfig`
struct default for `listen.http.webSocketSync` flipped from `true` to `false` in v5**.
Note the scope — a *live* instance reports `false` on all three lines, so an app that never built its own transport
config is unaffected. It matters only to code that constructs a `DittoTransportConfig` itself,
which is the anti-pattern above. See
[versions.md](versions.md#store-results-and-errors).

### Disabling cloud sync while keeping the mesh

```swift
ditto.updateTransportConfig { config in
    config.connect.webSocketURLs = []
}
```

See also <https://docs.ditto.live/sdk/latest/deployment/testing>.

### The setter is fatal, not throwing

Assigning a configuration Ditto rejects terminates the process (`fatalError`) rather than
throwing. Validate values —
particularly ports, interface IPs and URL strings — before assigning them.

### Transport conditions

`DittoTransportCondition` and `DittoConditionSource` are the Swift types; their **values
and cross-language naming** are `ditto-mesh-networking`'s. Both are `UInt32`-backed
enums with `CustomStringConvertible`.

### Connection types

`DittoConnectionType` is a `String`-backed, `CaseIterable` enum:
`.bluetooth`, `.accessPoint`, `.p2pWiFi`, `.webSocket`, and — **from 5.1.0 only** —
`.multicast`. An exhaustive `switch` written against 5.1.0 does not compile against 5.0.3
and vice versa.

The multicast transport itself is a private beta with hard prerequisites — see
[preview.md](preview.md).
