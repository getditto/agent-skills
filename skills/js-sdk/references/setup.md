# Setup

## CAP-01 Prerequisites, toolchain, package install

Install `@dittolive/ditto` at an exact tested version and commit the lockfile. Start
new examples on 5.2.0; preserve an existing application's version until migration is
requested. TypeScript types are bundled; do not install a separate `@types` package.
Call `await init()` before opening. The package resolves a native Node binding,
browser WASM, or React Native JSI binding through its package entry points.
Do not force the Node entry point into Metro or a browser bundle.

Choose the platform skill: [Node](../../js-node/SKILL.md),
[web/React](../../js-web/SKILL.md), [React Native](../../js-react-native/SKILL.md),
[Expo](../../js-expo/SKILL.md). They are included together in the `ditto-js` plugin.
The separately published `@dittolive/react-native` is an old alpha, not this SDK.

## CAP-02 Platform permissions, entitlements, build config

Native declarations are maintained once in [native-app-config](../../native-app-config/SKILL.md).
Web has no native plist/manifest. Node deployments need the correct `.node` binary.
For native development, take the higher of the framework and Ditto toolchain floors;
the published RN compatibility page's older minimum is not an Expo compatibility matrix.

Sources: <https://docs.ditto.live/sdk/latest/install-guides/js>,
<https://docs.ditto.live/sdk/latest/install-guides/react-native>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
