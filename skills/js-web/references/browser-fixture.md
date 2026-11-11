# Browser fixture — React and WASM

The React app CI runs in Chromium against real WASM. It uses the shared runtime,
provider and task helpers from the `js-sdk` skill's assets:
[runtime.ts](../../js-sdk/assets/runtime.ts),
[DittoProvider.tsx](../../js-sdk/assets/DittoProvider.tsx) and
[tasks.ts](../../js-sdk/assets/tasks.ts). The fixture imports them from `.generated/`,
where the harness copies the published assets before each run.

The `fixture` object is the test driver: it starts the runtime, mounts and unmounts
the provider, writes a task and counts observers so the test can check teardown. It
is a test shell, not a production app; supply real authentication in an app.

<!-- snippet-file: tests/js-sdk/browser/app.tsx -->
<!-- Generated from tests/js-sdk/browser/app.tsx by scripts/sync-snippets.py. Edit the source, not this block. -->
```tsx
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
Object.assign(window, { fixture });
```
<!-- /snippet -->
