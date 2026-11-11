# Swift workflow and installation evidence

Recorded 2026-10-15 for the Swift getting-started/deliverables/troubleshooting and
host-packaging changes, including an independent three-reviewer production audit.
The runtime checks below use the canonical shipped starter. They do not establish
new live-model evaluation results.

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

`scripts/package-sdk-plugin.py --check` passes. The builder produced marketplace,
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

Fresh native installation/discovery checks passed in isolated configuration directories:

- Claude Code 2.1.292: source checkout and materialized marketplace both install;
  `plugin details` finds exactly `swift-sdk`, with no agents, hooks or MCP servers.
  The installed cache materializes the skill, and its generator executes successfully.
- Gemini CLI 0.47.0: the local extension installs after its normal trust prompts;
  extension and skill listings show version 1.1.0 enabled.

These checks used documented `CLAUDE_CONFIG_DIR` and `GEMINI_CLI_HOME` overrides;
no global plugin configuration or user skills were changed. Model invocation and
desktop UI acceptance remain distinct from installation/discovery. Codex, Cursor,
Copilot, Antigravity and OpenCode native acceptance remains unverified. Cursor's
documented team/admin and local-import prerequisites are now explicit in the guide.
Public-directory publication is separate from supplying installation packages.

## Runtime checks and review corrections

The full SDK fixture and minimal app passed locally on 4.14.6, 5.0.3 and 5.1.0,
with 94 test invocations in 15 suites per version (including expected version-gated skips).
This includes a new regression executing the documented SwiftUI project/task stores'
inline observer callbacks; compilation and generic bridge tests had missed that path.
The canonical starter's separate model probe passes on all three pins, checking:

- Missing configuration, malformed UUID and empty license rejection.
- Concurrent-open protection, initial observer delivery and a nonempty local write.
- Local writes with sync paused, then sync resume.
- Cleanup, directory-lock release and persisted values after reopening.

Reproduce after a generated macOS app build:

```bash
python3 tests/swift-sdk/scripts/test-starter.py 5.1.0 --frameworks /tmp/DittoNotesBuild/Build/Products/Debug
python3 -m unittest discover -s tests/swift-sdk -p 'test_*.py' -v
```

The runtime probe reads the configured offline test license without printing it,
compiles the canonical Swift source with only its app entry point excluded, verifies
the actual SDK version and fails on missing delivery, timeout or process crash.
It copies frameworks into its own temporary directory before signing them.

Review found a runtime actor-isolation trap in the starter's observer decoding:
an unannotated callback created on `MainActor` could trap on SDK 5.0.3's callback
thread. An explicit `@Sendable` handler fixes it. A negative control removing that
annotation crashes the same probe; the corrected source passes all three pins.

Hosted CI exposed two fixture assumptions: a missing `.build` directory on fresh
checkouts and a hardcoded test-bundle name that differed between SwiftPM backends.
Both are corrected and covered by four fast runner regression tests. The platform
runner builds `UIPatterns` and its dependencies, avoiding duplicate v4 framework-copy
outputs from two CLI executables in Xcode 26's whole-package scheme. CLI products
are built and executed separately. A load-dependent timing assertion was removed;
the structural executor checks and timing diagnostics remain. Scoped JOIN regression
checks now run in the SDK 5.1 DQL CI leg.

Nine packaging regression tests verify reproducibility, checksums, complete resources,
scoped catalogs, metadata drift, output preservation and source-symlink rejection.
The latter prevents future links from copying files outside the canonical skill;
the reviewed source and release archives contained no such links.

## Remaining release acceptance

Model-runtime checks do not launch and drive the graphical app. Full UI interaction,
two-peer delivery and physical BLE/AWDL remain unverified. The README provides exact
procedures and distinguishes simulated sync pause from real network loss. Physical
device provisioning, background execution and production authentication remain
application-specific. Complete those checks and the remaining native-host acceptance
before claiming every advertised installation and app workflow is production proven.

The repository's SDK skill validator passes without warnings. The system
skill-creator helper could not run because its Python environment lacked PyYAML;
no user Python installation was modified to supply it. The repository validator
checks the SDK contract, links, context limits and existing fixture identity.
