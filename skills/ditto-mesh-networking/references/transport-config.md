# Transport Configuration Reference

The configuration object every Ditto SDK exposes, field by field, plus the exact semantics
of changing it while sync is running.

**Naming.** Field names below use the canonical camelCase shape. Each SDK spells them
idiomatically (`peerToPeer` / `peer_to_peer`, `bluetoothLE` / `bluetooth_le`,
`isEnabled` / `enabled`), and the *update* entry point differs too — a mutable
`transportConfig` property on some SDKs, an `updateTransportConfig { … }` closure on
others, a `setTransportConfig(config)` call on others. **The structure is the same
everywhere, except that SDKs omit sections their platform cannot use** — Swift has no
`wifiAware`, Kotlin has no `awdl`. For the literal syntax, use the SDK skill for your
language.

---

## 1. The shape

```
transportConfig
├── peerToPeer
│   ├── bluetoothLE   { isEnabled }
│   ├── lan           { isEnabled, mdnsEnabled, multicastEnabled }
│   ├── awdl          { isEnabled }            # Apple platforms only
│   └── wifiAware     { isEnabled }            # Android only
├── connect
│   ├── websocketUrls  Set<String>             # wss:// endpoints
│   ├── tcpServers     Set<String>             # host:port
│   └── retryInterval  Duration                # default 5s
├── listen
│   ├── tcp   { isEnabled, interfaceIP, port }
│   ├── udp   { isEnabled }
│   └── http  { isEnabled, interfaceIP, port, websocketSync, TLS/identity options }
└── global
    ├── syncGroup    UInt32                    # default 0
    └── routingHint  UInt32                    # default 0 (no preference)
```

---

## 2. `peerToPeer` — discovery-based transports

| Field | Default in a config *you* construct | Notes |
|---|---|---|
| `bluetoothLE.isEnabled` | `false` | Available on all native platforms. |
| `lan.isEnabled` | `false` | Enables the LAN stack as a whole. |
| `lan.mdnsEnabled` | `true` | Only takes effect when `lan.isEnabled` is true. |
| `lan.multicastEnabled` | `true` | Alternative discovery channel; same gating. |
| `awdl.isEnabled` | `false` | **Apple only.** Enabling it elsewhere is a validation error. |
| `wifiAware.isEnabled` | `false` | **Android only** (API 29+). Same rule. |

> ### The all-disabled default
>
> **A `TransportConfig` you construct yourself starts with every transport disabled.** The
> SDK's built-in default config enables the platform-appropriate P2P transports (and adds
> your Ditto Server URL if you supplied a cloud credential), but supplying your own object
> replaces that wholesale.
>
> The safe pattern in every SDK is **read-modify-write**: take the current config, change
> the one field you care about, apply it back. Constructing a fresh config to "just turn on
> Bluetooth" silently disables LAN, AWDL, and Wi-Fi Aware.

**Whether a platform mismatch is rejected depends on the SDK, not the platform.** Core
*can* reject AWDL on non-Apple and Wi-Fi Aware on non-Android, but each SDK chooses whether
to run that validation:

| SDK | Platform mismatch on native |
|---|---|
| **JavaScript / React Native, Go** | **Throws**, naming the offending transports |
| Swift, Kotlin/Java, .NET, C++, Rust, Python | Accepted silently — the transport never starts and no log line is emitted |

Wasm/browser builds always reject any P2P transport, `connect.tcpServers`, or a TCP/HTTP
listener. **Do not rely on config validation to catch a platform mismatch** unless you are
on JS or Go.

**Bluetooth LE tuning.** Some SDKs expose advertisement power and advertisement interval
hints on the BLE config. Note that changing them while BLE is already enabled is a **silent
no-op** — the runtime diff looks only at `isEnabled`; stop and re-enable the transport to
apply them.

The `maxOutgoing` field on the Java/Kotlin BLE config has been **removed** from current SDKs
and is inert in core. Use the `mesh_chooser_max_active_ble_clients` system parameter instead
(see [`mesh-formation.md`](mesh-formation.md)).

---

## 3. `connect` — outbound to known addresses

| Field | Default | Notes |
|---|---|---|
| `websocketUrls` | empty (in a config you construct; see note) | `wss://…` (or `ws://…` for local/on-prem) endpoints for Ditto Server, or for a peer serving sync over its HTTP listener. Note: with SDK v5 the managed Big Peer WebSocket is auto-configured into this set by initialization, so the *effective* value is normally non-empty in a cloud deployment — the `empty` default describes a bare constructed config. |
| `tcpServers` | empty | `host:port` strings for raw TCP sync with a known peer. |
| `retryInterval` | 5 seconds | **Mesh-wide**, not WebSocket-specific: the minimum interval between connection attempts to the same peer on a given transport. Changing it re-paces BLE, LAN and TCP retries too. WebSocket skips the cooldown on its *first* attempt. |

**Cloud sync.** SDKs that offer an `enableDittoCloudSync` / cloud-sync flag manage the
Ditto Server URL for you. Set it to `false` when you supply your own `websocketUrls` —
otherwise you can end up with both the managed URL and yours.

**Removing all WebSocket URLs disables Ditto Server sync instantly** — *unless* cloud sync
is enabled via `enableDittoCloudSync` / `cloud.enabled`, in which case the managed URL is
re-added behind your back and sync continues. Turn cloud sync off first. Clearing the URLs
never touches peer-to-peer transports.

If your app is configured for a Ditto Server but `websocketUrls` ends up empty, the SDK
logs a warning that the transport configuration is incomplete. Treat that warning as an
error in your own config validation — it is the usual symptom of a fresh-config overwrite.

---

## 4. `listen` — accepting inbound connections

| Field | Default | Notes |
|---|---|---|
| `tcp.isEnabled` | `false` | Accept inbound TCP sync connections. |
| `tcp.interfaceIP` | `[::]` (all interfaces) | Use `0.0.0.0` or `[::]` for all. **Do not pass the string `"localhost"`.** |
| `tcp.port` | `4040` | |
| `http.isEnabled` | `false` | Specialized deployments only. |
| `http.interfaceIP` | `[::]` | |
| `http.port` | `80` | |
| `http.websocketSync` | `false` in core (**`true`** in the Rust and .NET SDK builders) | Serve sync over the HTTP listener. Check your SDK rather than assuming the core default. |
| `http` TLS / identity-provider options | unset | Key/cert paths, identity-provider signing and verifying keys, CA key — for offline identity provisioning. |

The listeners are for less common data-sync scenarios. An incorrectly configured listener
can be insecure — read the deployment documentation before enabling `http`.

---

## 5. `global` — mesh-wide settings

### `syncGroup` (default `0`)

By default every device sharing an app ID forms one interconnected mesh. A sync group
partitions that: peers only form automatic connections **within** their group. Up to 2³²
groups; a device belongs to exactly one.

Typical use: two restaurants, two floors, two vehicles — same app, no reason for their
devices to burn radio time discovering and syncing with each other. Groups are commonly
assigned from an authentication webhook so the value comes from the peer's identity.

Two rules, both important:

1. **A sync group is an optimization, not a security control.** A manually created
   connection — an explicit `connect` address, a forced discovered peer — syncs across
   groups normally. If two groups must not see each other's data, enforce it with Ditto's
   permissions system.
2. **Do not change `syncGroup` while sync is active.** Ditto detects the change, logs a
   warning, and restarts sync internally to apply it. Stop sync, set the group, start sync.

### `routingHint` (default `0`, meaning no preference)

A cloud-side performance hint, not a data partition. Devices that operate on much the same
data — in practice, devices running the same or overlapping subscriptions — should share a
routing-hint value; Ditto makes a best effort to co-locate that data in Ditto Server, which
improves responsiveness for large collections.

**It does not affect query results** — it never filters or partitions data, only where the
cloud keeps it.

---

## 6. Runtime update semantics

Applying a new configuration **diffs it against the current one and reconciles each
transport independently**. You do not stop and start sync.

### Per-transport

| Transition | What happens |
|---|---|
| `false` → `true` | The transport starts: discovery begins, connections form over the next seconds. |
| `true` → `false` | The transport stops. Its physical connections drop immediately. |
| unchanged | Nothing happens. Live connections on that transport are **not** disturbed. |

Because unchanged transports are untouched, a well-scoped update is genuinely surgical:
turning Bluetooth off does not interrupt an in-flight LAN transfer.

**Three exceptions**, because the diff runs on the *resolved* config rather than the raw one:

1. Changing `global.syncGroup` while sync is active tears down and restarts **every**
   transport, not just sync.
2. Adding or removing `connect.tcpServers` can re-bind the TCP listener and start/stop LAN
   discovery, dropping inbound TCP connections — even though you never touched `listen` or
   `lan`.
3. `connect.retryInterval` is re-applied on every update, changed or not.

### Other fields

| Change | What happens |
|---|---|
| Add a WebSocket URL | Connection attempts begin; retried on `connect.retryInterval`. |
| Remove all WebSocket URLs | Ditto Server sync stops immediately; P2P unaffected. |
| Add / remove `tcpServers` | Connection attempts start / stop for those addresses. |
| Change `listen.tcp` fields | Listeners are re-bound with the new address and port. |
| Change `global.syncGroup` while sync is active | Sync is torn down and restarted internally, with a warning. Prefer stopping sync first. |
| Change `global.routingHint` | **No effect on existing Ditto Server connections.** The hint is attached only to WebSocket URLs added *after* the change, or after a stop/start sync cycle. Set it before starting sync. |

### What an update does *not* do

- **It never loses data.** Dropping a transport drops connections, not writes. Local writes
  continue while a peer is fully isolated, and CRDT merge reconciles when any path back
  into the mesh reopens.
- **It does not corrupt in-flight transfers.** A document interrupted mid-transfer resumes.
  It simply stays absent from the receiving peer's query results until it has arrived
  completely.
- **It cannot enable a transport the platform refuses.** OS Bluetooth off, Wi-Fi off,
  permission not granted, hardware unsupported — configuration is inert against all of
  these. Observe the SDK's transport-condition callback to distinguish "I disabled it" from
  "the platform won't give it to me". See
  [`platform-requirements.md`](platform-requirements.md).
- **It does not restart sync.** Except for the `syncGroup` case above.

### Ordering caution

If you are simultaneously starting sync and setting configuration, set the configuration
**before** starting sync where the SDK allows it. That avoids a window where the peer runs
with the default transport set — which for a P2P-heavy default may briefly connect to peers
your final configuration would have excluded.

---

## 7. Transport settings that live in DQL, not in the config object

A few transport-adjacent settings are system parameters or virtual collections rather than
fields on the config object. They are the same on every SDK.

| Statement | Purpose |
|---|---|
| `ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS = [{'address': 'tcp://10.0.0.143:12345', 'type': 'force'}]` | Point this peer at peers by address, bypassing mDNS. `address` is a URL (`tcp://`, `ws://`, `wss://`); `type` is `candidate` (default — attempt; may persist after removal) or `force` (always attempt; drops on removal); optional `discovery_hint` carries the remote peer's hint. SDK 4.12.0+. |
| `SELECT * FROM system:transports_info WHERE _id = 'discovery_hint'` | Read this peer's opaque discovery hint, for out-of-band peer exchange. May change on `startSync()`; in practice regenerated per Ditto instance (app restart) — re-read rather than cache. |
| `ALTER SYSTEM SET mesh_chooser_max_active_ble_clients = <n>` | Cap outgoing BLE client connections. |
| `ALTER SYSTEM SET mesh_chooser_avoid_redundant_bluetooth = true` | Suppress BLE connections to peers already well connected by a faster transport. |
| `ALTER SYSTEM SET document_size_soft_limit_bytes = <n>` / `document_size_hard_limit_bytes = <n>` | Document size thresholds. **Keep identical across your small peers.** Ditto Server has no such parameter and applies its own limit. |

For the syntax and semantics of `ALTER SYSTEM` / `SHOW`, use the `write-dql` skill.

> **Before relying on these in production**, confirm with Ditto which system parameters are
> supported for your SDK line — the set exposed via `ALTER SYSTEM` is not a stable public API
> in its entirety, and Ditto's documentation directs users to check with the team.
