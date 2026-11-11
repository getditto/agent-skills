import { cpSync, mkdirSync } from 'node:fs';
mkdirSync(new URL('./.generated/', import.meta.url), { recursive: true });
cpSync(new URL('../../skills/js-sdk/assets/', import.meta.url), new URL('./.generated/', import.meta.url), { recursive: true });
cpSync(new URL('./node_modules/@dittolive/ditto/web/ditto.wasm', import.meta.url), new URL('./.generated/ditto.wasm', import.meta.url));
cpSync(new URL('../../skills/native-app-config/assets/android-permissions.ts', import.meta.url), new URL('./.generated/android-permissions.ts', import.meta.url));
