# Preview and platform-specific APIs — Flutter

## Contents

- [CAP-20 Preview APIs](#cap-20-preview-apis)
  - [Not in the Flutter SDK](#not-in-the-flutter-sdk)
- [APIs available only on some platforms of this SDK](#apis-available-only-on-some-platforms-of-this-sdk)

## CAP-20 Preview APIs

Preview APIs can change or disappear in any release without notice. Each entry names the
opt-in and the first version.

| API | Since | Opt-in | Stable alternative |
|---|---|---|---|
| `Store.registerObserverV2`, `Store.registerObserverWithSignalNext`, `StoreObserverV2` | 5.1.0 | `@experimental` (`package:meta`): each use needs `// ignore: experimental_member_use` under `flutter analyze --fatal-infos` | `registerObserver` (V1) |
| `Store.experimentalSkipExecuteIsolateOffload` | 5.1.0 | `@experimental` static setter | the default worker isolate |
| Multicast transport, `config.peerToPeer.multicastBeta` and `ConnectionType.multicast` | 5.1.0 | Off by default; "in private beta and should only be used in coordination with Ditto support" (dartdoc of `MulticastBetaConfig`) | the other peer-to-peer transports |

From `lib/src/store/store.dart`, `transport_config.dart` and
`presence/presence_graph.dart` @ `sdk-release-5.1.0` and `sdk-release-5.2.0`; none exists
in 5.0.4. Observers: [observers.md](observers.md#registerobserverv2-510), executed on
macOS and (signal-next) Chrome. Multicast was not executed here; which deployments it
suits is the `ditto-mesh-networking` skill if installed, otherwise
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>. On iOS
and Android a multicast change applies only after `sync.stop()` and the next
`sync.start()` (dartdoc of `MulticastBetaConfig`).

### Not in the Flutter SDK

- **Data Streams**: not in `ditto_live` on any line (no such API in `lib/` @
  `sdk-release-5.2.0`). The docs list them as a Public Preview for Swift and Kotlin
  from 5.2.0 (<https://docs.ditto.live/sdk/latest/sync/data-streams>); the
  `data-streams` skill explains the concept. In Flutter, sync ordinary documents
  instead.
- **Encryption at rest: no supported API.** `DittoConfigExperimental.passphrase` is
  documented in the dartdoc as "undocumented and for internal use only" (5.0.4, 5.1.0)
  and "retained for configuration compatibility" (5.2.0). Executed (macOS, debug):
  `Ditto.open` with a passphrase succeeded on 5.0.4 and 5.1.0 (whether the store was
  encrypted was not checked) and failed on 5.2.0 with
  ``DittoException(Invalid DittoConfig: Passphrase-based encryption is no longer supported. Remove the `experimental.passphrase` entry from the Ditto config and use an encryption key instead.)``.
  5.2.0 exports `DittoEncryptionException` and `DittoEncryptionErrorReason`, but
  `DittoConfig` has no field for a key, so they cannot be produced from Dart. Do not set
  a passphrase. The docs list app-level encryption at rest (`DittoConfig.encryptionKey`)
  for Swift and Kotlin 5.2+ only, with other SDKs planned
  (<https://docs.ditto.live/sdk/latest/sync/encryption-at-rest>).
- **A sync-status API**: use `commitID` and `system:data_sync_info`
  ([sync.md](sync.md#cap-14-sync-status)).
- **A disk-usage API**: use `system:system_info`
  ([observability.md](observability.md#disk-usage)).

## APIs available only on some platforms of this SDK

Detect the platform at run time with `kIsWeb` first, then `Ditto.currentPlatform`, never
`defaultTargetPlatform` ([setup.md](setup.md#gate-platform-code-with-kisweb-then-dittocurrentplatform)).

| API | Where it does something | Elsewhere |
|---|---|---|
| `config.peerToPeer.awdl` | iOS, macOS | — |
| `config.peerToPeer.wifiAware` | Android | — |
| `config.peerToPeer.bluetoothLE`, `lan` | iOS, Android, macOS, Linux, Windows | Web: enabling one throws `DittoException` ([web.md](web.md#web-differences)) |
| `DittoSyncPermissions` (5.1.0+) | Android: lists the runtime permissions Ditto needs | `requiredPermissions()` is `[]` on web (executed); see [setup.md](setup.md#android-runtime-permissions) |
| `ditto.observeTransportConditions` (5.1.0+) | Native and web both have a bridge for it (source); executed on macOS only: no event within 5 s with peer-to-peer off | [transports.md](transports.md#transport-conditions-510) |
| File-path attachments, `Attachment.copyToPath`, `DittoLogger.exportLogs` | Native | Web: fail or throw ([web.md](web.md#web-differences)) |
| `Store.experimentalSkipExecuteIsolateOffload` | Native | No effect on web |
| A persistent store | Native | Web: in memory, empty after a page load ([web.md](web.md#in-memory-store-and-reload)) |
