// snippet:start js-web-browser-fixture
import React, { StrictMode, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createRuntime, type DittoRuntime } from '../.generated/runtime';
import { DittoProvider, useDittoQuery } from '../.generated/DittoProvider';
import { decodeTask, saveTask } from '../.generated/tasks';

let runtime: DittoRuntime;
let root: Root;
function Tasks() {
  const [filtered, setFiltered] = useState(false);
  const [invalid, setInvalid] = useState(false);
  const query = invalid ? 'NOT A QUERY' : filtered ? "SELECT * FROM tasks WHERE done = true" : 'SELECT * FROM tasks';
  const state = useDittoQuery(query, decodeTask);
  return <><button onClick={() => setFiltered(!filtered)}>Filter</button>
    <button onClick={() => setInvalid(!invalid)}>Invalid query</button>
    <output>{state.loading ? 'Loading' : state.error ? 'Query failed' : state.rows.map(row => row.title).join(',') || 'Empty'}</output></>;
}

export const fixture = {
  async start(config: { databaseID: string; license: string }) {
    runtime = createRuntime({ databaseID: config.databaseID,
      connection: { mode: 'smallPeersOnly', offlineLicense: config.license },
      initOptions: { webAssemblyModule: '/.generated/ditto.wasm' }, onAuthError: () => {},
    });
    root = createRoot(document.getElementById('root')!);
    this.mount();
    await runtime.start();
  },
  mount() {
    root.render(<StrictMode><DittoProvider runtime={runtime} loading={<p>Opening</p>}
      failure={() => <p>Open failed</p>}><Tasks /></DittoProvider></StrictMode>);
  },
  unmount() { root.render(null); },
  async write() { await saveTask(await runtime.start(), { _id: 'one', title: 'Browser task', done: false }); },
  async counts() {
    const ditto = await runtime.start();
    return { observers: ditto.store.observers.length, subscriptions: ditto.sync.subscriptions.length,
      rows: (await ditto.store.execute('SELECT * FROM tasks')).items.length };
  },
  async close() { root.unmount(); await runtime.close(); },
};
// snippet:end js-web-browser-fixture
Object.assign(window, { fixture });
