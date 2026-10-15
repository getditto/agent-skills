# @APP_NAME@

SwiftUI starter pinned to Ditto **@SDK_VERSION@**. The Xcode project has one shared
scheme for iOS/iPadOS, macOS and Mac Catalyst. The app writes notes to a local store,
updates its UI through a store observer and subscribes to the demo collection.

## Configure and run

1. Obtain a Ditto database ID and an offline development license from your Ditto
   project in [the portal](https://portal.ditto.live/). An installed agent skill does
   not provide an SDK license. This starter uses small-peers-only connectivity;
   it does not provision or contact a Ditto Server.
2. Set `DatabaseID` and `OfflineLicense` in `App/LocalConfig.plist`. That file is
   gitignored. It is embedded in a development app, so the license is extractable
   from the app bundle; do not put server admin credentials here or use this demo
   configuration as production authentication.
3. Open `@APP_NAME@.xcodeproj`. Allow Xcode to resolve the exact SDK package pin.
4. Select the `@APP_NAME@` scheme and an iOS Simulator, My Mac or Mac Catalyst
   destination, then **Product → Run**. Keep code signing enabled: Simulator and
   local Mac builds use ad-hoc signing. For a physical iOS device, open the target's
   **Signing & Capabilities**, enable automatic signing and select your Development
   Team; use a unique bundle ID.
5. Add a note. It should appear through the observer. Close and reopen the app to
   check persistence. Use **Diagnostics** to inspect the last delivery, document
   count, store path, requested sync state and observed mesh connections.

Swift 6/Xcode 16 or later is required by this starter. The SDK may support older
toolchains; the generated Swift 6 project deliberately uses this narrower baseline.
The starter's deployment floors are iOS/iPadOS 15, macOS 12 and Mac Catalyst 15.
The published 5.1.0 XCFramework has arm64-only slices for all four destinations,
so the 5.1.0 project explicitly targets arm64 (including Simulator). That pin cannot
build for an Intel Mac. Older pins retain their SDK's available architectures.
It is a SwiftUI starting point; UIKit/AppKit integration remains a separate task.

## Build from a terminal

```bash
xcodebuild -project @APP_NAME@.xcodeproj -scheme @APP_NAME@ -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build
xcodebuild -project @APP_NAME@.xcodeproj -scheme @APP_NAME@ -destination 'platform=macOS' -derivedDataPath DerivedData build
xcodebuild -project @APP_NAME@.xcodeproj -scheme @APP_NAME@ -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath DerivedData build
```

If you cloned the generated app and `LocalConfig.plist` is absent, copy
`App/LocalConfig.example.plist` to `App/LocalConfig.plist` and configure it before
building. Never turn signing off to work around a build error: an unsigned embedded
Ditto framework can compile successfully and then fail to load.

## Two-peer demonstration

1. Run the app on two independent destinations with the **same** database ID and
   license. Each needs its own app data container. For actual BLE/AWDL behavior,
   use supported physical devices; simulator behavior does not validate radios.
2. Keep both apps in the foreground. Grant Bluetooth and local-network permissions
   when prompted. On a shared LAN, add a uniquely named note on one peer and look
   for it on the other. Refresh Diagnostics and record the observed connection type.
3. On one peer, use Diagnostics → **Pause sync (simulation)**. Add a note there.
   It should remain locally usable; it should not reach the other peer while paused.
4. Resume sync and check that the note reaches the other peer. Repeat in the other
   direction. Pausing the SDK simulates disconnection; it does not test OS network
   loss, background execution, permission revocation or a specific radio.

## Troubleshooting

| Symptom | First check |
|---|---|
| Configuration error | Both fields in `LocalConfig.plist`; rebuild after editing |
| `dyld` / unsigned framework | Keep signing enabled and read the loader's full error |
| Local write succeeds, other peer sees nothing | Same database/license, matching subscription, foreground state, permissions and observed connection |
| Sync requested is yes, zero peers | Requested sync is not connectivity; inspect permissions, LAN/discovery and firewall |
| Local row never appears | Read the visible operation error; confirm the observer is registered |
| Persistence directory locked | Close the other instance using that exact directory; do not delete a live store |

The generated model owns one Ditto instance and cancels its consumer, observer and
subscription before closing. It does not close on every screen disappearance or
background transition. Closing retains the store and does not delete documents.

This is a bounded demo, not a production access-control model. It subscribes to all
`notes`; add application-specific scopes, authentication, retention and bounded
query behavior before using the pattern for customer data.

## Documentation

- [Swift SDK installation](https://docs.ditto.live/sdk/latest/install-guides/swift)
- [Presence](https://docs.ditto.live/sdk/latest/sync/using-mesh-presence)
- [Transport configuration](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations)
