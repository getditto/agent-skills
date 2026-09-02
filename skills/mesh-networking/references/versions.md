# Version Matrix

Version-gated claims in this skill, in one place. Anything not listed here is
version-independent as far as this skill is concerned.

**Confirm the user's SDK line before answering a version-sensitive question.** This skill
targets the same lines as the rest of this repo: **Ditto SDK 4.14.x (LTS), 5.0.x, 5.1.x**.

## Feature and behavior gates

| Claim | Applies to | Notes |
|---|---|---|
| `TRANSPORTS_DISCOVERED_PEERS` system parameter, and the `discovery_hint` / `system:transports_info` pattern for replacing mDNS | **SDK 4.12.0+** | Publicly documented as "supported in SDK version 4.12.0 and later". |
| `mesh_chooser_max_active_ble_clients` replaces `DittoBluetoothLeConfig.maxOutgoing` | **SDK 4.9.0+** (Java/Kotlin) | `maxOutgoing` is deprecated, not removed; the field still exists in core. |
| **Document hard limit rejects the local write** | Current SDKs | Earlier builds logged an `error` and accepted the write. Public docs still describe the older log-only behavior, so verify against your SDK line rather than the docs page. The limit gates *local writes only* — oversized documents already in the mesh replicate in regardless. |
| Wi-Fi Aware transport | **Android API 29+** (Android 10), hardware support required | Below API 29 the SDK logs an error and continues; `startSync()` still succeeds. |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` runtime permissions | **Android API 31+** | Below that, BLE scanning is gated on location permission instead. |
| `NEARBY_WIFI_DEVICES` permission (with `neverForLocation`) | **Android API 33+** | On API 29–32 use `ACCESS_FINE_LOCATION`, and the system location toggle must be on. |
| Bluetooth 5 2M PHY requested | Android only, adapter-dependent | Not implemented in the Apple, BlueZ or WinRT BLE backends. It is a *preference* the controller may decline. |

## Behavior that varies by SDK, not by version

| Behavior | Where it differs |
|---|---|
| **Transport config validation** | Strict (throws, naming the offending transports) in **Wasm/browser** builds only. Native SDKs accept an unsupported transport silently; it never starts and logs a warning. |
| **Transport-condition identifiers** | Core, Swift and Kotlin use `BleDisabled` / `NoBleCentralPermission` / `NoBlePeripheralPermission`. The JS SDK renders them `BLEDisabled` / `NoBLECentralPermission` / `NoBLEPeripheralPermission`. |
| **Transport-condition callback availability** | Not exposed by every SDK. Check the SDK skill for your language; fall back to logs where absent. |
| **Config entry point** | A mutable `transportConfig` property, an `updateTransportConfig { … }` closure, or a `setTransportConfig(config)` call, depending on SDK. The *structure* is identical everywhere. |
| **Extra config sections** | Some SDKs expose platform- or preview-specific sections beyond the core four. |

## Defaults that are not a contract

The per-transport connection budgets, churn interval, and at-capacity backoff behavior
described in [`mesh-formation.md`](mesh-formation.md#connection-caps) rest on **internal
defaults that change between releases**. Exact values are deliberately not documented here —
design for the relative ordering (LAN > P2P Wi-Fi > BLE), not for a count. Only two
parameters are publicly documented and intended for tuning:

- `mesh_chooser_max_active_ble_clients`
- `mesh_chooser_avoid_redundant_bluetooth`

Both are snapshotted when the mesh chooser is constructed — set them before `startSync()`.

Do not architect against an exact connection count; it is not a supported contract.
