---
name: mesh-networking
description: Use when working with Ditto's peer-to-peer mesh — choosing or configuring transports (Bluetooth LE, LAN/mDNS, AWDL, Wi-Fi Aware, WebSocket to Ditto Server, explicit TCP), understanding peer discovery and multihop routing, deciding what changes when transport config is updated at runtime, or sizing documents and attachments for a slow transport like BLE. Conceptual and config-model guidance; per-language API syntax lives in that language's SDK skill, query syntax in the DQL skill.
---

# Ditto Mesh Networking and Transports

Ditto peers sync by forming a **mesh network** over whatever network transports each
device has available — no server required. This skill explains how that mesh forms,
what each transport can and cannot do, how the transport configuration works, what
changes when you update it while sync is running, and — the part teams most often get
wrong — **how your transport mix should change the way you model your data.**

## When to use this skill

Use it for:

- "Which transports should I enable?" / "Why aren't my iOS and Android devices connecting?"
- "What happens to sync if I turn off Bluetooth in my transport config at runtime?"
- "How many peers will each device connect to?"
- "Why is sync slow over Bluetooth?" / "How big can my documents be?"
- Understanding discovery, the presence graph, multihop routing, and sync groups.

Do **not** use it for:

- **Exact API syntax** — property names, builder shapes, and permission calls differ per
  SDK. Route to the language-specific Ditto SDK skill if one is installed; otherwise send
  the user to <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>,
  which carries the per-language snippets. This skill deliberately keeps code to a minimum
  and describes the *configuration model* that every SDK exposes.
- **Query syntax** — route to the DQL skill (`write-dql`). The exception: this skill does
  cover the handful of `ALTER SYSTEM` / `system:` statements that configure transports,
  because those are language-agnostic.

## Version awareness

Most of this skill is version-independent, but a few claims are not — notably whether the
document hard limit **rejects a write** or only logs, and the availability of
`TRANSPORTS_DISCOVERED_PEERS` (4.12.0+). Where a question turns on one of those, confirm the
user's SDK line and check [`references/versions.md`](references/versions.md). Note that
Ditto's public docs currently lag the code on the hard-limit behavior.

## The one-paragraph model

Every Ditto peer runs several **transports** at once. Each transport independently
**discovers** nearby peers and opens **physical connections** to them. When two peers are
reachable over more than one transport at the same time, Ditto's **multiplexer** binds all
of those physical connections into a single **virtual connection** for that peer and picks
the best one to actively carry traffic — switching without duplicating data as conditions
change. Ditto calls the resulting multi-transport fabric the **rainbow connection**. Peers
that are not directly connected still sync: the **presence graph** lets updates travel
multiple hops through intermediate peers. Sync is a property of the mesh, not of any one
link.

## The transports at a glance

| Transport | Reaches | Cross-platform? | Typical role |
|---|---|---|---|
| **Bluetooth LE** | Nearby devices, no infrastructure | **Yes** — the only P2P radio that bridges iOS ↔ Android | Low-bandwidth fallback; keeps the mesh alive when Wi-Fi is gone |
| **LAN** (mDNS/multicast discovery + TCP) | Devices on the same Wi-Fi AP or Ethernet | Yes | High-bandwidth workhorse when infrastructure exists |
| **AWDL** (Apple Wireless Direct Link) | Nearby Apple devices, no AP needed | **No** — Apple ↔ Apple only | Fast infrastructure-free P2P between iOS/macOS/tvOS |
| **Wi-Fi Aware** | Nearby Android devices, no AP needed | **No** — Android ↔ Android only (API 29+) | Fast infrastructure-free P2P between Android devices |
| **WebSocket** | Ditto Server (the "Big Peer"), over the internet | Yes (only transport in browsers/Wasm) | Cloud sync, store-and-forward, backend integrations |
| **TCP connect/listen** | A peer at a known address/port | Yes | Fixed infrastructure, servers, mDNS-hostile networks |

Key consequences:

1. **A mixed iOS/Android fleet with no Wi-Fi has only Bluetooth LE.** AWDL and Wi-Fi Aware
   never talk to each other. Design for BLE bandwidth in that case.
2. **Browsers and Wasm builds are WebSocket-only.** Enabling any P2P transport in a Wasm
   build is a validation error. **On native SDKs the opposite is true** — an unsupported
   transport (AWDL on Android, Wi-Fi Aware on iOS) is accepted silently and simply never
   starts. Do not rely on config validation to catch a platform mismatch.
3. **Having no Ditto Server is fine.** A pure small-peer mesh converges perfectly well;
   it just has no cloud store-and-forward for peers that are never co-located.

Full per-transport detail — discovery mechanism, platform support, permissions, failure
modes — is in [`references/transports.md`](references/transports.md).

## The configuration model

Every SDK exposes the same core four-part transport configuration object:

```
transportConfig
├── peerToPeer   # bluetoothLE, lan (+ mdns/multicast sub-toggles), awdl, wifiAware
├── connect      # websocketUrls, tcpServers, retryInterval  → outbound to known addresses
├── listen       # tcp, http  → accept inbound connections at a known address
└── global       # syncGroup, routingHint  → mesh-wide behavior, not tied to one transport
```

Some SDKs expose extra platform- or preview-specific sections beyond these four.

**The trap that bites everyone:** a `TransportConfig` you construct yourself starts with
**every transport disabled**. The SDK's *default* config enables the platform-appropriate
P2P transports, but the moment you supply your own object you own all of it — you must
re-enable each transport you want. A config where you only set `bluetoothLE.enabled = true`
silently disables LAN, AWDL, and Wi-Fi Aware.

See [`references/transport-config.md`](references/transport-config.md) for every field,
its default, and what it actually controls.

## Updating the transport configuration at runtime

This is the part with the most surprising behavior, so it gets its own rules.

**Updates are applied by diffing the old config against the new one, transport by
transport.** You do not need to stop and restart sync.

| Change | Effect |
|---|---|
| Transport `false` → `true` | That transport starts. Discovery begins; connections form over the next seconds. |
| Transport `true` → `false` | That transport stops and its connections drop immediately. |
| Transport unchanged | **Untouched.** Its live connections are not disturbed. |
| Add a WebSocket URL | Connection attempts begin, retried on `connect.retryInterval` (default 5s — a mesh-wide per-peer cooldown, not WebSocket-specific). |
| Remove all WebSocket URLs | Ditto Server sync stops immediately. |
| Change `global.syncGroup` **while sync is active** | Sync is torn down and restarted internally. **Stop sync, change the group, start sync** — do not change it live. |

Because updates are diffed, **read-modify-write is the safe pattern**: fetch the current
config, change only the field you care about, apply it. Constructing a fresh config to
"just turn on Bluetooth" is how teams accidentally take LAN down in production.

**What an update does *not* do:** it never loses data. Dropping a transport drops
connections, not writes. Local writes continue while a peer is fully disconnected, and
CRDT merge reconciles everything when any path back into the mesh reopens. An interrupted
document transfer resumes rather than corrupting; the document simply stays absent from
query results on the receiving peer until it has arrived in full.

**What an update cannot fix:** a transport that the platform refuses. If Bluetooth is off
at the OS level, or the app lacks the runtime permission, enabling it in config changes
nothing. Observe the SDK's transport-condition callback to see those states — see
[`references/platform-requirements.md`](references/platform-requirements.md).

## How transports shape data modeling

**This is the highest-value idea in this skill.** Ditto's data-modeling advice is not
transport-neutral. The same schema that is fine on LAN can be unusable on Bluetooth LE.

The mechanism: Bluetooth LE delivers roughly **20 KB/s** of effective throughput, against
tens of megabits per second for LAN or peer-to-peer Wi-Fi — three orders of magnitude. And
two costs scale with **document size**, not with edit size:

- **Merge cost.** Reconciling a document *costs* the whole document: Ditto clones, merges,
  re-serializes and re-indexes all of it on every update, even a one-field change. A
  one-byte edit to a 5 MiB document pays 5 MiB of work on every peer that receives it.
- **Arrival is all-or-nothing.** A document is invisible to queries on the receiving peer
  until every part of it has arrived. At 20 KB/s a 250 KiB document takes 10+ seconds
  before it appears at all; a 5 MiB document takes minutes.

So the rule the user's intuition suggests is exactly right, and it is a *transport-driven*
rule:

> **If Bluetooth LE is a transport you actually depend on, prefer many small documents over
> few large ones.** Ten 25 KB documents each become visible as they land; one 250 KB
> document appears only after the whole transfer completes. On LAN the difference is
> imperceptible; on BLE it is the difference between a responsive app and a frozen one.

The corollary matters too: on a LAN-only or cloud-only deployment, Ditto's normal advice —
**embed related data in one document** so it writes atomically and merges with add-wins map
semantics — stands unchanged. Splitting documents to chase BLE performance you don't need
buys you cross-document consistency problems for nothing.

Size thresholds to design against (defaults; identical on every peer in the mesh):

- **256 KiB** — soft limit. Write succeeds, logs a warning. Treat as your real ceiling on BLE.
- **5 MiB** — hard limit. On current SDKs the **local write is rejected with an error**;
  older builds logged an error and accepted it. The limit gates *local writes only* — an
  oversized document that already exists elsewhere in the mesh still replicates in.

Binary payloads do not belong in documents at all. The `ATTACHMENT` type stores blobs
out-of-band, excludes them from document size, and — critically for BLE — **peers fetch
attachments explicitly rather than receiving them automatically**, so a large image never
blocks the document updates behind it.

Fuller treatment, including sync-group partitioning and subscription scoping as bandwidth
tools: [`best-practices.md`](best-practices.md).

## How many peers will each device connect to?

Ditto deliberately does **not** connect every peer to every other peer — that would not
scale and would saturate the radios. Each transport has its own connection budget, sized by
how much power that transport costs: **LAN is the most generous** (the radio is already
associated with the access point, so extra connections are near-free), **peer-to-peer Wi-Fi
is tighter** (it drives the radio directly, with no infrastructure to offload to), and
**BLE is the tightest** (the OS Bluetooth controller has a small total connection budget
that every BLE app on the device shares). The mesh chooser then picks *which* peers to
connect to, favoring peers that are far away in the graph, poorly connected, or not
otherwise reachable. It also performs periodic **churn**:
deliberately dropping a long-established connection so a peer that has been waiting can
take the slot. Churn is what prevents the mesh from fragmenting into isolated islands.

Two operational consequences:

- **The set of direct connections is not stable, by design.** Anything that treats "peer A
  is connected to peer B" as a steady-state fact will see spurious connect/disconnect
  churn. Observe *reachability over a window*, not point-in-time edges.
- **Not being directly connected is not a sync failure.** Multihop routing carries updates
  through intermediate peers.

Caps, churn intervals, and the two publicly supported tuning parameters are in
[`references/mesh-formation.md`](references/mesh-formation.md).

## Anti-patterns

1. **Building a fresh `TransportConfig` to change one setting.** It starts all-disabled;
   you just turned off everything you didn't re-enable. Read-modify-write instead.
2. **Assuming AWDL or Wi-Fi Aware bridges iOS and Android.** They don't. Cross-platform
   infrastructure-free sync is Bluetooth LE, full stop.
3. **Designing large documents and then blaming Bluetooth.** 20 KB/s is a physical
   constraint, not a bug. Model for it or don't depend on BLE.
4. **Putting images or binary blobs in document fields.** Use `ATTACHMENT`; it's fetched on
   demand and doesn't count against document size.
5. **Changing `syncGroup` while sync is running.** Forces an internal restart. Stop sync first.
6. **Treating sync groups as a security boundary.** They are a connection-scoping
   optimization. A manually configured connection crosses them freely. Use Ditto's
   permissions system for access control.
7. **Disabling transports "to save battery" without measuring.** Removing a transport
   removes paths through the mesh; the peer may end up relaying everything over the slowest
   remaining link, which costs *more* radio time.
8. **Expecting a WebSocket URL alone to give peer-to-peer sync.** WebSocket reaches Ditto
   Server only. Peers on the same table sync directly only if a P2P transport is enabled.

## Where to look

| If you're doing this... | Read |
|---|---|
| **Debugging "no sync" / "peers won't connect"** — start here | [`references/platform-requirements.md`](references/platform-requirements.md#8-diagnosis-order), then [`references/mesh-formation.md`](references/mesh-formation.md#1-the-six-stages-of-a-sync) |
| Localizing *which* stage is failing (discovery vs connection vs replication) | [`references/mesh-formation.md`](references/mesh-formation.md#1-the-six-stages-of-a-sync) |
| Choosing transports; per-transport range, bandwidth, platform support, failure modes | [`references/transports.md`](references/transports.md) |
| Looking up a config field, its default, or what a runtime change does | [`references/transport-config.md`](references/transport-config.md) |
| Understanding discovery, presence graph, multihop, connection caps, churn, sync groups | [`references/mesh-formation.md`](references/mesh-formation.md) |
| Permissions, entitlements, manifest entries, OS-level prerequisites per platform | [`references/platform-requirements.md`](references/platform-requirements.md) |
| Which SDK version / which SDK a claim applies to | [`references/versions.md`](references/versions.md) |
| Sizing documents, attachments, and subscriptions for your transport mix | [`best-practices.md`](best-practices.md) |
| Matching a real deployment to a transport configuration | [`examples/deployment-scenarios.md`](examples/deployment-scenarios.md) |
| Writing the actual configuration code | The Ditto SDK skill for your language, else <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations> |
| Transport `ALTER SYSTEM` / `system:` statements | [`references/transport-config.md`](references/transport-config.md#7-transport-settings-that-live-in-dql-not-in-the-config-object) |
| Writing queries or subscriptions | The `write-dql` skill (ships in the separate `ditto-dql` plugin) |
