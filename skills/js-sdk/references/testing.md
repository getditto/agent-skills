# Test the shipped assets

## CAP-18 Testing

The [harness](../../../tests/js-sdk/README.md) copies the exact published assets into
an ignored fixture directory before typechecking and executing them. It verifies
local CRUD, observer delivery and cancellation, rollback, indexing, attachments,
eviction, persistence, runtime races, and React lifecycle behavior. Browser tests run
actual WASM in Chromium. Mobile checks compile the same provider and native UI, bundle
with Metro, run Expo prebuild, and inspect generated native config.

Keep evidence tiers separate: TypeScript is not native compilation; prebuild is not
permission acceptance; a simulator is not Bluetooth/AWDL/Wi-Fi Aware proof. Run the
physical-device acceptance checklist in the platform skill for radio/background claims.
Credentials are loaded from the gitignored root .env by tests/lib/load-env.mjs; CI
variables take precedence. Fail an expected integration job when its license is absent;
do not turn it into a green skipped test. Never commit credentials into generated apps.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
