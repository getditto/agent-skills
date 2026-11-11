# JavaScript / React Native / Expo verification

Tests execute the code shipped in skills/js-sdk/assets, copied byte-for-byte into an
ignored .generated directory. The Expo fixture is generated from the installed-style
sibling skill assets. No internal Ditto source checkout is needed.

## Run

Node 22+ and Python 3.9+ are required by the harness. Configure the repository-root
.env as described in .env-sample; DITTO_OFFLINE_LICENSE is required for runtime tests.
The existing environment takes precedence. No credentials belong in tracked fixtures.

```bash
npm ci --prefix tests/js-sdk
npm run typecheck --prefix tests/js-sdk
npm test --prefix tests/js-sdk
cd tests/js-sdk
npx playwright install chromium
npm run test:browser
python3 test_artifacts.py
python3 stage-mobile.py
npm ci --prefix mobile
npm run typecheck --prefix mobile
cd mobile
CI=1 npx expo export --platform ios --platform android
CI=1 npx expo prebuild --no-install
cd ..
python3 test_artifacts.py --native
```

Repeat prebuild and the native assertions to check idempotence. All generated native
projects and local config stay ignored. stage-mobile.py preserves an existing local
credential file and refreshes source/assets. config.local.json contains placeholders
unless explicitly configured for an on-device run.

For native compilation, run `pod install --repo-update` in mobile/ios on a Mac with
Xcode/CocoaPods, then build the generated workspace for an arm64 simulator
(`ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=-`). Android uses
`./gradlew :app:assembleDebug -PreactNativeArchitectures=arm64-v8a` in mobile/android
with JDK 17 and a configured Android SDK. Use the architecture matching your test target.
Neither native command is replaced by a successful TypeScript/Metro check.

## Evidence

| Layer | What it proves | Status at authoring |
|---|---|---|
| Node 5.0.3 / 5.1.0 / 5.2.0 | Actual SDK CRUD/parameters, observer delivery, rollback, index, attachment bytes, eviction, persistence reopen, shutdown race, missing auth handler, two-peer TCP replication and signalNext | Passed |
| Browser 5.0.3 / 5.1.0 / 5.2.0 / Chromium | Actual WASM plus React StrictMode, query replacement, cleanup/remount and reload data loss | Passed |
| Expo 57.0.31 / RN 0.86.3 / React 19.2.3 | TypeScript and Hermes bundles for iOS + Android | Passed |
| Expo prebuild | Shipping Ditto plugin's generated Apple/Android configuration | Passed; plist/manifest assertions |
| Native compilation | CocoaPods/Gradle linkage, Ditto 5.2.0, TypeScript 6.0.3 | iOS simulator and Android arm64 APK builds passed |
| iOS 27.1 / Xcode 27.2 | App launch; automated real JSI/provider observer CRUD and process-relaunch persistence | Passed; integration probe, not UI taps |
| Android 15 / API 35 emulator | Permission denial/retry/grant, task UI CRUD and process-relaunch persistence | Passed |
| Physical devices | BLE/AWDL/Wi-Fi Aware, Apple permission dialogs, background execution | Not executed; acceptance checklist in js-react-native |

The 5.0.3/5.1.0 local runs and CI jobs exercise the 5.x shared API. v4.14.6 is a migration/reference
boundary, not a claim that the v5 starter runs unchanged on v4. No production auth,
EAS deployment, app-store submission or real radio coverage is inferred from local tests.

## Tests and maintenance

- sdk.test.ts tests observable data/resource behavior against the real native SDK.
- permissions.test.ts covers API 23/30/31/32/33+ request decisions with/without Aware.
- browser/runtime.spec.ts tests real WASM and React effects; no mocked Ditto database.
- test_artifacts.py validates XML/plist, deterministic scoped archives, extracted-plugin
  generation, existing-project refusal, and actual Expo prebuild outputs.
- Native fixtures compile the same App/TasksScreen/permissions/provider sources used by
  the generator. Lockfiles pin tools as well as SDK versions.

Keep skill source assertions separate from evidence. Compiling TypeScript verifies
method signatures; real runtime tests verify behavior; physical devices verify radios.
Tests fail rather than silently skipping when a required license/native output is absent.
The test launcher normalizes NO_COLOR to a boolean accepted by the native logger.

## Optional server authentication

With DITTO_DATABASE_ID, DITTO_URL and DITTO_TOKEN set in the test environment, run
`NO_COLOR=true node --import tsx cloud.ts` from this directory after staging assets.
It exercises the same runtime's expiration handler and login against the configured
server, awaits authenticated status, closes, and writes no documents. Executed on 5.2.0
with the local test configuration. Credential values and customer endpoints are not
included in this report. CI does not imply this optional external check ran.

## Reproduce iOS native runtime verification

The optional [native probe](native/Probe.tsx) imports the shipped runtime, provider,
query hook, tasks and permissions without mocking Ditto. It is test instrumentation,
not customer app UI. Configure the generated fixture's ignored config.local.json with
a development offline license first. Build/install the generated native app with normal
simulator ad-hoc signing (`CODE_SIGN_IDENTITY=-`); do not disable signing of DittoCore.

1. Copy native/Probe.tsx to mobile/src/App.tsx in the generated test fixture.
2. Start `node native/receiver.mjs` to collect status-only results on localhost:8094.
3. In mobile, start `CI=1 NODE_OPTIONS=--dns-result-order=ipv4first npx expo start
   --dev-client --localhost --port 8092`. IPv4 binding avoids a dev-client/localhost mismatch.
4. Run `xcrun simctl launch --terminate-running-process DEVICE_ID com.example.dittotasks
   --initialUrl http://localhost:8092` for an already booted/installed simulator.
5. Require all first-leg PASS lines and READY_FOR_PROCESS_RELAUNCH; repeat the launch
   command to terminate and restart the native process. Require restored-row PASS,
   cleanup PASS and COMPLETE. A leftover row from an interrupted run can run only the
   second leg; rerun from COMPLETE to collect both legs for a full pass.
6. Restore the shipped app with `python3 stage-mobile.py`. Stop your Metro/receiver
   and simulator. Never replace a customer's App with this harness.

Executed 2026-11-02 on iOS 27.1 arm64. The unmodified app rendered its initial permission
explanation; DeviceHub accessibility was unavailable, so CRUD used this automated
native probe. Android acceptance used actual UI input and process force-stop/relaunch.
These checks do not establish physical radio sync, iOS privacy-dialog behavior, or
release provisioning. See the platform skill acceptance checklist for those checks.

CI is configured for the same three SDK patches and an Xcode 27 arm64 native build;
these authoring results are local execution, not a claim that remote CI already ran.

The starter's scene opt-in is required with Xcode 27. Its scoped Kotlin compiler plugin
aligns Expo 57's root compiler with Ditto's Kotlin 2.3 metadata; prebuild assertions
check both the property and root dependency. Expo 58.0.22 / RN 0.88.1 failed Ditto
5.2.0 native iOS compilation because RCTCxxBridge.runtime was removed, so the starter
uses the tested 57/0.86 pair. Do not replace this matrix with an unverified "latest" claim.
