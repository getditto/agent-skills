# Getting started with a Ditto Swift app

Use this workflow when the user wants a new runnable app. For a change to an existing
app, inspect its package pin, lifecycle owner and target settings, then integrate in
place. Keep the user's UI framework and authentication choice.

## Establish the destination

Gather only missing information: existing project or new folder; iOS/iPadOS, macOS
or Mac Catalyst; SwiftUI/UIKit/AppKit; existing SDK pin; and small-peers-only or a
Ditto Server connection. Inspect the workspace/toolchain first. A reasonable new-demo
default is SwiftUI, SDK 5.1.0 and an iOS Simulator destination; state that assumption.
The generator supports 4.14.6, 5.0.3, 5.1.0 and 5.2.0 and needs Python 3.9+ plus Swift 6/Xcode
16+. Confirm compatibility using [versions.md](versions.md); do not downgrade or
upgrade a customer's dependencies merely to match the demo.
SDK 5.1.0's published binary is arm64-only, so that starter pin requires Apple
silicon for Mac/Simulator builds. State this before selecting it on an Intel host.

## New project: create the deliverable

Use the bundled [project generator](../scripts/create-swift-app.py) through the host's
command tool. Paths below are relative to the installed skill directory; first resolve
the actual installed location, which can differ between hosts.

```text
python3 <installed-skill>/scripts/create-swift-app.py <new-project-directory> --name DittoNotes --sdk-version 5.1.0 --bundle-id com.example.ditto.notes
```

The destination must not exist. The generator writes a complete Xcode project and
shared scheme, a SwiftUI notes app, usage descriptions, Mac sandbox entitlements,
local configuration/example files and a project README. It never merges into an
existing app. For UIKit/AppKit, use the existing SDK reference patterns rather than
claiming this generator produces those UI frameworks.

The generated demo uses **small-peers-only** connectivity. Obtain the database ID and
offline license through the user's Ditto project; do not invent credentials, fetch
secrets from unrelated workspaces or print tokens. Have the user populate the
gitignored `App/LocalConfig.plist`. An installed skill does not activate the SDK.
The starter embeds this development configuration in the app bundle; it is not a
production secret store or an access-control design.

For a server-connected app, preserve the user's server URL, auth provider and login
flow. Read [connect.md](connect.md) and [lifetimes.md](lifetimes.md); adapt the generated
composition root deliberately, install the expiration handler before starting sync,
and use the app's credential store. Do not imply that the mesh starter provisions a
backend or already implements server authentication.

## Open, run and hand off

1. Open the generated `.xcodeproj`, resolve the exact Swift package pin and select
   the shared scheme and destination. Keep framework/app code signing enabled.
2. Run the app and add a note. The observer, not a local array append, should deliver
   it to the list. Restart to inspect persistence. Report separately whether you
   generated, compiled, launched, or observed the write/read path; do not infer one
   from another.
3. Use Diagnostics to inspect requested sync state, actual presence, observed
   connection types, store location and last observer delivery. Zero peers is valid
   on an isolated device; `sync.isActive` is not a connectivity indicator.
4. Follow the README's two-peer procedure if sync demonstration is requested. Use
   supported physical devices for BLE/AWDL claims. Label the pause/resume action as
   simulated disconnection, not proof of physical radio behavior.
5. Hand off the project path, exact SDK pin, configuration file, scheme/destination,
   run command and checks actually completed. Include remaining prerequisites and
   the shortest next action for a failure; use [troubleshooting.md](troubleshooting.md).

See [project-deliverables.md](project-deliverables.md) for the completion contract.

## Technical sources

- [Ditto Swift installation](https://docs.ditto.live/sdk/latest/install-guides/swift)
- [Mesh presence](https://docs.ditto.live/sdk/latest/sync/using-mesh-presence)
- [Transport configuration](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations)

Generating the project proves neither runtime behavior nor peer connectivity; report
each separately.
