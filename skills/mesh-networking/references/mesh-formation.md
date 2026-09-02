# Mesh Formation Reference

How a Ditto mesh actually comes together: the lifecycle from `startSync()` to converged
data, why peers connect to *some* peers and not all of them, and what that means for
anything you build on top of connection state.

---

## 1. The six stages of a sync

Every sync problem localizes to one of these. Knowing the stage you're stuck in is most of
the diagnosis.

1. **Startup** — the app calls `startSync()` and the SDK initializes each enabled
   transport.
2. **Transport configuration** — was each transport created with valid parameters? A
   `wss://` URL that parses; at least one peer-to-peer transport enabled; platform
   supports what you asked for.
3. **Discovery / reachability** — can this peer *see* another one? BLE advertise+scan,
   mDNS browse, multicast, Wi-Fi Aware publish/subscribe, or — for Ditto Server — the
   `wss://` upgrade reaching the endpoint and auth succeeding.
4. **Connection** — the underlying physical connection completes: TCP for LAN/AWDL/Wi-Fi
   Aware, GATT for BLE, the WebSocket upgrade for Ditto Server.
5. **Virtual-connection acquisition** — the multiplexer binds one or more physical
   connections to a **virtual connection** scoped to a specific remote peer. This is the
   layer sync actually runs on. A physical connection with no virtual connection means
   bytes are on the wire but no peer session is using them.
6. **Replication** — updates flow on the virtual connection *and* are committed to the
   local store.

Stages 3–6 run independently per transport and per remote peer. A peer can be at stage 6
with one neighbour and stage 3 with another at the same time.

---

## 2. The multiplexer and the rainbow connection

The same two peers are often reachable over several transports at once — BLE *and* LAN,
say, or AWDL *and* BLE. Ditto does not treat those as separate peers or duplicate the data
across them.

Instead the **multiplexer** pools every physical connection to a given remote peer into one
**virtual connection**, fragments outbound messages, reassembles them on the far side, and
picks which physical link actively carries traffic — switching as conditions change, with
no application involvement and no duplicated bytes. Ditto calls the resulting
multi-transport fabric the **rainbow connection**: each colour is a different transport,
all working in parallel.

Two practical consequences:

- **Enabling more transports is close to free and strictly increases resilience.** A peer
  that has BLE and LAN keeps syncing when the access point dies; a peer with only LAN
  stops. Leave transports on unless you have a measured reason not to.
- **The transport carrying your data is not stable, and shouldn't be.** Do not build logic
  that assumes "this peer is a Bluetooth peer".

The multiplexer also adapts its framing to the link: on a slow transport it sends much
smaller chunks than on a fast one, so a single large message cannot monopolize a
low-bandwidth link. This helps interleaving, but it does not change the fundamental
throughput ceiling — a large document over BLE is still slow.

---

## 3. Discovery, presence, and multihop routing

Discovered peers form a **presence graph** — the local peer's view of who exists in the
mesh and which peers are connected to which. It's a map, and Ditto uses it like one:
updates take the shortest, fastest path from A to B, and when an intermediate peer
disappears, routes are recomputed and traffic reroutes around it.

This is why **not being directly connected to a peer is not a sync failure.** A tablet at
the far end of a warehouse can converge with the point-of-sale terminal at the front
through a chain of intermediate devices, none of which needs any application code.

The presence graph is observable from every SDK (a presence/observe API). What each peer
exposes to the graph includes optional **peer metadata** — an application-defined
dictionary, visible to every peer in the mesh.

Two rules for peer metadata:

- **Keep it small.** Peer metadata syncs across the mesh on *every new connection*. Large
  metadata over BLE slows or disrupts connection establishment for everybody. The hard
  limit is **4 KB when JSON-encoded**; exceeding it throws a size-limit error. (Do not
  confuse this with the *Small Peer Info* metadata API, a different surface with a 128 KB
  limit.)
- **Keep it non-sensitive.** It is visible to every connected peer.

---

## 4. Why peers don't all connect to each other

A fully connected mesh would not scale — radios saturate, discovery storms, batteries
drain. Ditto instead runs an aggressive connection burst at startup (existing peers welcome
newcomers), then settles into a bounded, deliberately churning topology.

### Connection caps

Each transport caps how many direct neighbours a peer maintains, and **the caps differ by
transport because the power cost differs by transport**:

| Transport | Relative budget | Why |
|---|---|---|
| **LAN** (TCP over Wi-Fi or Ethernet) | Most generous | The radio is already associated with the access point and the AP does the work. Extra connections are close to free, so a peer maintains more of them. |
| **P2P Wi-Fi** (AWDL, Wi-Fi Aware) | Fewer than LAN | Drives the Wi-Fi radio directly, with no infrastructure to offload to. Each connection costs real battery, so the budget is tighter. AWDL and Wi-Fi Aware share one budget — they are two implementations of the same idea and never run against each other. |
| **Bluetooth LE** | Fewest | Lowest power *per byte*, but connection slots are scarce: the OS Bluetooth controller has a small total connection budget that Ditto shares with every other BLE app on the device. Inbound and outbound are budgeted separately. |
| **WebSocket → Ditto Server** | No SDK-side cap | The server applies its own limits. |

The exact numbers are internal defaults that change between releases, so they are not
documented here — design for the *ordering*, not for a count. The practical consequence is
the one that matters: **on BLE a peer holds only a handful of direct neighbours**, so which
peers occupy those slots matters far more than it does on LAN.

Two BLE parameters are publicly documented and intended for tuning:

```sql
-- Cap outgoing BLE client connections
ALTER SYSTEM SET mesh_chooser_max_active_ble_clients = 3

-- Skip BLE connections to peers that already have a better route into the mesh
ALTER SYSTEM SET mesh_chooser_avoid_redundant_bluetooth = true
```

Lower BLE caps leave more radio capacity for non-Ditto BLE peripherals and reduce overhead,
at the cost of slower convergence in dense meshes.

**Set these before `startSync()`.** Per-transport connection limits are snapshotted when the
mesh chooser is constructed, so an `ALTER SYSTEM` issued after sync has started does not take
effect. Run them immediately after initializing the Ditto object.

### Which peers get chosen

When a peer has more candidates than slots, it prefers connections that improve the mesh
rather than duplicate it — peers not already reachable in the local mesh, peers further
away in hop distance, peers on the other side of a topological split, peers with fewer
connections of their own, and connections on a transport it isn't already using for that
peer. The effect is that the mesh spreads toward its edges instead of clumping.

### Churn

Periodically — per transport, and only for connections that have already been up for a
while — a peer deliberately **drops an established connection** so a peer that has been
waiting can take the slot.

Churn is not a bug and not instability. It is the primary defence against **islanding**:
without it, the first N peers to connect would hold the caps forever and late arrivals
would never get in, splitting the mesh into permanently isolated clusters.

### When a peer is at capacity

By default a peer at its budget **rejects** new inbound connections, and the rejected peer
backs off exponentially before retrying — seconds at first, rising to a ceiling of several
minutes. Some deployments can instead be configured to evict an existing connection to make
room; an evicted peer gets a short flat cooldown before it may reconnect. Both the backoff
curve and the eviction policy are internal defaults, not a supported contract.

---

## 5. What this means for your application

**Do not treat direct connections as state.** Because of churn, caps, and multiplexer
switching, "peer A is connected to peer B" is a momentary fact. A dashboard, presence
indicator, or health check built on point-in-time edges will show constant flapping that
does not correspond to any real problem.

Build on **reachability over a window** instead:

- "Have I seen this peer in the presence graph in the last 30 seconds?" — good.
- "Am I currently directly connected to this peer?" — misleading.
- "Has my subscription converged?" — the question you usually actually mean; answer it with
  the SDK's sync-status / subscription APIs, not with connection state.

**Do not equate 'no direct connection' with 'no sync'.** Multihop routing means data flows
between peers that never see each other directly.

**Expect asymmetry.** One peer's view of the mesh is not the other's. Diagnosing a real
connection problem generally requires evidence from **both** peers.

---

## 6. Common topologies

### Star through Ditto Server

Every peer holds a WebSocket to the server; no peer-to-peer transports.

- Forced in browsers and Wasm builds.
- Chosen deliberately when P2P is disabled.
- **Cost:** every convergence is two WAN round trips, and there is no offline operation
  between co-located devices. Two tablets on the same table sync via the cloud.

### Every peer a gateway (the usual native default)

Every peer runs P2P transports **and** holds a WebSocket to the server.

- Local convergence happens over the mesh at local latency.
- The server provides store-and-forward for peers that are never co-located.
- There is no gateway flag — the role is implicit in having both configured.

### Pure small-peer mesh

P2P transports only, no server.

- Fully offline-capable, converges among whoever is present.
- Peers that are never co-located never exchange data — there is no store-and-forward.
- Perfectly valid; the right choice for air-gapped or intermittently-connected deployments.

---

## 7. Sync groups

A sync group scopes *automatic* connection formation. Peers with the same app ID but
different `global.syncGroup` values will not discover-and-connect to each other. Up to 2³²
groups; default is group `0`; a device is in exactly one.

Use it to stop devices that will never need each other's data from spending radio time on
discovery and connection — two restaurants, two vehicles, two floors.

**Remember:** it is an optimization, not a security control (manual connections cross group
boundaries), and changing it while sync is active forces an internal sync restart. Details
in [`transport-config.md`](transport-config.md#5-global--mesh-wide-settings).
