# Transports Reference

One section per transport: what it is, where it runs, how it discovers peers, what it
costs in bandwidth and battery, and how it fails. Read the section for the transport you
are choosing, debugging, or designing against.

Throughout: **small peer** = an SDK instance on a device. **Big Peer** / **Ditto Server** =
the cloud (or on-prem) peer reached over WebSocket.

---

## 1. Bluetooth Low Energy (BLE)

**What it is.** A short-range, low-power radio link that needs no network infrastructure —
no access point, no router, no internet. Every Ditto peer runs *both* BLE roles at once:
**central** (scanning for and connecting to others) and **peripheral** (advertising itself).
That symmetry is why two Ditto devices find each other with no designated server and no
pairing step.

**Where it runs.** iOS, macOS, Android, Linux (BlueZ), Windows. Not in browsers.

**Discovery.** Continuous advertise + scan. A peer advertises a Ditto service UUID; nearby
peers scanning see it and connect over GATT.

**Bandwidth — the number that drives your data model.** Effective throughput in Ditto's
mesh is roughly **20 KB/s**. The BLE radio's theoretical ceiling is higher (2 Mbps on the
Bluetooth 5 high-speed PHY, and Ditto uses Bluetooth 5 when both peers support it), but
GATT framing, connection intervals, and mesh overhead dominate in practice. Two peers
where one is Bluetooth 4.x negotiate down to 4.x rates.

Plan against 20 KB/s. Concretely:

| Payload | Time to replicate over BLE |
|---|---|
| 2 KB document | well under a second |
| 25 KB document | ~1 second |
| 256 KiB document (soft limit) | 10+ seconds, invisible to queries the whole time |
| 5 MiB document (hard limit) | minutes |

**Range.** Tens of metres indoors, materially further outdoors and on Bluetooth 5 hardware
(100+ m line-of-sight is achievable). Real range depends on firmware, antenna, body
blocking, and interference — treat published figures as approximations.

**Why it matters even when it's slow.** BLE is the **only peer-to-peer transport that
bridges iOS and Android**. It is also the transport that survives when Wi-Fi is switched
off, the AP is down, or the venue's network isolates clients. A mesh that keeps BLE enabled
degrades; a mesh that doesn't, disconnects.

**Connection shape.** A peer caps its *outgoing* BLE client connections (2 on Android, 3 on
Linux and iOS by default). Inbound connections are bounded by the OS GATT server rather
than by Ditto (roughly 7 on Android). One peripheral serving several centrals at once is
normal and useful — one phone can feed several tablets.

**Failure modes to recognize.**

- **Bluetooth off at the OS level, or permission not granted.** Config changes are inert;
  the SDK surfaces this through its transport-condition callback (`BLEDisabled`,
  `NoBLECentralPermission`, `NoBLEPeripheralPermission`).
- **Android GATT error 133.** A catch-all "connection failed" from the Android BLE stack,
  visible in `logcat` rather than Ditto's logs. Triggered by rapid reconnect cycles, OS BLE
  state contention, or firmware quirks. Mitigation: toggle Bluetooth off/on and relaunch;
  keep both peers foregrounded when testing.
- **iOS background.** In background the service UUID moves to the manufacturer-data
  overflow area and the device name is suppressed. Cross-platform discovery degrades.
- **Frequent disconnect/reconnect cycles.** Usually environmental — range, interference, or
  a backgrounded app — rather than a Ditto fault.

---

## 2. LAN (mDNS / multicast discovery + TCP)

**What it is.** Sync between peers attached to the same local network — a Wi-Fi access
point, or Ethernet. Traffic stays local; no internet needed. LAN is *composite*: discovery
and data movement are separate, independently configurable pieces.

1. **mDNS discovery** (DNS-SD) — the default way peers find each other. On by default when
   LAN is enabled.
2. **Multicast discovery** — an alternative discovery channel. Also on by default.
3. **TCP transport** — moves the bytes once a peer is known.

You may run any subset. Both discovery channels off is a valid configuration **if** you
feed the TCP transport addresses explicitly (see §6).

**Where it runs.** Every native SDK target. Not in browsers.

**Bandwidth.** The high-throughput option in most deployments — ordinary TCP over the local
network, tens to hundreds of Mbps. Document size is effectively a non-issue here; the
256 KiB soft limit exists for merge cost, not for LAN transfer time.

**Range.** Whatever the access point covers. Unlike the radio transports, LAN range is a
property of the infrastructure, not of the devices.

**Failure modes to recognize.**

- **Client isolation / AP isolation.** Guest and corporate Wi-Fi networks routinely block
  client-to-client traffic. Peers associate with the AP fine and never see each other.
  This is the single most common "LAN doesn't work" cause.
- **VPN.** Most VPN tunnels carry neither mDNS nor multicast. Startup looks healthy, no
  peer is ever discovered. Confirm by toggling the VPN off.
- **iOS Local Network permission.** Required for mDNS browse *and* LAN TCP connect. The
  first denial is sticky until the user re-enables it in Settings.
- **Missing `NSBonjourServices` in the iOS `Info.plist`.** iOS silently filters Ditto's
  mDNS records out. Nothing appears in logs.
- **Android multicast without a `MulticastLock`.** Multicast discovery starts and sees
  nothing.
- **Captive portals.** Local mDNS succeeds; outbound traffic is blocked. Affects Ditto
  Server reachability, not small-peer LAN sync.

---

## 3. AWDL (Apple Wireless Direct Link)

**What it is.** Apple's peer-to-peer Wi-Fi link — direct device-to-device Wi-Fi with no
access point. The same technology underneath AirDrop. Ditto layers a customized multiplexer
over it to raise frequency, speed, and efficiency of transfer.

**Where it runs.** iOS, macOS, tvOS. **Apple devices only** — an AWDL peer never connects
to an Android peer. On non-Apple platforms, enabling AWDL is a configuration error.

**Discovery.** Shares the LAN mDNS service type; distinguished by Bonjour's
"include AWDL / include P2P" browse flags rather than by a separate service name. That
sharing means **AWDL and LAN failures are often the same failure** — if mDNS is broken,
both go dark together.

**Bandwidth.** Wi-Fi-class throughput, far above BLE, and available with no infrastructure
at all. This is what makes an all-iPad deployment fast in a venue with no usable Wi-Fi.

**Failure modes.** iOS Local Network permission (prompted on first use, sticky if denied);
missing `NSBonjourServices` entries; peers backgrounded.

---

## 4. Wi-Fi Aware (NAN)

**What it is.** Android's peer-to-peer Wi-Fi standard — the Android counterpart to AWDL.
Direct device-to-device Wi-Fi, no access point.

**Where it runs.** **Android only, API 29 (Android 10) and above**, and only on hardware
that reports the Wi-Fi Aware feature. Many low-end and older devices do not, regardless of
OS version. Below API 29 the SDK refuses to start it and says so.

**Discovery.** Each peer publishes a Wi-Fi Aware service and subscribes to others
simultaneously.

**Bandwidth.** Wi-Fi-class, like AWDL. Also cross-platform-*in*compatible with AWDL:
Android ↔ Android only.

**Failure modes.**

- **Wi-Fi radio off.** Wi-Fi Aware rides the Wi-Fi radio; turning Wi-Fi off kills it even
  though no AP is involved.
- **`NEARBY_WIFI_DEVICES` permission** on Android 13+ (API 33+). Without it the platform
  silently filters peers out.
- **Location services.** Android ties Wi-Fi Aware availability to the location-services
  system toggle plus a location-class permission (`ACCESS_FINE_LOCATION` on API 29–32,
  `NEARBY_WIFI_DEVICES` with `neverForLocation` on API 33+). Location off ⇒ Android
  reports Wi-Fi Aware unavailable and discovery stays silent.
- **Background termination.** By default the Wi-Fi Aware client stops searching when the
  app goes to background. Apps that must keep meshing in background need to change that
  behavior explicitly.

---

## 5. WebSocket (Ditto Server / Big Peer)

**What it is.** A client-initiated WebSocket Secure (`wss://`) connection to Ditto Server —
cloud or on-prem. Bidirectional, real-time, and the path for cloud store-and-forward and
backend integrations such as MongoDB Atlas.

**Where it runs.** Every SDK target, including browsers and Wasm — where it is the **only**
available transport.

**Role.** Client only. Peers connect *to* the server; the server does not initiate.

**Bandwidth.** The highest-capacity link in most deployments, but the only one that depends
on internet reachability. Latency is WAN latency, so a pure star-through-the-cloud topology
means every convergence costs a round trip to the server and offers no offline operation.

**Why you usually want it *alongside* P2P, not instead of it.** With both configured, every
peer is implicitly a gateway: peers converge locally over the mesh *and* the server provides
store-and-forward for peers that are never co-located. There is no "gateway" flag — the role
comes for free from having both configured. Removing all WebSocket URLs at runtime stops
server sync immediately without touching P2P.

**Failure modes.** Malformed URL; auth webhook failure; captive portal or firewall blocking
the outbound connection; expired credentials. Connection attempts retry on
`connect.retryInterval` (default 5 seconds).

---

## 6. Explicit TCP: `connect` and `listen`

Not a discovery-based transport — a way to point Ditto at a peer whose address you already
know, or to accept connections at a known address. Use it when mDNS/multicast discovery is
unavailable or undesirable: routed networks, hardened enterprise networks, fixed
infrastructure peers, containers.

**Listening.** Enable the TCP listener and bind an interface and port (default `[::]` and
`4040`). Bind `0.0.0.0` or `[::]` for all interfaces — do not pass the string `"localhost"`.

**Connecting.** Two routes:

- `connect.tcpServers` in the transport config — a set of addresses to attempt.
- The `TRANSPORTS_DISCOVERED_PEERS` system parameter, set with DQL (SDK 4.12.0+), which
  takes a list of peers with an `address` and a `type`:
  - `candidate` — attempt the connection; may persist if the entry is later removed.
  - `force` — always attempt; the connection drops immediately when the entry is removed.

  Addresses accept IPv4, IPv6, or a domain name with the `tcp://` scheme.

**Replacing mDNS discovery entirely.** Where mDNS is unusable, the supported pattern is:
disable LAN, enable TCP listening, read this peer's `discovery_hint` from the
`system:transports_info` virtual collection, distribute IP + port + hint over your own
channel (your backend, a QR code, a config service), and have peers write each other into
`TRANSPORTS_DISCOVERED_PEERS`. The `discovery_hint` is an optional opaque identifier that
changes on every `startSync()` and carries no long-term tracking data.

An HTTP listener also exists for specialized deployments (including acting as an identity
provider in fully offline environments). It is not part of ordinary sync configuration; see
the deployment documentation before enabling it — an incorrectly configured listener can be
insecure.

---

## Choosing a mix

Work down this list; the first row that matches your deployment is your baseline.

| Situation | Enable |
|---|---|
| Browser / Wasm | WebSocket only (anything else is rejected) |
| Mixed iOS + Android fleet, unreliable or absent Wi-Fi | BLE **and** LAN, plus AWDL and Wi-Fi Aware for the same-platform fast paths, plus WebSocket if you have a server |
| Single-platform fleet, no infrastructure | The matching P2P Wi-Fi transport (AWDL or Wi-Fi Aware) + BLE as fallback |
| Reliable venue Wi-Fi, devices always on it | LAN + WebSocket; keep BLE on for AP outages |
| Fixed infrastructure, no mDNS | TCP listen + explicit peers + WebSocket |
| Air-gapped, no server | All available P2P transports, no WebSocket |

**Default to leaving transports on.** The multiplexer picks the best available link per
peer and switches as conditions change; an enabled-but-unused transport costs little, while
a disabled one removes a path through the mesh permanently. Disable a transport only for a
measured reason.
