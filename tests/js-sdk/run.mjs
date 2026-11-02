import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
const tests = readdirSync(new URL('./test/', import.meta.url)).filter(f => f.endsWith('.test.ts')).map(f => `test/${f}`);
const result = spawnSync(process.execPath, ['--import', 'tsx', '--test', ...tests], {
  cwd: import.meta.dirname, stdio: 'inherit',
  env: { ...process.env, NO_COLOR: 'true', RUST_LOG: 'off' },
});
process.exit(result.status ?? 1);
