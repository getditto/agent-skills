import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { Ditto, DittoConfig, DittoError, Logger, init } from '@dittolive/ditto';
import { createRuntime } from '../.generated/runtime';
import { decodeTask, saveTask, setTaskDone, deleteTask } from '../.generated/tasks';
// @ts-expect-error Repository helper is JavaScript.
import { loadEnv } from '../../lib/load-env.mjs';
loadEnv();
const license = process.env.DITTO_OFFLINE_LICENSE;
assert.ok(license, 'Set DITTO_OFFLINE_LICENSE in .env or the environment');
const databaseID = process.env.DITTO_DATABASE_ID ?? '00000000-0000-4000-8000-000000000001';
await init();
Logger.enabled = false;

export async function eventually(predicate: () => boolean | Promise<boolean>) {
  const end = Date.now() + 10000;
  while (!await predicate()) {
    if (Date.now() > end) throw new Error('Condition timed out');
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

test('published operations: observe, CRUD, parameters, transaction, index, attachment, eviction, reopen', async () => {
  const path = await mkdtemp(join(tmpdir(), 'ditto-js-skill-'));
  const runtime = createRuntime({ databaseID, persistenceDirectory: path,
    connection: { mode: 'smallPeersOnly', offlineLicense: license }, onAuthError: () => {} });
  let ditto: Ditto | undefined;
  try {
    assert.equal(runtime.start(), runtime.start(), 'concurrent start shares one promise');
    ditto = await runtime.start();
    const instance = ditto;
    const subscription = ditto.sync.registerSubscription('SELECT * FROM tasks');
    const events: string[][] = [];
    const observer = ditto.store.registerObserver('SELECT * FROM tasks', (result) => {
      events.push(result.items.map((item) => decodeTask(item.value).title));
    });
    const title = "Don't interpolate :this OR 1 = 1";
    const write = await saveTask(ditto, { _id: 'one', title, done: false });
    assert.ok(write.commitID !== null);
    await eventually(() => events.some((rows) => rows.includes(title)));
    await setTaskDone(ditto, 'one', true);
    assert.equal(decodeTask((await ditto.store.execute('SELECT * FROM tasks')).items[0].value).done, true);
    await ditto.store.transaction(async (tx) => {
      await tx.execute('INSERT INTO tasks DOCUMENTS (:task)', { task: { _id: 'rollback', title: 'No', done: false } });
      return 'rollback';
    });
    assert.equal((await ditto.store.execute("SELECT * FROM tasks WHERE _id = 'rollback'")).items.length, 0);
    await ditto.store.execute('CREATE INDEX IF NOT EXISTS tasks_title ON tasks (title)');
    assert.equal((await ditto.store.execute('SELECT * FROM tasks WHERE title = :title', { title })).items.length, 1);
    await assert.rejects(ditto.store.execute('THIS IS NOT DQL'), DittoError);
    const attachment = await ditto.store.newAttachment(new Uint8Array([1, 2, 3]), { kind: 'test' });
    await ditto.store.execute('INSERT INTO files DOCUMENTS (:file)', { file: { _id: 'file', attachment } });
    const token = (await ditto.store.execute('SELECT * FROM files')).items[0].value.attachment;
    const fetched = await ditto.store.fetchAttachment(token);
    assert.ok(fetched);
    assert.deepEqual(Array.from(await fetched.data()), [1, 2, 3]);
    assert.ok(ditto.presence.graph.localPeer);
    observer.cancel(); subscription.cancel();
    assert.equal(ditto.store.observers.length, 0);
    assert.equal(ditto.sync.subscriptions.length, 0);
    await deleteTask(ditto, 'one');
    await saveTask(ditto, { _id: 'persist', title: 'Persists', done: false });
    await ditto.store.execute('EVICT FROM files WHERE _id = :id', { id: 'file' });
    assert.equal((await ditto.store.execute('SELECT * FROM files')).items.length, 0);
    await runtime.close();
    assert.ok(instance.isClosed);
    ditto = await Ditto.open(new DittoConfig(databaseID, { mode: 'smallPeersOnly' }, path));
    assert.equal(decodeTask((await ditto.store.execute('SELECT * FROM tasks')).items[0].value).title, 'Persists');
  } finally {
    await runtime.close(); await ditto?.close(); await rm(path, { recursive: true, force: true });
  }
});

test('closing during async startup releases the directory and rejects later starts', async () => {
  const path = await mkdtemp(join(tmpdir(), 'ditto-close-'));
  const runtime = createRuntime({ databaseID, persistenceDirectory: path,
    connection: { mode: 'smallPeersOnly', offlineLicense: license }, onAuthError: () => {} });
  try {
    const opening = runtime.start();
    const rejected = assert.rejects(opening, /closed during startup/);
    await runtime.close(); await rejected;
    await assert.rejects(runtime.start(), /closed/);
    const next = await Ditto.open(new DittoConfig(databaseID, { mode: 'smallPeersOnly' }, path));
    await next.close();
  } finally { await runtime.close(); await rm(path, { recursive: true, force: true }); }
});

test('server mode requires the expiration handler before sync', async () => {
  const path = await mkdtemp(join(tmpdir(), 'ditto-auth-'));
  const ditto = await Ditto.open(new DittoConfig(databaseID, { mode: 'server', url: 'wss://localhost:1' }, path));
  try {
    assert.throws(() => ditto.sync.start(), (error: unknown) => error instanceof DittoError && error.code === 'authentication/expiration-handler-missing');
  } finally { await ditto.close(); await rm(path, { recursive: true, force: true }); }
});

test('two real peers synchronize over explicit loopback TCP', async () => {
  const socket = createServer();
  await new Promise<void>((resolve) => socket.listen(0, '127.0.0.1', resolve));
  const address = socket.address();
  assert.ok(address && typeof address !== 'string');
  const port = address.port;
  await new Promise<void>((resolve, reject) => socket.close(error => error ? reject(error) : resolve()));
  const folder = await mkdtemp(join(tmpdir(), 'ditto-peers-'));
  const peers: Ditto[] = [];
  try {
    for (const name of ['a', 'b']) {
      const peer = await Ditto.open(new DittoConfig(databaseID, { mode: 'smallPeersOnly' }, join(folder, name)));
      peers.push(peer);
      peer.setOfflineOnlyLicenseToken(license);
      peer.updateTransportConfig(config => {
        config.peerToPeer.bluetoothLE.isEnabled = false;
        config.peerToPeer.awdl.isEnabled = false;
        config.peerToPeer.wifiAware.isEnabled = false;
        config.peerToPeer.lan.isEnabled = false;
        if (name === 'a') Object.assign(config.listen.tcp, { isEnabled: true, interfaceIP: '127.0.0.1', port });
        else config.connect.tcpServers = [`127.0.0.1:${port}`];
      });
      peer.sync.registerSubscription('SELECT * FROM tasks');
      peer.sync.start();
    }
    await saveTask(peers[0], { _id: 'peer-task', title: 'From peer A', done: false });
    await eventually(async () => (await peers[1].store.execute('SELECT * FROM tasks')).items.some(item => item.value._id === 'peer-task'));
    await setTaskDone(peers[1], 'peer-task', true);
    await eventually(async () => (await peers[0].store.execute("SELECT * FROM tasks WHERE _id = 'peer-task'")).items[0]?.value.done === true);
  } finally {
    for (const peer of peers) await peer.close();
    await rm(folder, { recursive: true, force: true });
  }
});

test('signalNext resumes after an asynchronous consumer finishes', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'ditto-signal-'));
  const ditto = await Ditto.open(new DittoConfig(databaseID, { mode: 'smallPeersOnly' }, folder));
  let signal: (() => unknown) | undefined;
  const events: number[] = [];
  const observer = ditto.store.registerObserverWithSignalNext('SELECT * FROM tasks', (result, next) => {
    events.push(result.items.length);
    signal = next;
  });
  try {
    await eventually(() => events.length === 1);
    await saveTask(ditto, { _id: 'one', title: 'one', done: false });
    assert.deepEqual(events, [0]);
    signal!();
    await eventually(() => events.includes(1));
  } finally { observer.cancel(); await ditto.close(); await rm(folder, { recursive: true, force: true }); }
});
