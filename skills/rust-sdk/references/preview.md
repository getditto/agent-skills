# Preview and platform-specific APIs — Ditto Rust SDK

## Contents

- [CAP-20 Preview and platform-specific APIs](#cap-20-preview-and-platform-specific-apis)
- [Data Streams](#data-streams)
- [Multicast transport](#multicast-transport)
- [Platform-specific notes](#platform-specific-notes)

## CAP-20 Preview and platform-specific APIs

Support is **preview**. Both features below are opt-in and can change without a major
version bump.

## Data Streams

- **Opt-in:** the Cargo feature `preview-datastreams`:

  ```toml
  [dependencies]
  dittolive-ditto = { version = "=5.2.0", features = ["preview-datastreams"] }
  ```

- **Since:** the feature exists in 5.0.4, 5.1.0 and 5.2.0 (crate manifests); this skill
  did not execute it.
- **Stability:** the `preview` module documents that preview APIs carry "no semver
  guarantees" (`src/preview/mod.rs`, 5.2.0 crate).
- **Entry point:** `ditto.datastreams()` returns a
  `dittolive_ditto::preview::datastreams::Endpoint`. Acceptors bind a topic
  (`bind_topic(..)…finish_with(..)`); connectors target a peer key from the presence
  graph (`connect(peer, topic)…finish_async().await`). **Dropping the `Acceptor` unbinds
  the topic**, so bind it to a named variable, never `let _ =`.
- The crate's own examples are the best Rust reference: `examples/datastreams.rs`,
  `datastreams_ping.rs`, `datastreams_pong.rs` and `datastreams_with_arguments.rs` in the
  published `dittolive-ditto` crate (`cargo run --example datastreams --features
  preview-datastreams` from a checkout of the crate source).
- Semantics (reliability modes, topics, delivery guarantees, NGN requirement) belong to
  the `data-streams` skill, otherwise <https://docs.ditto.live/sdk/latest/sync/data-streams>.
  The hosted 5.2.0 API reference is built without this feature, so these items do not
  appear there; run `cargo doc --features preview-datastreams --open`.

## Multicast transport

`TransportConfig.peer_to_peer.multicast_beta: MulticastBetaConfig { enabled,
group_address ("224.1.2.3"), port (6003), interface }`, added in 5.1.0. It is a private
beta: enable it only in coordination with Ditto support. `enable_all_peer_to_peer()`
leaves it off. On 5.0.x the field does not exist, so an exhaustive `PeerToPeer { .. }`
literal written for 5.0.x fails to compile on 5.1.0. Use field assignment.

## Platform-specific notes

- **Targets:** prebuilt libraries exist only for Linux (x86_64, aarch64) and macOS
  aarch64 (plus macOS x86_64 on 4.14.x) — [setup.md](setup.md#supported-targets).
- **AWDL and Wi-Fi Aware** fields exist on every platform but only do something on Apple
  and Android radios respectively; on Linux, LAN, TCP, WebSocket and BLE (with BlueZ) are
  the relevant transports.
- **No encryption at rest:** the Rust SDK 5.2.0 has no public way to set an encryption
  key (`DittoConfig`'s hidden `experimental.passphrase` is rejected when set). Use
  full-disk or volume encryption on the host.
