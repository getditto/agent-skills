#!/usr/bin/env node
// Deterministically score a model's data-modeling review against a case's
// expected findings. No model-in-the-loop judging.
//
// Scoring rule: a finding is HIT when every one of its "groups" has at least
// one regex match (case-insensitive, dot matches newline) in the response.
// An anti-finding is PENALIZED when it matches.
//
// Usage:
//   node runner/score.mjs                      # score results/*.response.md
//   node runner/score.mjs --case pos-order     # single case
//   node runner/score.mjs --min 0.75           # recall threshold (default)
//
// Exit code 0 = every scored case meets --min recall and has no anti-finding
// hits; 1 otherwise.

import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const casesDir = join(here, '..', 'cases');
const resultsDir = join(here, '..', 'results');

const args = process.argv.slice(2);
const caseFilter = args.includes('--case') ? args[args.indexOf('--case') + 1] : null;
const minRecall = args.includes('--min')
  ? parseFloat(args[args.indexOf('--min') + 1])
  : 0.75;

if (Number.isNaN(minRecall) || minRecall < 0 || minRecall > 1) {
  console.error(`Invalid --min value (expected 0..1): ${args[args.indexOf('--min') + 1]}`);
  process.exit(2);
}

function groupsHit(response, groups) {
  return groups.every((alternatives) =>
    alternatives.some((alt) => new RegExp(alt, 'is').test(response))
  );
}

const cases = (await readdir(casesDir, { withFileTypes: true }))
  .filter((d) => d.isDirectory())
  .map((d) => d.name)
  .filter((name) => !caseFilter || name === caseFilter)
  .sort();

let failures = 0;
let scored = 0;
let skipped = 0;

if (cases.length === 0) {
  console.error('No cases found' + (caseFilter ? ` matching "${caseFilter}"` : ''));
  process.exit(1);
}

for (const name of cases) {
  const expected = JSON.parse(
    await readFile(join(casesDir, name, 'expected.json'), 'utf8')
  );
  let response;
  try {
    response = await readFile(join(resultsDir, `${name}.response.md`), 'utf8');
  } catch {
    console.log(`SKIP  ${name.padEnd(14)} no response file (run runner/run.mjs first)`);
    skipped += 1;
    continue;
  }
  scored += 1;

  const rows = [];
  let hits = 0;
  for (const f of expected.findings) {
    const hit = groupsHit(response, f.groups);
    if (hit) hits += 1;
    rows.push(`  ${hit ? 'HIT ' : 'MISS'}  [${f.severity}] ${f.id} @ ${f.path}`);
  }
  const recall = expected.findings.length ? hits / expected.findings.length : 1;

  const anti = [];
  for (const a of expected.antiFindings ?? []) {
    if (groupsHit(response, a.groups)) anti.push(a.desc);
  }

  const pass = recall >= minRecall && anti.length === 0;
  if (!pass) failures += 1;

  console.log(
    `${pass ? 'PASS' : 'FAIL'}  ${name.padEnd(14)} recall ${(recall * 100).toFixed(0)}% (${hits}/${expected.findings.length})` +
      (anti.length ? `  anti-findings hit: ${anti.length}` : '')
  );
  for (const row of rows) console.log(row);
  for (const a of anti) console.log(`  PENALTY anti-finding: ${a}`);
}

if (scored === 0) {
  console.error('\nNothing scored — no response files found under results/. Run runner/run.mjs first.');
  process.exit(1);
}
console.log(`\nscored ${scored} case(s), skipped ${skipped}, failed ${failures}`);
process.exit(failures ? 1 : 0);
