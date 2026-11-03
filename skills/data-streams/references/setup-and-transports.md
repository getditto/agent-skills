# Setup and transports

Sources: <https://docs.ditto.live/sdk/latest/sync/data-streams>; the Kotlin 5.2.0 and
Swift 5.2.0 declarations; **executed** items come from the two-peer fixtures.

## Enable NGN before the instance exists

Data Streams run over Ditto's **next-generation networking (NGN)**, which is off by default
and must be enabled **before** the `Ditto` instance is constructed; changing it afterwards
has no effect (<https://docs.ditto.live/sdk/latest/sync/data-streams>). Two switches:

| Switch | Meaning | Recommended in the preview |
|---|---|---|
| `network_enable_ngn` / `DITTO_NETWORK_ENABLE_NGN` | turns on the NGN transport Data Streams use; **required** | `true` |
| `replication_over_ngn` / `DITTO_REPLICATION_OVER_NGN` | moves document and attachment sync onto NGN too | `false`: keep document sync on the stable transports |

Two ways to set them:

1. **Environment variables, all supported versions.** Android: `Os.setenv(name, value, true)`
   in `Application.onCreate()` before `DittoFactory.create`. JVM: the process environment
   (the fixture sets them on the Gradle test task, executed). Apple: `setenv` before
   `Ditto.open`.
2. **`systemParameters` in the config, 5.2.0 and later.** Kotlin `DittoConfig(…,
   systemParameters = mapOf("network_enable_ngn" to true, "replication_over_ngn" to false))`;
   Swift `DittoConfig(…, systemParameters: ["network_enable_ngn": .bool(true),
   "replication_over_ngn": .bool(false)])` (executed in the Swift fixture).

`replication_over_ngn` must be **the same on every peer that replicates documents** with
each other; the reference apps that set it `true` do so on every peer. Mixed settings
split the mesh for document sync even though streams still work.

## Transports

- **No TCP listener is required.** Ditto's peer-to-peer transports are on by default, so for
  Data Streams alone `sync.start()` is enough. Enable `listen.tcp` only for legacy
  document sync to a fixed address, and know that a listener exposes the app on the network
  (<https://docs.ditto.live/sdk/latest/sync/data-streams>).
- **Modify the current transport config; never construct a new one.** A fresh config has
  every transport disabled (<https://docs.ditto.live/sdk/latest/sync/data-streams>). Both SDKs
  expose an update-in-place call that hands you a copy of the live config.
- Streams follow whatever link the mesh has: LAN, Wi-Fi Aware, Bluetooth LE, or an explicit
  TCP connection. The fixtures use a TCP loopback listener plus `connect.tcpServers` with
  LAN discovery off (executed); the push-to-talk app runs Wi-Fi Aware with the TCP listener
  on so multihop presence keeps working. Radio choice and permissions are the
  `ditto-mesh-networking` skill's territory.

## Discovery and sync

- **Start sync before relying on presence.** The sender finds the receiver's **peer key**
  (`peerKeyString`) in the presence graph; the fixtures wait until each side lists the other
  in `remotePeers` before connecting (executed).
- Presence proves reachability, **not** that the topic is bound. Early connects fail with
  `Rejected(HandshakeTimedOut)`; retry with bounded backoff.
- Do not call `connect` **inside** a presence callback. Copy the peer key out and connect
  from your own task or coroutine (<https://docs.ditto.live/sdk/latest/sync/data-streams>).
- Reference-app pattern for two peers that both bind and both see each other: pick the
  role by **ordering the peer keys** (the lower key connects, the higher key only accepts),
  so exactly one stream exists per topic and pair.

## Platform notes

- **Android:** API 24+, the SDK's normal Bluetooth/Wi-Fi permissions; Wi-Fi Aware needs
  hardware support and API 29+. Multicast transport (separate beta) has its own
  permissions from 5.2.0 (`requiredMulticastPermissions`). Details:
  `kotlin-sdk/references/transports.md`.
- **Apple (5.2.0 only):** `@_spi(PreviewDataStreams) import DittoSwift`. With NGN enabled,
  `sync.start()` synchronously spawns the UDP transport and needs more stack than a Swift
  cooperative thread offers in debug builds; the Ditto reference app and the fixture call
  it on a dedicated 64 MB-stack thread (executed). Details: `swift-sdk/references/data-streams.md`.
- **JVM:** the same `com.ditto:ditto-kotlin` API with the `ditto-binaries` classifier;
  environment variables are the way to enable NGN below 5.2.0.
