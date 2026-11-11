import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { init, Ditto, DittoConfig } from '@dittolive/ditto';

if (!process.env.DITTO_OFFLINE_LICENSE) throw new Error('Set DITTO_OFFLINE_LICENSE');
await init();
const directory = await mkdtemp(join(tmpdir(), 'ditto-example-'));
let ditto, observer, subscription, timer;
try {
  ditto = await Ditto.open(new DittoConfig(
    process.env.DITTO_DATABASE_ID ?? '00000000-0000-4000-8000-000000000001',
    { mode: 'smallPeersOnly' }, directory,
  ));
  ditto.setOfflineOnlyLicenseToken(process.env.DITTO_OFFLINE_LICENSE);
  ditto.sync.start();
  subscription = ditto.sync.registerSubscription('SELECT * FROM tasks');
  const observed = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error('Observer timed out')), 10000);
    observer = ditto.store.registerObserver('SELECT * FROM tasks', (result) => {
      if (result.items.some((item) => item.value._id === 'task-1')) resolve();
    });
  });
  // Attach the observer rejection before awaiting a write, avoiding an unhandled timeout.
  await Promise.all([observed, ditto.store.execute(
    'INSERT INTO tasks DOCUMENTS (:task)',
    { task: { _id: 'task-1', title: 'Learn Ditto', done: false } },
  )]);
  const result = await ditto.store.execute('SELECT * FROM tasks');
  console.log(`SDK: ${Ditto.VERSION}; observed: ${result.items[0].value.title}`);
} finally {
  clearTimeout(timer);
  observer?.cancel();
  subscription?.cancel();
  ditto?.sync.stop();
  await ditto?.close();
  await rm(directory, { recursive: true, force: true });
}
