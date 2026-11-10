# Version boundaries

## CAP-19 v4 to v5 migration, API and on-disk store

| Concern | 4.14.6 | 5.0.3 / 5.1.0 | 5.2.0 |
|---|---|---|---|
| Package | @dittolive/ditto | same | same |
| Recommended open | inspect v4 types; legacy identity API exists | await Ditto.open(new DittoConfig(id, connect, path)) | same positional form, plus config options object |
| Query | DQL; disable v3 compatibility before mutations where required | DQL only | DQL only |
| Start | startSync on legacy instance | sync.start | sync.start |
| Shutdown | inspect v4 close contract | await close() | await close() |
| JOIN/composite index/RETURNING/ADVISE | absent | 5.1.0 only | present |
| Config systemParameters | absent | absent | options constructor supports it |
| Browser disk persistence | none | none | none |

## Choosing a version

| Situation | Version |
|---|---|
| New project, no version requested | the latest stable release: `npm view @dittolive/ditto dist-tags.latest` (5.2.0 when authored) |
| User requests a version (including 4.x) | that version; v4 uses its own types and migration guide |
| New Expo / React Native starter | ships pinned to **5.2.0**, its build-verified version; if npm `latest` is newer, bump the pin and rebuild iOS and Android |
| Existing project | the version in its lockfile; do not upgrade or downgrade unless asked |
| Existing 4.x project, upgrade requested | follow the migration guides below and the store-path notes |

Version numbers from training data, blog posts or older install guides (for example
4.12 or 4.14) are not a default for new code; use 4.x only when the user asks for it.
Write an exact version, not a range. Ignore prerelease tags (`-dev-weekly`, `-preview`,
`-rc`, `-experimental`).
Do not silently upgrade an existing project. The runnable provider/native starter targets
5.x; v4 maintenance uses its own package types and migration guide. Read the exact
published package, not the repository's unreleased main branch. The test report states
which patches actually ran; this table alone is not execution evidence.

Reuse the existing native persistence path when upgrading and back it up according to
the application's data policy. A default-path change can look like lost data. Test
upgrade and any supported rollback with a copy; never downgrade a production store
merely because the JS compiles. Browser reload loss is unrelated to native migration.

Sources: <https://docs.ditto.live/sdk/latest/migration-guides/node-js-v4>,
<https://docs.ditto.live/sdk/latest/migration-guides/react-native-v4>,
<https://docs.ditto.live/sdk/latest/install-guides/js>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
