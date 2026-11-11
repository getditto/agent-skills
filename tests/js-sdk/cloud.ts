// Optional, explicit live authentication check; does not write customer documents.
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Authenticator, Logger, init } from '@dittolive/ditto';
import { createRuntime } from './.generated/runtime';
// @ts-expect-error Repository helper is JavaScript.
import { loadEnv } from '../lib/load-env.mjs';
loadEnv();
const databaseID = process.env.DITTO_DATABASE_ID;
const url = process.env.DITTO_URL;
const token = process.env.DITTO_TOKEN;
assert.ok(databaseID && url && token, 'Set DITTO_DATABASE_ID, DITTO_URL and DITTO_TOKEN');
await init();
Logger.enabled = false;
const folder = await mkdtemp(join(tmpdir(), 'ditto-js-auth-'));
let failed = false;
const runtime = createRuntime({ databaseID, persistenceDirectory: folder,
  connection: { mode: 'server', url, provider: Authenticator.DEVELOPMENT_PROVIDER, getToken: async () => token },
  onAuthError: () => { failed = true; },
});
try {
  const ditto = await runtime.start();
  const deadline = Date.now() + 30000;
  while (!ditto.auth.status.isAuthenticated) {
    assert.ok(!failed, 'Authentication failed (credential details redacted)');
    assert.ok(Date.now() < deadline, 'Authentication timed out');
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  console.log('Live server authentication passed; no documents written');
} finally { await runtime.close(); await rm(folder, { recursive: true, force: true }); }
