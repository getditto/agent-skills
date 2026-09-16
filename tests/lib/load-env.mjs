// tests/lib/load-env.mjs
//
// Loads the repo-root `.env` file (gitignored local test config) into
// process.env. Real environment variables — including CI secrets — always
// win: process.loadEnvFile never overrides a variable that is already set.
//
// Call once at runner startup, before reading process.env:
//
//   import { loadEnv } from "../../lib/load-env.mjs";
//   loadEnv();

import fs from "node:fs";
import path from "node:path";

export function loadEnv() {
  const envPath = path.resolve(import.meta.dirname, "..", "..", ".env");
  if (fs.existsSync(envPath)) {
    process.loadEnvFile(envPath);
  }
}
