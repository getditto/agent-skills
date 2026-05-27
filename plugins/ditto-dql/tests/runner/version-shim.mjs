// runner/version-shim.mjs
import { createRequire } from "node:module";
import path from "node:path";

export async function loadSdk(version) {
  if (!["4.14.4", "5.0.0"].includes(version)) {
    throw new Error(`Unsupported DITTO_SDK_VERSION: ${version}. Supported: 4.14.4, 5.0.0`);
  }
  const sdkRoot = path.resolve(import.meta.dirname, "..", "sdks", `v${version}`);
  const requireFromSdk = createRequire(path.join(sdkRoot, "package.json"));
  const sdkPath = requireFromSdk.resolve("@dittolive/ditto");
  return await import(sdkPath);
}
