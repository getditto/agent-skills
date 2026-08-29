#!/usr/bin/env node
// Feed test cases to a live AI model and capture its data-modeling review.
//
// Usage:
//   DM_MODEL_CMD="claude -p" node runner/run.mjs            # all cases
//   DM_MODEL_CMD="claude -p" node runner/run.mjs --case pos-order
//   node runner/run.mjs --prompts-only                      # just write prompts
//
// DM_MODEL_CMD must be a shell command that reads the prompt from STDIN and
// writes the model's answer to STDOUT (e.g. `claude -p`). Responses land in
// results/<case>.response.md; prompt-only mode lands in results/prompts/.

import { spawn } from 'node:child_process';
import { mkdir, readdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { buildPrompt } from './prompt.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const casesDir = join(here, '..', 'cases');
const resultsDir = join(here, '..', 'results');

const args = process.argv.slice(2);
const promptsOnly = args.includes('--prompts-only');
const caseFilter = args.includes('--case') ? args[args.indexOf('--case') + 1] : null;

function runModel(cmd, prompt) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, { shell: true, stdio: ['pipe', 'pipe', 'inherit'] });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.on('error', reject);
    child.on('close', (code) =>
      code === 0 ? resolve(out) : reject(new Error(`model command exited ${code}`))
    );
    child.stdin.write(prompt);
    child.stdin.end();
  });
}

const cases = (await readdir(casesDir, { withFileTypes: true }))
  .filter((d) => d.isDirectory())
  .map((d) => d.name)
  .filter((name) => !caseFilter || name === caseFilter)
  .sort();

if (cases.length === 0) {
  console.error('No cases found' + (caseFilter ? ` matching "${caseFilter}"` : ''));
  process.exit(1);
}

const modelCmd = process.env.DM_MODEL_CMD;
if (!promptsOnly && !modelCmd) {
  console.error('Set DM_MODEL_CMD (e.g. DM_MODEL_CMD="claude -p") or pass --prompts-only.');
  process.exit(1);
}

const failed = [];

for (const name of cases) {
  const caseDir = join(casesDir, name);
  const { prompt } = await buildPrompt(caseDir);

  if (promptsOnly) {
    const dir = join(resultsDir, 'prompts');
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, `${name}.prompt.md`), prompt);
    console.log(`wrote prompt: results/prompts/${name}.prompt.md`);
    continue;
  }

  console.log(`running case ${name} via "${modelCmd}" ...`);
  try {
    const response = await runModel(modelCmd, prompt);
    await mkdir(resultsDir, { recursive: true });
    const outPath = join(resultsDir, `${name}.response.md`);
    await writeFile(outPath, response);
    console.log(`wrote response: results/${name}.response.md (${response.length} chars)`);
  } catch (err) {
    failed.push(name);
    console.error(`FAILED case ${name}: ${err.message}`);
  }
}

if (failed.length) {
  console.error(`\n${failed.length} case(s) failed: ${failed.join(', ')}`);
  process.exit(1);
}
