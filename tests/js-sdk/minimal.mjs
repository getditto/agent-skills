import { loadEnv } from '../lib/load-env.mjs';
import { spawnSync } from 'node:child_process';
loadEnv();
const result = spawnSync(process.execPath, ['.generated/minimal-app.mjs'], {
  cwd: import.meta.dirname, encoding: 'utf8',
  env: { ...process.env, NO_COLOR: 'true' }, maxBuffer: 8 * 1024 * 1024,
});
const line = result.stdout?.split('\n').find(line => line.startsWith('SDK: '));
if (result.status !== 0 || !line?.endsWith('; observed: Learn Ditto')) {
  console.error('Minimal program failed. Exit:', result.status);
  // Do not publish SDK debug logs which may contain customer configuration.
  process.exit(1);
}
console.log(line);
