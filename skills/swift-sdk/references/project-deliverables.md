# Swift app deliverables

For a new-app request, deliver files that can be opened and run. For an existing
app, make a focused integration and identify its actual target/scheme. Keep detailed
API guidance in the relevant SDK references.

## New SwiftUI project

The [generator](../scripts/create-swift-app.py) supplies:

| Deliverable | Purpose |
|---|---|
| `<Name>.xcodeproj` and shared scheme | Openable app target and exact SDK package pin |
| `App/StarterApp.swift` | Local write → store observer → SwiftUI list; one app-lived owner |
| `App/Info.plist` | Bluetooth/local-network usage descriptions and Bonjour service |
| `App/Mac.entitlements` | Mac sandbox, network client/server and Bluetooth declarations |
| `App/LocalConfig.plist` | Local development database ID/license; ignored by Git |
| `App/LocalConfig.example.plist` | Reconstruct configuration after cloning without committing credentials |
| `README.md` | Configuration, destinations, commands, two-peer demonstration and limitations |
| `.gitignore` | Excludes local configuration and build/user state |

The template creates a foreground notes demo for iOS/iPadOS 15+, macOS 12+ and
Mac Catalyst 15+, using a Swift 6 toolchain. Ad-hoc signing supports local Simulator
and Mac builds; physical iOS deployment requires the user's development team and
provisioning. Background execution is a separate application requirement, not
something the starter's foreground demonstration establishes.
The 5.1.0/5.2.0 project is arm64-only, matching the published XCFramework. Do not promise
Intel Mac/Simulator compatibility for that pin or disable signing to force a build.

## Existing app

- Keep its package manager, supported OS versions, identity flow, target layout
  and UI framework. Confirm the resolved SDK pin before choosing API forms.
- Introduce one stable Ditto owner at the composition root; retain and explicitly
  cancel the relevant observers/subscriptions at their lifecycle boundary.
- Add only required target permissions/entitlements from [setup.md](setup.md).
- Bind query arguments and decode Sendable snapshots before actor hops. Separate
  a sync subscription's unsorted query from an observer's local sorted query.
- Provide the concrete changed paths and the customer's build/run entry point.

## Completion record

State the status of each applicable stage independently:

| Stage | Evidence to report |
|---|---|
| Generated/integrated | Real paths, target/scheme, exact pin and configuration location |
| Built | Exact command, SDK pin, destination and result |
| Launched | Actual destination; distinguish launch from build success |
| Local data path | Named write visible through the observer and retained after reopening |
| Peer sync | Two separate stores/containers, matching database, subscriptions, observed transport and direction |
| Offline/reconnect | Local operation during disconnection and delivery after reconnection; identify simulation vs real network loss |

Do not mark a stage passed because instructions exist for it. If execution was not
requested or the host lacks Xcode/devices/credentials, say which stage remains
unverified and leave exact reproducible instructions. Do not delete a live store,
disable signing, or change authorization to force a demonstration to succeed.

## Product adaptation

The starter's all-`notes` subscription is a bounded teaching example. Adapt schema,
subscriptions, retention, authentication and conflict behavior to the actual domain.
Use concept skills if installed, otherwise the official links in the entry point.
Client filtering is not a replacement for authorization. A development license in
the bundle is not suitable storage for server credentials.

Source for target setup: [Swift installation](https://docs.ditto.live/sdk/latest/install-guides/swift).
