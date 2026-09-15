# Platform Requirements and Diagnosis

Transports depend on OS permissions, entitlements, manifest declarations, and hardware
support. **Configuration cannot override any of them.** When a transport is enabled in
config but produces no connections, this file is where to look before suspecting Ditto.

---

## 1. The first question: config or platform?

Every SDK exposes a **transport-condition** callback that reports platform-level transport
states. The callback receives a **source and a condition**, not a condition alone.

The full condition set is: `Unknown`, `Ok` (no known problems — the healthy state),
`GenericFailure`, `AppInBackground`, `MdnsFailure`, `TcpListenFailure`,
`NoBleCentralPermission`, `NoBlePeripheralPermission`, `CannotEstablishConnection`,
`BleDisabled`, `NoBleHardware`, `WifiDisabled`, `TemporarilyUnavailable`.

**The JS SDK renames several of these**, so do not copy identifiers across languages:
`Ok`→`OK`, `MdnsFailure`→`MDNSFailure`, `TcpListenFailure`→`TCPListenFailure`,
`NoBleHardware`→`NoBLEHardware`, `WifiDisabled`→`WiFiDisabled`, `BleDisabled`→`BLEDisabled`,
`NoBleCentralPermission`→`NoBLECentralPermission`,
`NoBlePeripheralPermission`→`NoBLEPeripheralPermission`. The source enum is renamed too
(`Bluetooth`→`BLE`, `Tcp`→`TCP`, `Mdns`→`MDNS`, `WifiAware`→`WiFiAware`).

Wire it up early; it is the fastest way to distinguish:

- *"I disabled this transport"* — a configuration problem, fix the config.
- *"The platform will not give me this transport"* — a permission, entitlement, hardware,
  or OS-toggle problem, and no amount of config will fix it.

Availability of the callback varies by SDK; check the SDK skill for your language. Where it
isn't available, fall back on the SDK's logs.

---

## 2. iOS / macOS

| Requirement | Applies to | Symptom if missing |
|---|---|---|
| Bluetooth usage description in `Info.plist` + user grant | BLE | BLE never starts; transport condition reports missing central/peripheral permission. |
| **Local Network permission** | LAN (mDNS + TCP), AWDL | Prompted on first use. **The first denial is sticky** — the user must re-enable it in Settings → Privacy → Local Network. Discovery silently returns nothing. |
| **`NSBonjourServices` in `Info.plist`** | LAN, AWDL | iOS silently filters Ditto's mDNS records out. Nothing appears in logs — this is the quietest failure on the platform. Both the LAN and AWDL service entries must be present for AWDL to be visible. |
| Background modes | BLE, AWDL | In background, iOS moves the BLE service UUID to the manufacturer-data overflow area and suppresses the device name; cross-platform discovery degrades. AWDL and mDNS activity is curtailed. |

AWDL runs on Apple platforms only (iOS, macOS, tvOS). Enabling it elsewhere throws on the
JS and Go SDKs; most other SDKs accept it silently and it simply never starts. See
[`transport-config.md` §2](transport-config.md#2-peertopeer--discovery-based-transports).

---

## 3. Android

| Requirement | Applies to | Symptom if missing |
|---|---|---|
| `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, and `BLUETOOTH_CONNECT` runtime permissions (API 31+) | BLE | Ditto scans, connects, **and advertises** — all three are needed. A missing one surfaces through the transport-condition callback. |
| Location permission (older API levels) | BLE scanning | Scanning returns nothing on API levels that tie BLE scan results to location. |
| `CHANGE_WIFI_MULTICAST_STATE` **and** an acquired `MulticastLock` | LAN multicast discovery | Multicast discovery *starts* and never sees a peer. The startup log line still appears — absence of peers is the only signal. |
| `NEARBY_WIFI_DEVICES` (API 33+), with `neverForLocation` asserted | Wi-Fi Aware | Platform silently filters Wi-Fi Aware peers out. |
| `ACCESS_FINE_LOCATION` (API 29–32) **and** location services *switched on* | Wi-Fi Aware | Android reports Wi-Fi Aware unavailable; discovery stays silent. Note this is the system location **toggle**, not just the permission. |
| Android 10 (API 29) or newer **and** hardware Wi-Fi Aware support | Wi-Fi Aware | The SDK logs an error and continues without it — `startSync()` still succeeds, so watch the log, not the return value. Many low-end and older devices lack the hardware feature regardless of OS version. |
| Wi-Fi radio switched on | Wi-Fi Aware | Wi-Fi Aware rides the Wi-Fi radio even though no access point is involved. Wi-Fi off ⇒ transport offline. |

**Wi-Fi Aware manifest permissions.** The rows above cover the Android-version-gated *runtime*
requirements; Wi-Fi Aware also needs its baseline manifest permission set, which varies by
Ditto SDK language and version. Check the SDK-specific required-permissions list for your SDK
rather than this table for the complete manifest.

**Wi-Fi Aware and background.** By default the Wi-Fi Aware client stops searching when the
app goes to background. Apps that must keep meshing in background have to change that
behavior explicitly — check the SDK skill for the setting.

**Android GATT 133.** A catch-all BLE failure code from the Android stack, visible in
`logcat` rather than Ditto's logs. Triggered by rapid reconnect cycles, OS BLE state
contention, or firmware quirks. First mitigations: toggle Bluetooth off and on, relaunch
the app, and keep both peers foregrounded while testing.

Wi-Fi Aware runs on Android only. As with AWDL, whether enabling it elsewhere throws
depends on the SDK.

---

## 4. Linux

- **BLE** runs via BlueZ. The Bluetooth service must be running and the adapter powered.
- **LAN** works with the system mDNS responder or Ditto's internal one.
- Android uses a lower default outgoing BLE budget than Linux, iOS and tvOS.

---

## 5. Windows

- **BLE** runs on the WinRT Bluetooth stack.
- The Windows BLE backend does **not** include Ditto's announce string in advertisements,
  which makes peer disambiguation harder when more than one Ditto peer is in range.

---

## 6. Browsers and Wasm

**WebSocket only.** Enabling any peer-to-peer transport, a TCP server in `connect`, or a
TCP/HTTP listener in a Wasm build produces a validation error naming the offending
transports — it is not silently ignored.

Consequences worth designing around: no offline peer-to-peer sync between two browser
tabs on the same machine; every convergence costs a round trip to Ditto Server; a browser
peer cannot act as a relay for nearby devices.

---

## 7. Network environment (not a device setting, but the same class of problem)

These block transports regardless of any permission being correctly granted.

| Condition | Blocks | How to confirm |
|---|---|---|
| **AP / client isolation** on guest and corporate Wi-Fi | LAN | Peers associate with the AP but never see each other. Test with a LAN service that goes over the AP — an HTTP/TCP/SMB service between the two devices. (Don't use AirDrop as the test: it travels over Apple's peer-to-peer Wi-Fi rather than the AP LAN path, so it can succeed while client isolation remains.) The most common "LAN doesn't work" cause. |
| **VPN** | LAN (mDNS and multicast) | Most tunnels carry neither. Startup looks healthy, no peer is ever discovered. Toggle the VPN off to confirm. |
| **Captive portal** | WebSocket / Ditto Server | Local mDNS still succeeds; outbound traffic is intercepted. |
| **Firewall / egress filtering** | WebSocket | `wss://` outbound blocked. |
| **Routed networks** (peers on different subnets) | LAN discovery | mDNS is link-local. Use explicit TCP peers instead — see [`transports.md` §6](transports.md#6-explicit-tcp-connect-and-listen). |

---

## 8. Diagnosis order

When a transport produces no connections, work down this list. Stop at the first failure.

1. **Is it enabled in the effective config?** Remember that a self-constructed
   `TransportConfig` starts all-disabled. Log the config you actually applied.
2. **Does the platform support it?** AWDL is Apple-only; Wi-Fi Aware is Android 10+ with
   hardware support; browsers are WebSocket-only.
3. **Is the radio / OS toggle on?** Bluetooth on; Wi-Fi on (needed for Wi-Fi Aware even
   without an AP); location services on for Wi-Fi Aware on Android.
4. **Are permissions granted?** Check the transport-condition callback, not just the
   manifest — a declared permission is not a granted one.
5. **Are manifest / plist declarations present?** `NSBonjourServices` on Apple is the
   silent killer.
6. **Is the network environment permitting it?** AP isolation, VPN, captive portal,
   subnet routing.
7. **Is the peer within range and foregrounded?** BLE and P2P Wi-Fi are proximity
   transports, and backgrounded apps advertise less.
8. **Is the peer's identity valid?** If the peer's certificate is missing, expired or
   otherwise invalid, Ditto **silently zeroes every peer-to-peer transport, both listeners,
   and `connect.tcpServers`** regardless of what your config says — and an invalid web
   identity likewise empties `websocketUrls`. This is the classic "everything is configured
   and nothing connects" case, and no amount of transport debugging will find it. Check
   authentication state before concluding the transport layer is at fault.
9. **Do both peers agree?** Collect evidence from **both** sides. Transport problems are
   frequently asymmetric, and one peer's logs are only half the picture.
