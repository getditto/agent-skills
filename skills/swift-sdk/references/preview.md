# Preview and platform-specific APIs — Ditto Swift SDK

## CAP-20 Preview and platform-specific APIs

This is not SwiftUI `#Preview`. It is the part of the Swift SDK that is explicitly
experimental, beta, or available on only some Apple platforms.

### `DittoConfigExperimental` — encryption at rest

```swift
let config = DittoConfig(
    databaseID: "REPLACE_ME_WITH_YOUR_DATABASE_ID",
    connect: .smallPeersOnly(),
    persistenceDirectory: directory,
    experimental: DittoConfigExperimental(passphrase: "REPLACE_ME_WITH_YOUR_PASSPHRASE")
)
```

`DittoConfig.experimental` carries the SDK's own warning:

> *"Experimental functionality should not be used in production applications as it may
> be changed or removed at any time, and may not have the same security features."*

`passphrase` is the only field on `DittoConfigExperimental`; the warning is carried by
the enclosing `DittoConfig.experimental` property. `ditto.isEncrypted` reports the state, and mismatches
throw `DittoError.encryptionError` ([errors.md](errors.md#encryptionerror_)). There is no
documented way to change or rotate a passphrase on an existing store; treat the choice as
permanent for that persistence directory.

### `DittoExperimental`

`ditto.experimental` is a `DittoExperimental` whose only public member in 5.1.0 is:

```swift
DittoExperimental.triggerTestPanic()
```

It forces a panic, and exists so you can confirm a crash reporter is wired up and
symbolicated (<https://docs.ditto.live/sdk/latest/install-guides/swift>). Never ship a call to it.

### Reliable UDP multicast — 5.1.0, private beta

`DittoMulticastBetaConfig` and `DittoPeerToPeer.multicastBeta` are new in 5.1.0:

```swift
ditto.updateTransportConfig { config in
    config.peerToPeer.multicastBeta.isEnabled = true
    config.peerToPeer.multicastBeta.groupAddress = "224.1.2.3"   // default
    config.peerToPeer.multicastBeta.port = 6003                  // default
    config.peerToPeer.multicastBeta.interfaceName = nil          // default: all interfaces
}
```

Five constraints, all of which must be stated wherever this is used:

1. **Private beta.** Use it only in coordination with Ditto support.
2. **Disabled by default**, and supported on **iOS and macOS only**.
3. **On iOS the host app must be signed with the restricted
   `com.apple.developer.networking.multicast` entitlement**, which Apple grants per app on
   request. Without it the build cannot ship.
4. **On iOS `NSLocalNetworkUsageDescription` is required** — see
   [setup.md](../../native-app-config/references/apple.md#infoplist-declarations).
5. **On iOS a change requested while sync is active does not take effect** until sync is
   stopped and successfully started again, when Ditto validates the platform
   configuration.

Its `DittoConnectionType.multicast` case is also 5.1.0-only, so an exhaustive `switch`
over connection types is version-gated
([transports.md](transports.md#connection-types)).

### Data Streams: not available in Swift

Data Streams is **not exposed by the Swift SDK**. The nearest
alternative for large payloads is an attachment
([attachments.md](attachments.md)).

### Platform exclusions

| Platform | Status |
|---|---|
| iOS, iPadOS, iOS Simulator | supported on all three lines |
| macOS (AppKit) | supported on all three lines |
| Mac Catalyst | supported on all three lines |
| tvOS | **not supported on any v5 line.** Binaries still ship at 5.0.3 and are gone at 5.1.0 — a tvOS app should stay on 4.14.x and contact Ditto support |
| visionOS | listed as a v4 beta platform in the migration guide, but no SPM slice ships on any line |
| watchOS | excluded on every line |

Detail: [versions.md](versions.md#shipped-xcframework-slices).

`DittoPeerOS.tvOS` outlives tvOS support on purpose, so a presence `switch` still has to
handle it ([presence.md](presence.md#dittopeeros-and-exhaustive-switches)).

Intel (`x86_64`) is removed from **every** 5.1.0 slice — macOS, iOS Simulator and Mac
Catalyst — not only from the Mac build.

### DittoSwiftTools

`github.com/getditto/DittoSwiftTools` is a **separate SPM package** with diagnostic
SwiftUI views: presence viewer, disk-usage inspector, logging viewer, permissions
helpers. Adding the Ditto SDK does not bring it in, and it does not inherit the SDK's
platform floor.

Version coupling, per the
[Swift v4 migration guide](https://docs.ditto.live/sdk/latest/migration-guides/swift-v4): Tools **10.0.0**
is the first major release supporting DittoSwiftPackage 5, requires **5.0.1 or later**,
needs a Swift 6 toolchain, raises its targets to iOS 15 / Catalyst 15 / macOS 12, and
removes tvOS support along with `DittoTvOSTextFieldComponent`. Direct
`DittoPresenceViewerCore` dependencies must be dropped, because Tools 10 bundles those
assets.

5.1 changes: `DiskUsageInspectorView` added; the SDK's own `DittoSwiftPresenceViewer`
framework target and podspec removed in favour of Tools' `DittoPresenceViewer`.

Do not assume tvOS support for DittoSwiftTools; check the Tools repository's release notes
for its current platform list.
