# Diagnostics

## CAP-15 Logging, diagnostics and stats

Report SDK version (`Ditto.VERSION`), platform, initialization state, auth state,
`sync.isActive`, peer count, permission state, and the last local query error as separate
fields. Never label sync-active as fully synchronized. Redact tokens, user documents,
private keys, and full customer paths from shared logs.

`Logger.minimumLogLevel = 'Warning'` controls output. Node/web support
`Logger.setCustomLogCallback`; the published API explicitly rejects that callback on
React Native. Use native logs (Xcode / adb logcat) there. Native `Logger.exportToFile`
is for a user-authorized support export; don't silently upload it. `smallPeerInfo.metadata`
can label a device for operations, not establish its identity or permissions.

Source: published `@dittolive/ditto@5.2.0` `types/ditto.d.ts`, Logger and SmallPeerInfo.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
