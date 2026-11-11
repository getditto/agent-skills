# Preview and platform boundaries

## CAP-20 Preview and platform-specific APIs

Do not infer JavaScript support from another language's version number. The published
5.2.0 JS declarations used by this skill do not expose the Swift/Kotlin Data Streams
API; do not generate it for Node, web, or RN. Unreleased source may contain new bindings.
Use the installed release's documented feature gate before adopting a preview API.

Browser cannot use native Bluetooth, AWDL, Wi-Fi Aware or arbitrary TCP listeners;
WebSockets are its sync transport. Expo Go cannot load Ditto's native module. Expo web
must use the browser setup, not the native configuration recipe. React Native macOS is
a separate CLI target; the Expo iOS/Android starter does not claim macOS support.

Source: `@dittolive/ditto@5.2.0` `types/ditto.d.ts` export surface;
<https://docs.ditto.live/sdk/latest/compatibility/js-web>,
<https://docs.ditto.live/sdk/latest/install-guides/react-native>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
