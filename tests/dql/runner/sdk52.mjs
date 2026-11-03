// 5.2.0 regression and general query checks; disposable local stores only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadSdk } from './version-shim.mjs';
import { loadEnv } from '../../lib/load-env.mjs';
loadEnv();
const sdk = await loadSdk('5.2.0');
await sdk.init();
assert.equal(sdk.Ditto.VERSION, '5.2.0');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ditto-520-regressions-'));
const license = process.env.DITTO_OFFLINE_LICENSE;
assert.ok(license, 'DITTO_OFFLINE_LICENSE is required');
let ditto;
try {
  ditto = await sdk.Ditto.open(new sdk.DittoConfig({
    databaseID: process.env.DITTO_DATABASE_ID || '00000000-1111-2222-3333-444444444444',
    connect: { mode: 'smallPeersOnly' }, persistenceDirectory: directory,
    systemParameters: { transports_websocket_so_keepalive_idle_secs: 60 },
  }));
  ditto.setOfflineOnlyLicenseToken(license);
  const exec = query => ditto.store.execute(query);
  const rows = async query => (await exec(query)).items.map(item => item.value);
  assert.equal((await rows('SHOW transports_websocket_so_keepalive_idle_secs'))[0].transports_websocket_so_keepalive_idle_secs, 60);
  for (const mutation of ['DELETE', 'EVICT']) {
    await exec(`INSERT INTO regressions DOCUMENTS ({'_id':'a','n':1}), ({'_id':'b','n':2}), ({'_id':'c','n':3}) ON ID CONFLICT DO UPDATE`);
    await exec(`${mutation} FROM regressions USE IDS 'a', 'c'`);
    assert.deepEqual((await rows('SELECT * FROM regressions')).map(x => x._id), ['b'], `${mutation} must remove exactly the selected IDs`);
  }
  await exec("INSERT INTO ordering DOCUMENTS ({'_id':'a','group':1,'score':2,'payload':'A'}), ({'_id':'b','group':1,'score':9,'payload':'B'}), ({'_id':'c','group':2,'score':5,'payload':'C'})");
  await exec('CREATE INDEX ordering_idx ON ordering (group ASC, score DESC)');
  assert.deepEqual((await rows('SELECT * FROM ordering ORDER BY group ASC, score DESC')).map(x => [x._id,x.payload]), [['b','B'],['a','A'],['c','C']]);
  // General alias coverage: this query also passes on 5.1.0 and has no fetch operator.
  // It does not reproduce the 5.2.0 fix for alias sorting before document fetch.
  assert.deepEqual((await rows('SELECT score AS rank FROM ordering ORDER BY rank DESC')).map(x => x.rank), [9,5,2]);
  assert.deepEqual((await rows('SELECT * FROM ordering WHERE 1 < group')).map(x => x._id), ['c']);
  await exec("INSERT INTO fleets DOCUMENTS ({'_id':'yes','cars':[{'color':'blue','type':'SUV'}]}), ({'_id':'no','cars':[{'color':'blue','type':'sedan'},{'color':'red','type':'SUV'}]})");
  assert.deepEqual((await rows("SELECT * FROM fleets f WHERE ANY car IN f.cars SATISFIES car.color = 'blue' AND car.type = 'SUV' END")).map(x => x._id), ['yes']);
  assert.deepEqual(await rows('SELECT * FROM system:sync_degradations'), []);
  const bundle = await rows('EXECUTE FUNCTION system_request_support_bundle()');
  assert.ok(bundle.length > 0, 'capture must return a result');
  const retained = await rows('SELECT * FROM system:support_bundles');
  assert.ok(retained.length > 0, 'capture must be listed');
  await ditto.close();
  ditto = await sdk.Ditto.open(new sdk.DittoConfig({
    databaseID: process.env.DITTO_DATABASE_ID || '00000000-1111-2222-3333-444444444444',
    connect: { mode: 'smallPeersOnly' }, persistenceDirectory: directory,
    systemParameters: { ngn_data_streams_enabled: false, ngn_sync_enabled: true },
  }));
  ditto.setOfflineOnlyLicenseToken(license);
  assert.throws(() => ditto.sync.start(), /ngn|NGN|configuration/i,
    'NGN sync without NGN streams must fail');
  console.log('PASS 5.2.0: startup parameters, DELETE/EVICT effects, indexes/projections, ANY, diagnostics and support capture');
} finally {
  await ditto?.close();
  fs.rmSync(directory, { recursive: true, force: true });
}
