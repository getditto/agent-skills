# Deployment Scenarios

Worked examples matching a real deployment to a transport configuration and a data model.
Each one states the constraint, the transport choice, what the mesh looks like, and — the
part that's easy to skip — what the transport choice implies for the schema.

Configuration is described in terms of the fields in
[`references/transport-config.md`](../references/transport-config.md); for the literal
syntax in your language, use that SDK's skill.

---

## 1. Restaurant point-of-sale — mixed iPads and Android handhelds, venue Wi-Fi that sometimes dies

**Constraint.** Orders must keep flowing when the access point goes down mid-shift. Devices
are a mix of iOS and Android, so no single P2P Wi-Fi technology covers the fleet.

**Transports.**

| Setting | Value | Why |
|---|---|---|
| `peerToPeer.lan.isEnabled` | `true` | Fast path while the AP is up. |
| `peerToPeer.bluetoothLE.isEnabled` | `true` | The **only** iOS ↔ Android path when the AP is down. |
| `peerToPeer.awdl.isEnabled` | `true` (Apple builds) | Fast infrastructure-free path between iPads. |
| `peerToPeer.wifiAware.isEnabled` | `true` (Android builds) | Same for the handhelds. |
| `connect.websocketUrls` | Ditto Server URL | Store-and-forward + backend integration. |
| `global.syncGroup` | location ID | Two restaurants in the same app don't discover each other. |

**Mesh shape.** Every peer a gateway: local convergence over LAN/AWDL/Wi-Fi Aware at local
latency, plus cloud store-and-forward. When the AP fails, LAN drops out and the multiplexer
switches those peer links to BLE with no application involvement.

**Why the failover is instant:** Ditto *maintains* a redundant BLE link alongside Wi-Fi by
default — it does **not** establish a new BLE connection on demand when the AP dies. That
redundancy is the failover. Keep it; see the warning in scenario 2.

**Data-model implication — this is the point.** The *worst case* here is BLE-only, so the
schema must be sized for 20 KB/s even though the common case is LAN.

- One document per order, not one document per table-session containing all its orders.
- Order line items embedded in the order document (bounded — an order has a handful of
  lines) is fine and gives you atomic writes.
- Order *history* for a table goes in its own collection, keyed by table `_id`. Unbounded
  growth must not live inside a document that syncs on every edit.
- Menu images: `ATTACHMENT`, always. A menu with embedded base64 images is a mesh-wide
  outage waiting for the AP to fail.
- Handhelds subscribe to today's open orders for their section, not to all orders.

---

## 2. Warehouse / airside operations — Android-only fleet, no usable Wi-Fi

**Constraint.** A large physical area with no reliable network infrastructure. Devices are
spread out; many pairs are never in direct range of each other.

**Transports.**

| Setting | Value | Why |
|---|---|---|
| `peerToPeer.bluetoothLE.isEnabled` | `true` | Long-ish range, works with no infrastructure. |
| `peerToPeer.wifiAware.isEnabled` | `true` | Much faster than BLE when two devices are close. All-Android fleet, so this covers every pair. |
| `peerToPeer.lan.isEnabled` | `true` | Costs nothing; picks up any Wi-Fi that does exist. |
| `connect.websocketUrls` | Ditto Server URL, if reachable at all | May only connect when a device returns to an office. |

**Mesh shape.** A sparse, multihop, constantly churning mesh. Most peer pairs are **not**
directly connected; updates travel several hops through intermediate devices. Churn is what
keeps the far corners from islanding.

**Data-model implication.** This is the hard case — BLE-dominated with multihop relaying, so
every byte is paid for repeatedly along the path.

- Documents in the **single-digit to low tens of KB**. Aggressively split.
- No document that grows with activity. A `location` document with an embedded scan history
  will be re-merged on every scan, at every hop.
- Everything binary is an `ATTACHMENT`, and expect attachments to arrive much later than the
  documents referencing them — design the UI for "record present, photo pending".
- Subscriptions scoped by zone, not fleet-wide. First sync over BLE for a full dataset is
  measured in minutes.
- Peer metadata: a device ID and a zone. Nothing more.

**Also worth considering:**
`ALTER SYSTEM SET mesh_chooser_avoid_redundant_bluetooth = true` stops BLE slots being spent
on peers that already have a good Wi-Fi Aware route — BLE slots per peer are few, so slot
allocation is the scarce resource.

**But understand the trade.** This disables the redundant BLE link that makes Wi-Fi→BLE
failover instant. A peer whose Wi-Fi Aware link drops must then establish BLE from scratch.
Do **not** set it where fast failover matters (scenario 1's point-of-sale case is exactly
where you would leave it off). Set it before `startSync()`.

---

## 3. Kiosk / fixed infrastructure on a routed enterprise network

**Constraint.** Devices are stationary, on a corporate network where mDNS and multicast are
blocked or the peers are on different subnets. Addresses are known and stable.

**Transports.**

| Setting | Value | Why |
|---|---|---|
| `peerToPeer.lan.isEnabled` | `false` | mDNS/multicast won't traverse the network anyway. |
| `listen.tcp.isEnabled` | `true` | Accept inbound sync. |
| `listen.tcp.interfaceIP` / `port` | `[::]` / `4040` | Bind all interfaces — never the literal string `"localhost"`. |
| `connect.tcpServers` *or* `TRANSPORTS_DISCOVERED_PEERS` | the known peer addresses | Explicit topology. |
| `connect.websocketUrls` | Ditto Server URL | |

Where the peer set is dynamic, use the discovery-hint pattern: read
`SELECT * FROM system:transports_info WHERE _id = 'discovery_hint'` on each peer,
distribute IP + port + hint through your own service, and write peers into
`TRANSPORTS_DISCOVERED_PEERS` — carrying the remote peer's hint in the entry's
`discovery_hint` field — with `type: 'force'` for links that must always exist.

**Data-model implication.** TCP over a wired/enterprise network is high-bandwidth. Standard
Ditto modeling applies — embed related data, use maps keyed by ID, split only for permission
scope or genuine unbounded growth.

---

## 4. Browser dashboard alongside a native fleet

**Constraint.** An operations dashboard runs in a browser; the field devices are native.

**Transports.**

- Browser peer: `connect.websocketUrls` only. Any peer-to-peer transport in a Wasm build is
  a **validation error**, not a silent no-op.
- Native peers: their normal P2P mix **plus** a WebSocket URL.

**Mesh shape.** The browser is a leaf on Ditto Server. It never participates in the P2P
mesh and cannot relay for nearby devices. Native peers converge locally at local latency
and reach the dashboard through the server.

**Data-model implication.** Nothing changes for the browser's sake — but note the dashboard
sees data only after it reaches Ditto Server. If the field mesh is operating offline, the
dashboard is stale by definition. Don't build alerting that treats dashboard staleness as a
device fault.

---

## 5. Air-gapped deployment — no cloud at all

**Constraint.** No internet, by policy. Sync happens only among devices present.

**Transports.**

- All available P2P transports enabled.
- `connect.websocketUrls` empty.
- Optionally TCP listen/connect if there is a fixed local server peer.

**Mesh shape.** Pure small-peer mesh. Fully functional and fully offline. The one thing it
does not have is store-and-forward — **two peers that are never co-located (directly or
through a chain of intermediates) never exchange data.** If some device pairs never overlap
in time or space, you need a physically mobile relay device, not a configuration change.

**Data-model implication.** Model for the slowest transport in the mix, as above. Also
consider: with no cloud peer, there is no always-on peer holding the full dataset. A device
that has been away for a week converges only against whatever the peers it meets happen to
hold.

---

## 6. Runtime reconfiguration: "battery saver turns off Bluetooth"

**The requirement.** An app setting that disables BLE to save power.

**The correct implementation.** Read the current transport config, set
`peerToPeer.bluetoothLE.isEnabled = false`, apply. **Do not construct a fresh
`TransportConfig`** — it starts all-disabled, so you would also silently take down LAN,
AWDL, and Wi-Fi Aware.

**What happens.** BLE stops and its connections drop immediately. Every other transport is
untouched — a LAN transfer in flight is not interrupted. Turning it back on restarts
discovery; connections re-form over the following seconds.

**What to tell the user.** On a mixed iOS/Android fleet with no Wi-Fi, disabling BLE
disables *all* cross-platform sync. Verify the saving is real before shipping it: a peer
that loses its BLE path may end up relaying everything over a longer route, spending *more*
radio time, not less.

**Related trap.** If the setting also lets users switch sync group (site selection, say),
**stop sync before changing `global.syncGroup` and start it after.** Changing it live forces
an internal sync restart.
