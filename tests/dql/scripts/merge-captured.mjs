// scripts/merge-captured.mjs
//
// Merges captured rowCount / firstRow values from test runs into
// catalog.json's `expect` fields. Run after:
//   DITTO_SDK_VERSION=5.0.0 node runner/run.mjs --capture-expected
//   DITTO_SDK_VERSION=4.14.4 node runner/run.mjs --capture-expected
// to populate goldens.
//
// Only deterministic goldens are kept:
// - rowCount is set only when every version the entry is availableIn that
//   captured a PASS agrees. (If only one version captured it — the other is
//   expected-fail or unsupported — that single count is used.)
// - firstRow is set only when it is byte-identical across captures AND the
//   query has an ORDER BY (without ORDER BY the first row is arbitrary).
//   EXPLAIN/PROFILE statements never get goldens — plan/timing output is
//   not stable.
//
// Never overwrites hand-curated expectations.

import fs from "node:fs";
import path from "node:path";

const here = import.meta.dirname;
const catalogPath = path.resolve(here, "..", "catalog", "catalog.json");
const cap5 = readJsonIfExists(
  path.resolve(here, "..", "results", "captured-5.0.0.json"),
);
const cap4 = readJsonIfExists(
  path.resolve(here, "..", "results", "captured-4.14.4.json"),
);
const cap51 = readJsonIfExists(
  path.resolve(here, "..", "results", "captured-5.1.0.json"),
);

function readJsonIfExists(p) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
}

function isExplainOrProfile(query) {
  return /^\s*(EXPLAIN|PROFILE)\b/i.test(query) || /\/\*\+[^]*#profile/.test(query);
}

function hasOrderBy(query) {
  return /\bORDER\s+BY\b/i.test(query);
}

const cat = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const overrides = (() => {
  try { return JSON.parse(fs.readFileSync(path.resolve(here, "..", "catalog", "overrides.json"), "utf8")); } catch { return {}; }
})();
const skipGoldens = new Set(Object.keys(overrides.skipGoldens || {}));
let updatedRowCount = 0;
let updatedFirstRow = 0;
let totalCovered = 0;
for (const entry of cat) {
  const versions = entry.availableIn || [];
  const caps = [];
  if (cap5 && versions.includes("5.0.x") && cap5[entry.id]) caps.push(cap5[entry.id]);
  if (cap4 && versions.includes("4.14.x") && cap4[entry.id]) caps.push(cap4[entry.id]);
  if (cap51 && versions.includes("5.1.x") && cap51[entry.id]) caps.push(cap51[entry.id]);
  if (caps.length === 0 || skipGoldens.has(entry.id)) continue;
  totalCovered++;

  entry.expect = entry.expect || {};

  // rowCount: only if all captures agree.
  // An availableIn version missing from the captures means the entry errored
  // there (no PASS) — treat as disagreement, don't write a golden.
  const coveredVersions = [cap4 && cap4[entry.id] ? "4.14.x" : null,
                           cap5 && cap5[entry.id] ? "5.0.x" : null,
                           cap51 && cap51[entry.id] ? "5.1.x" : null]
    .filter(Boolean);
  const missing = versions.filter((v) => !coveredVersions.includes(v));
  const rowCounts = new Set(caps.map((c) => c.rowCount));
  if (entry.expect.rowCount === undefined && missing.length === 0 && rowCounts.size === 1) {
    entry.expect.rowCount = caps[0].rowCount;
    updatedRowCount++;
  }

  // firstRow: only if identical across versions, query is ordered,
  // and output shape is stable (not EXPLAIN/PROFILE).
  const firstRows = new Set(caps.map((c) => JSON.stringify(c.firstRow)));
  if (
    entry.expect.firstRow === undefined &&
    firstRows.size === 1 &&
    caps[0].firstRow &&
    hasOrderBy(entry.query) &&
    !isExplainOrProfile(entry.query)
  ) {
    entry.expect.firstRow = caps[0].firstRow;
    updatedFirstRow++;
  }
}
fs.writeFileSync(catalogPath, JSON.stringify(cat, null, 2));
console.log(
  `Merged captures into catalog: ${totalCovered} entries had captures, ` +
    `${updatedRowCount} got rowCount, ${updatedFirstRow} got firstRow`,
);
