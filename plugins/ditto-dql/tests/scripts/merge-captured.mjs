// scripts/merge-captured.mjs
//
// Merges captured rowCount / firstRow values from a test run into
// catalog.json's `expect` field. Run after a `npm run test:vX --
// --capture-expected` to populate goldens.
//
// Prefers v5 captures over v4 (newer SDK, more stable). Only fills in
// values that aren't already set on the catalog entry — never overwrites
// hand-curated expectations.

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

function readJsonIfExists(p) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return {};
  }
}

const cat = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
let updatedRowCount = 0;
let updatedFirstRow = 0;
let totalCovered = 0;
for (const entry of cat) {
  // Prefer v5 captures over v4
  const cap = cap5[entry.id] || cap4[entry.id];
  if (!cap) continue;
  totalCovered++;
  entry.expect = entry.expect || {};
  if (entry.expect.rowCount === undefined) {
    entry.expect.rowCount = cap.rowCount;
    updatedRowCount++;
  }
  if (!entry.expect.firstRow && cap.firstRow) {
    // Already pre-truncated to first 5 keys by the runner.
    entry.expect.firstRow = cap.firstRow;
    updatedFirstRow++;
  }
}
fs.writeFileSync(catalogPath, JSON.stringify(cat, null, 2));
console.log(
  `Merged captures into catalog: ${totalCovered} entries had captures, ` +
    `${updatedRowCount} got rowCount, ${updatedFirstRow} got firstRow`,
);
