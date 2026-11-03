// Two local peers: each document fits, but merging their distinct fields exceeds
// the default hard limit. This tests document size, not the size of one delta.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { loadSdk } from './version-shim.mjs';
import { loadEnv } from '../../lib/load-env.mjs';

loadEnv();
assert.ok(process.env.DITTO_OFFLINE_LICENSE, 'DITTO_OFFLINE_LICENSE is required');
const sdk = await loadSdk('5.2.0');
await sdk.init();
assert.equal(sdk.Ditto.VERSION, '5.2.0');
const databaseID = process.env.DITTO_DATABASE_ID || '00000000-1111-2222-3333-444444444444';
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ditto-sync-degradation-'));
const peers = [];
const subscriptions = [];
const collection = 'merge_limit_checks';
const fields = ['left', 'right'];
const rows = async (ditto, query) => (await ditto.store.execute(query)).items.map(item => item.value);

async function availablePort() {
  const listener = net.createServer();
  await new Promise((resolve, reject) => {
    listener.once('error', reject);
    listener.listen(0, '127.0.0.1', resolve);
  });
  const port = listener.address().port;
  await new Promise((resolve, reject) => listener.close(error => error ? reject(error) : resolve()));
  return port;
}

async function until(predicate, label) {
  const deadline = performance.now() + 30_000;
  while (performance.now() < deadline) {
    if (await predicate()) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for ${label}`);
}

try {
  const port = await availablePort();
  for (const [index, field] of fields.entries()) {
    const peer = await sdk.Ditto.open(new sdk.DittoConfig({
      databaseID, connect: { mode: 'smallPeersOnly' },
      persistenceDirectory: path.join(directory, String(index)),
    }));
    peers.push(peer);
    peer.setOfflineOnlyLicenseToken(process.env.DITTO_OFFLINE_LICENSE);
    peer.updateTransportConfig(config => {
      config.setAllPeerToPeerEnabled(false);
      config.listen.tcp.isEnabled = index === 0;
      config.listen.tcp.interfaceIP = '127.0.0.1';
      config.listen.tcp.port = port;
      config.connect.tcpServers = index === 1 ? [`127.0.0.1:${port}`] : [];
      config.connect.websocketURLs = [];
    });
    const limit = await rows(peer, 'SHOW document_size_hard_limit_bytes');
    assert.equal(limit[0].document_size_hard_limit_bytes, 5 * 1024 * 1024);
    await peer.store.execute(`INSERT INTO ${collection} DOCUMENTS (:doc)`, {
      doc: { _id: 'large', [field]: 'a'.repeat(3 * 1024 * 1024) },
    });
    const initial = (await rows(peer, `SELECT * FROM ${collection}`))[0];
    assert.equal(initial[field].length, 3 * 1024 * 1024);
    assert.ok(!Object.hasOwn(initial, fields[1 - index]));
    assert.deepEqual(await rows(peer, 'SELECT * FROM system:sync_degradations'), []);
    subscriptions.push(peer.sync.registerSubscription(`SELECT * FROM ${collection}`));
  }
  for (const peer of peers) peer.sync.start();
  await peers[0].store.execute(`INSERT INTO ${collection} DOCUMENTS ({'_id':'control','n':1})`);
  await until(async () => (await rows(peers[1], `SELECT * FROM ${collection} WHERE _id='control'`))[0]?.n === 1,
    'initial control document');
  for (const [index, peer] of peers.entries()) {
    await until(async () => (await rows(peer, 'SELECT * FROM system:sync_degradations')).some(entry =>
      entry.collection === collection && entry.document_id === 'large' && entry.reason === 'documentTooBig'),
    `the intended document's degradation on peer ${index}`);
    const local = (await rows(peer, `SELECT * FROM ${collection} WHERE _id='large'`))[0];
    assert.equal(local[fields[index]].length, 3 * 1024 * 1024);
    assert.ok(!Object.hasOwn(local, fields[1 - index]), 'Over-limit incoming field must be dropped');
  }
  await peers[0].store.execute(`UPDATE ${collection} SET n=2 WHERE _id='control'`);
  await until(async () => (await rows(peers[1], `SELECT * FROM ${collection} WHERE _id='control'`))[0]?.n === 2,
    'continued independent-document replication after degradation');
  console.log('PASS 5.2.0: both peers reject over-limit document merges; other documents continue syncing');
} finally {
  const cleanup = await Promise.allSettled(subscriptions.map(async subscription => subscription.cancel()));
  cleanup.push(...await Promise.allSettled(peers.map(async peer => { peer.sync.stop(); await peer.close(); })));
  fs.rmSync(directory, { recursive: true, force: true });
  const failures = cleanup.filter(result => result.status === 'rejected').map(result => result.reason);
  if (failures.length) throw new AggregateError(failures, 'Peer cleanup failed');
}
