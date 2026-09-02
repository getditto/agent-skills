# Version Matrix

Version-gated claims in this skill, in one place. Anything not listed here is
version-independent as far as this skill is concerned.

**Confirm the user's SDK line before answering a version-sensitive question.** This skill
targets the same lines as the rest of this repo: **Ditto SDK 4.14.x (LTS), 5.0.x, 5.1.x**.

## Feature and behavior gates

| Claim | Applies to | Notes |
|---|---|---|
| `TRANSPORTS_DISCOVERED_PEERS` system parameter, and the `discovery_hint` / `system:transports_info` pattern for replacing mDNS | **SDK 4.12.0+** | Publicly documented as "supported in SDK version 4.12.0 and later". |
| `mesh_chooser_max_active_ble_clients` replaces `DittoBluetoothLeConfig.maxOutgoing` | Java/Kotlin | `maxOutgoing` has been **removed** from current Kotlin/Java SDKs. The field survives in core but is never read. |
| **Document hard limit rejects the local write** | All supported lines | Public docs still describe the write as succeeding with only an `error` log; the code rejects it. Follow the code. The limit gates *local writes only* — oversized documents already in the mesh replicate in regardless. |
| Wi-Fi Aware transport | **Android API 29+** (Android 10), hardware support required | Below API 29 the SDK logs an error and continues; `startSync()` still succeeds. |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` runtime permissions | **Android API 31+** | Below that, BLE scanning is gated on location permission instead. |
| `NEARBY_WIFI_DEVICES` permission (with `neverForLocation`) | **Android API 33+** | On API 29–32 use `ACCESS_FINE_LOCATION`, and the system location toggle must be on. |
| Bluetooth 5 2M PHY requested | Android only, adapter-dependent | Not implemented in the Apple, BlueZ or WinRT BLE backends. It is a *preference* the controller may decline. |
| **BLE throughput ~20 KB/s vs ~4 KB/s** | **Android 10+ vs below** | Below Android 10 Ditto falls back to chunked BLE GATT at roughly 4 KB/s — 5× slower. This is the most version-sensitive *performance* claim in the skill: if your fleet includes pre-Android-10 devices, size your documents against 4 KB/s. |

## Behavior that varies by SDK, not by version

| Behavior | Where it differs |
|---|---|
| **Transport config validation** | Wasm/browser always rejects P2P transports. On native, **JS and Go throw** on a platform mismatch; Swift, Kotlin/Java, .NET, C++, Rust and Python accept it silently and the transport never starts. |
| **Transport-condition identifiers** | Core, Swift and Kotlin use `BleDisabled` / `NoBleCentralPermission` / `NoBlePeripheralPermission`. The JS SDK renders them `BLEDisabled` / `NoBLECentralPermission` / `NoBLEPeripheralPermission`. |
| **Transport-condition callback availability** | Not exposed by every SDK. Check the SDK skill for your language; fall back to logs where absent. |
| **Config entry point** | A mutable `transportConfig` property, an `updateTransportConfig { … }` closure, or a `setTransportConfig(config)` call, depending on SDK. The *structure* is the same everywhere except that SDKs omit sections their platform cannot use — Swift has no `wifiAware`, Kotlin has no `awdl`. |
| **Extra config sections** | Some SDKs expose platform- or preview-specific sections beyond the core four. |

## Defaults that are not a contract

The per-transport connection budgets, churn interval, and at-capacity backoff behavior
described in [`mesh-formation.md`](mesh-formation.md#connection-caps) rest on **internal
defaults that change between releases**. Exact values are deliberately not documented here —
design for the relative ordering (LAN > P2P Wi-Fi > BLE), not for a count. Only two
parameters are publicly documented and intended for tuning:

- `mesh_chooser_max_active_ble_clients`
- `mesh_chooser_avoid_redundant_bluetooth`

`mesh_chooser_avoid_redundant_bluetooth` takes effect immediately.
`mesh_chooser_max_active_ble_clients` is snapshotted at Ditto-instance construction, so
`ALTER SYSTEM` cannot change it at runtime — configure it before the instance is built.

Do not architect against an exact connection count; it is not a supported contract.
