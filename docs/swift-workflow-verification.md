# Swift workflow and installation evidence

Recorded 2026-10-15 for the Swift getting-started/deliverables/troubleshooting and
host-packaging changes. This record does not replace the SDK fixture's earlier
runtime evidence or claim new model-evaluation results.

## Generated app builds

Toolchain: Xcode 27.1, build 27A9269; Apple Swift 6.4
(`swiftlang-6.4.0.34.1`), on an arm64 Mac. Each project was generated into a fresh
directory with an exact SDK pin. Configuration values remained empty: compiling the
starter needs no offline license or server credentials.

| SDK | macOS | iOS Simulator | Mac Catalyst |
|---|---|---|---|
| 4.14.6 | Build passed | Build passed | Build passed |
| 5.0.3 | Build passed | Build passed | Build passed |
| 5.1.0 | Build passed | Build passed, arm64 | Build passed |

Reproduce from the repository root, substituting each exact pin and a fresh folder:

```bash
python3 skills/swift-sdk/scripts/create-swift-app.py /tmp/DittoNotes --sdk-version 5.1.0
xcodebuild -project /tmp/DittoNotes/DittoNotes.xcodeproj -scheme DittoNotes -destination 'platform=macOS' -derivedDataPath /tmp/DittoNotesBuild build
xcodebuild -project /tmp/DittoNotes/DittoNotes.xcodeproj -scheme DittoNotes -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/DittoNotesBuild build
xcodebuild -project /tmp/DittoNotes/DittoNotes.xcodeproj -scheme DittoNotes -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/DittoNotesBuild build
```

The signed macOS 5.1.0 app also passed `codesign --verify --deep --strict`.
The legacy `disableSyncWithV3()` warning is expected on 4.14.6 and excluded from v5
compilation. AppIntents metadata-extraction warnings occurred without a dependency
on AppIntents; these were not build failures.

Initial attempts exposed issues that were corrected before the passing results:

- A sandbox dependency fetch could not resolve GitHub. Retrying with permitted
  network access fetched the public SDK package.
- Stripping the prebuilt 5.1.0 framework failed in this Xcode toolchain. The generated
  app sets `COPY_PHASE_STRIP=NO` and keeps signing enabled.
- Xcode requested unsupported x86_64 architectures. Debug builds use the active
  architecture; the exact 5.1.0 pin explicitly targets arm64, matching the published
  XCFramework's `Info.plist` slices. The generic Simulator leg then passed.
- An early template called an unavailable `Ditto.close()`. The final template cancels
  its handles, stops sync and releases the last instance reference, matching the SDK.

CI now generates the app and builds the same three destinations for all three pins.
Fresh CI results must be reviewed independently of these local results.

## Installation packages

`scripts/package-swift-plugin.py --check` passes. The builder produced marketplace,
standalone plugin, Antigravity, Gemini and per-skill-upload ZIPs. Archive inspection
found one canonical `swift-sdk` entry in each, local scripts/assets, no symlinks and
parseable JSON metadata. The packaged Swift starter matches the canonical asset.
Packaged Markdown remains within the repository's size limits after maintainer links
are rewritten to GitHub. SHA256SUMS and the generic package's file manifest are emitted.

The existing plugin name remains `ditto-swift`, now version 1.1.0. Existing Claude
concept plugins retain their scopes. New native catalogs and packages expose Swift
only; no Kotlin implementation is included.

The host commands and formats were checked against current vendor documentation.
Installed CLI help confirms Codex marketplace management and Gemini local-extension
installation. The installed Antigravity CLI treats `plugin install`'s argument as a
directory (including `--help`); the documented local-directory route is retained.
Listing unregistered temporary catalogs is not an install or activation check.

**Fresh installs/activation have not been executed across every host.** Claude and
Codex desktop UI variations, Cursor and Copilot installations, Gemini/Antigravity
activation and OpenCode execution remain client acceptance work. No global plugin
configuration or installed user skills were changed. Public-directory publication
is also separate from supplying native/local installation packages.

## Remaining runtime scope

The generated apps were compiled and signed, not launched or exercised with real
credentials. Local persistence, observer-driven UI behavior, two-peer delivery,
pause/reconnect behavior and physical BLE/AWDL are therefore not new runtime passes.
The generated README gives explicit procedures and separates simulated disconnection
from actual network loss. Physical-device signing/provisioning and production
authentication remain application-specific.

The repository's SDK skill validator passes without warnings. The system
skill-creator helper could not run because its Python environment lacked PyYAML;
no user Python installation was modified to supply it. The repository validator
checks the SDK contract, links, context limits and existing fixture identity.
