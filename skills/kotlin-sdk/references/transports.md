# Transports — Ditto Kotlin SDK

> **Sources for this file.** `sdk/latest/sync/customizing-transport-configurations.mdx`,
> `sdk/latest/migration-guides/kotlin-v4.mdx` (transport config + transport condition
> sections), `sdk/latest/install-guides/kotlin.mdx` (permissions, foreground service).
> The builder-DSL surface (`peerToPeer{}`, `listen { tcp{} http{} }`, `connect{}`,
> `global{}`, `interfaceIp`, `Global.syncGroup: UInt` vs the removed `*Long` setters)
> is **[source-verified]** against
> `sdks/kotlin/api/ditto-kotlin/src/commonMain/kotlin/com/ditto/kotlin/transports/DittoTransportConfig.kt`
> at `sdk-release-5.1.0` — the docs do not show the full Kotlin DSL.
>
> **Do not restate transport strategy, mesh formation, or the per-platform radio
> capability matrix** — that is the `ditto-mesh-networking` skill (or
> <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>).
> This file is the Kotlin API surface only.

## CAP-06 Customizing transports

All types live in `com.ditto.kotlin.transports` — the config classes are nested
under `DittoTransportConfig`, which is itself declared in that package.

### Always mutate through `updateTransportConfig`

In v5, `DittoTransportConfig` is an **immutable class** configured through a
DSL-style builder of nested blocks — you can no longer mutate fields on the config
directly:

```kotlin
ditto.updateTransportConfig { config ->
    config.peerToPeer {
        bluetoothLe { enabled = true }
        lan { enabled = true }
        wifiAware { enabled = true }
    }
}

ditto.sync.start()
```

(sdk/latest/migration-guides/kotlin-v4)

The nested builder blocks correspond one-to-one with the nested config classes:

| Builder block | Class |
|---|---|
| `peerToPeer { }` | `DittoTransportConfig.PeerToPeer` |
| `bluetoothLe { }` | `DittoTransportConfig.PeerToPeer.BluetoothLE` |
| `lan { }` | `DittoTransportConfig.PeerToPeer.Lan` |
| `wifiAware { }` | `DittoTransportConfig.PeerToPeer.WifiAware` |
| `connect { }` | `DittoTransportConfig.Connect` |
| `listen { }` | `DittoTransportConfig.Listen` |
| `tcp { }` (inside `listen`) | `DittoTransportConfig.Listen.TcpConfig` |
| `http { }` (inside `listen`) | `DittoTransportConfig.Listen.HttpConfig` |
| `global { }` | `DittoTransportConfig.Global` |

Facts about the API (sdk/latest/sync/customizing-transport-configurations,
sdk/latest/migration-guides/kotlin-v4):

- **`enableAllPeerToPeer()` is removed in v5.** Configure each peer-to-peer
  transport explicitly with `enabled = true/false`.
- Changes made via `updateTransportConfig` **after sync has started apply
  instantly** — no need to stop and restart sync.
- `ditto.transportConfig` get/set still exists, but `updateTransportConfig()` is
  the recommended approach.
- A newly created Ditto instance ships with a default configuration that enables
  all peer-to-peer transports; only customize what you need.

### BLE advertisement tuning enums are PascalCase in v5

| Enum | v4 values | v5 values |
|---|---|---|
| `DittoAdvertisementPower` | `VERY_LOW`, `LOW`, `MEDIUM`, `HIGH` | `VeryLow`, `Low`, `Medium`, `High` |
| `DittoAdvertisementFrequency` | `LOW`, `MEDIUM`, `HIGH` | `Low`, `Medium`, `High` |

(sdk/latest/migration-guides/kotlin-v4)

### Cloud sync: `connect.websocketUrls` exists but is no longer needed

`DittoTransportConfig.Connect.websocketUrls` **still exists in v5**
(`DittoTransportConfig.kt:411,441`, both published jars — **[source-verified]**;
the docs' transport page still shows it). What changed is the *workflow*: the v4
workaround of adding the Ditto Server websocket URL to the transport config is
unnecessary — the cloud URL is inferred from the identity/config you construct
the instance with, `DittoConfig.Connect.Server.url`:

```kotlin
// v4 — REMOVED
ditto.updateTransportConfig { config ->
    config.connect.websocketUrls.add("wss://REPLACE_ME_WITH_YOUR_URL_HOST")
}

// v5 — the URL is part of DittoConfig, not the transport config
val ditto = DittoFactory.create(
    DittoConfig(
        databaseId = "REPLACE_ME_WITH_YOUR_DATABASE_ID",
        connect = DittoConfig.Connect.Server("REPLACE_ME_WITH_YOUR_URL"),
    )
)
```

(sdk/latest/migration-guides/kotlin-v4). See [connect.md](connect.md) for the
full `DittoConfig.Connect` surface.

### Listening for incoming TCP connections

To act as a connection hub that other small peers connect to directly (rather
than relying on mDNS/Bluetooth discovery), enable the TCP listener:

```kotlin
ditto.updateTransportConfig { config ->
    config.listen {
        tcp {
            // TCP listen is disabled by default — enable it explicitly.
            enabled = true
            // To listen on every interface, bind to 0.0.0.0.
            // Do NOT pass the string "localhost".
            interfaceIp = "0.0.0.0"
            port = 4000
        }
    }
}

ditto.sync.start()
```

(sdk/latest/sync/customizing-transport-configurations — field semantics; builder
nesting per sdk/latest/migration-guides/kotlin-v4.)

### Connecting to remote small peers

Explicit peer connections are **not** part of `updateTransportConfig` — they are
set through DQL system configuration (SDK 4.12.0+; on earlier versions the
equivalent was `transportConfig.connect.tcpServers`):

```kotlin
ditto.store.execute("""
  ALTER SYSTEM SET TRANSPORTS_DISCOVERED_PEERS =
  [{'address': 'tcp://10.0.0.143:12345', 'type': 'force'}]
""")
```

- `address`: `tcp://` scheme only; supports IPv4, IPv6 (`tcp://[2001:db8::1:0]:12345`),
  and domain names (`tcp://mydevice.local:12345`).
- `type`: `candidate` (default — used when forming an optimal mesh; connection may
  persist after removal) or `force` (always connect; dropped immediately on removal).
- Optional `discovery_hint` field: an opaque per-peer string read from
  `SELECT * FROM system:transports_info WHERE _id = 'discovery_hint'`; it may
  change on every `sync.start()` and is used when replacing mDNS discovery.
- Changes can be made at any time but only take effect while sync is active.

(sdk/latest/sync/customizing-transport-configurations)

### Transport conditions

v5 replaces the `ditto.callback` / `DittoCallback` interface with a Kotlin
`Flow`:

```kotlin
lifecycleScope.launch {
    ditto.transportCondition.collect { event ->
        // event.condition: DittoTransportCondition
        // event.subsystem: DittoTransportCondition.Source
        println("${event.subsystem}: ${event.condition}")
    }
}
```

- `ditto.transportCondition: Flow<DittoTransportConditionEvent>`
- `DittoTransportConditionEvent(condition, subsystem)` wraps what v4 delivered as
  two separate callback parameters.
- `DittoTransportCondition.Source` is a nested enum: `Bluetooth`, `Tcp`, `Awdl`,
  `Mdns`.
- Collect within `lifecycleScope` (or another lifecycle-bound scope) so collection
  is cancelled automatically.

(sdk/latest/migration-guides/kotlin-v4)

**What the condition *values* mean** (e.g. BLE disabled vs. missing permission)
is owned by the `ditto-mesh-networking` skill if installed, otherwise
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>.

### Android runtime permissions

BLE, Wi-Fi Aware, and LAN transports require Android runtime permissions. Use the
SDK helper `DittoSyncPermissions` (`com.ditto.kotlin.transports.DittoSyncPermissions`)
rather than hand-rolling the permission list (sdk/latest/install-guides/kotlin):

```kotlin
import com.ditto.kotlin.transports.DittoSyncPermissions

fun requestPermissions() {
    val missing = DittoSyncPermissions(this).missingPermissions()
    if (missing.isNotEmpty()) {
        this.requestPermissions(missing, 0)
    }
}
```

After the user grants permissions, Ditto does not notice immediately — call
`ditto.refreshPermissions()` so sync starts without delay:

```kotlin
private val requestPermissionLauncher =
    registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        this.ditto.refreshPermissions()
    }
```

**Manifest declarations are merged automatically.** The Ditto SDK's own
`AndroidManifest.xml` declares every permission its mesh transports need, and the
manifest merger adds them to your app. The SDK's declarations include
(sdk/latest/install-guides/kotlin):

- BLE: `BLUETOOTH` / `BLUETOOTH_ADMIN` (`maxSdkVersion="30"`),
  `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`
  (`usesPermissionFlags="neverForLocation"`)
- Location (for BLE/Wi-Fi discovery on older APIs): `ACCESS_FINE_LOCATION`
  (`maxSdkVersion="32"`), `ACCESS_COARSE_LOCATION` (`maxSdkVersion="30"`)
- Wi-Fi Aware / LAN: `NEARBY_WIFI_DEVICES` (`neverForLocation`), `INTERNET`,
  `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`, `CHANGE_NETWORK_STATE`,
  `CHANGE_WIFI_MULTICAST_STATE`, `CHANGE_WIFI_STATE`

The `android:maxSdkVersion` attributes scope legacy permissions away on newer
Android versions. If your app still needs one across all versions, override it in
your own manifest with `tools:remove`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" tools:remove="android:maxSdkVersion" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" tools:remove="android:maxSdkVersion" />
```

(sdk/latest/install-guides/kotlin)

*Why* each radio needs which permission, and which transports work on which
Android version/hardware, belongs to `ditto-mesh-networking` — see
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>.

### Foreground service (background sync)

Without a foreground service, sync stops when the app is backgrounded. Declare
`DefaultDittoForegroundService` and it is **automatically started and stopped by
`sync.start()` and `sync.stop()`** (sdk/latest/install-guides/kotlin):

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" tools:targetApi="upside_down_cake" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" tools:targetApi="tiramisu" />

<application ...>
    <service
        android:name="com.ditto.kotlin.transports.DefaultDittoForegroundService"
        android:exported="false"
        android:foregroundServiceType="connectedDevice"
        android:stopWithTask="true">
        <meta-data android:name="notificationChannelName" android:value="Background Data Sync" />
        <meta-data android:name="notificationChannelId" android:value="BackgroundDataSyncId" />
        <meta-data android:name="smallIcon" android:resource="@drawable/small_app_icon" />
        <meta-data android:name="notificationTitle" android:value="Syncing Data" />
        <meta-data android:name="notificationText" android:value="Syncing data across connected devices" />
        <meta-data android:name="notificationId" android:value="1001" />
    </service>
</application>
```

Customize the `meta-data` — it is shown in the foreground-service notification,
and the `small_app_icon` drawable must be monochrome white.

## v4 notes (4.14.x)

Only relevant when reading or migrating v4 code
(sdk/latest/migration-guides/kotlin-v4):

- `DittoTransportConfig` was a **mutable data class**; the idiomatic update was
  direct mutation inside the lambda:

  ```kotlin
  // v4 — mutable properties, flat assignment
  ditto.updateTransportConfig { config ->
      config.peerToPeer.bluetoothLe.enabled = true
  }
  ```

- `enableAllPeerToPeer()` existed to turn on all peer-to-peer transports at once.
- Cloud websocket URLs were added via `config.connect.websocketUrls.add("wss://…")`.
- Top-level config classes were standalone (`DittoPeerToPeer`,
  `DittoBluetoothLeConfig`, `DittoLanConfig`, `DittoWifiAwareConfig`,
  `DittoConnect`, `DittoListen`, `DittoTcpListenConfig`, `DittoHttpListenConfig`,
  `DittoGlobalConfig`) rather than nested under `DittoTransportConfig`.
- Transport conditions arrived via `ditto.callback = object : DittoCallback {
  override fun transportConditionDidChange(...) }`.
- Removed config fields with no v5 replacement: `BluetoothLE.maxOutgoing`,
  `BluetoothLE.mtuRequest`, `Listen.HttpConfig.staticContentPath`,
  `Global.syncGroupLong` / `Global.routingHintLong` (use `UInt` directly on
  `Global.syncGroup` / `Global.routingHint`).
- v4 package root: `live.ditto.*` / `live.ditto.transports.*`.
