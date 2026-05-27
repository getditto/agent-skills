// scripts/report.mjs
import fs from "node:fs";
import path from "node:path";

const dir = path.resolve(import.meta.dirname, "..", "results");
if (!fs.existsSync(dir)) { console.error("No results/ directory yet"); process.exit(1); }
const files = fs.readdirSync(dir).filter(f => /^[0-9]+\.[0-9]+\.[0-9]+\.json$/.test(f)).sort();
if (!files.length) { console.error("No version-result files in results/"); process.exit(1); }

const byId = {};
for (const f of files) {
  const ver = f.replace(/\.json$/, "");
  const results = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
  for (const r of results) {
    byId[r.id] ??= { id: r.id };
    byId[r.id][ver] = r.status;
    byId[r.id][`${ver}_msg`] = r.message;
  }
}

const versions = files.map(f => f.replace(/\.json$/, ""));
const entries = Object.values(byId).sort((a, b) => a.id.localeCompare(b.id));

// Per-version summary
console.log("=".repeat(120));
console.log("DQL Skill Test Results — Summary");
console.log("=".repeat(120));
const allStatuses = ["PASS", "PASS-AS-EXPECTED-FAIL", "PASS-UNEXPECTED-ON-VERSION", "FAIL", "FAIL-ASSERTION", "FAIL-UNEXPECTED-PASS"];
const headers = ["Status"].concat(versions);
console.log(headers.map((h, i) => h.padEnd(i === 0 ? 32 : 14)).join(""));
console.log("-".repeat(120));
for (const status of allStatuses) {
  const row = [status];
  for (const v of versions) {
    row.push(String(entries.filter(e => e[v] === status).length));
  }
  console.log(row.map((c, i) => c.padEnd(i === 0 ? 32 : 14)).join(""));
}
console.log("-".repeat(120));
console.log(`Total entries: ${entries.length}`);

// Failures detail (only entries with at least one FAIL or UNEXPECTED-PASS status)
const failing = entries.filter(e => versions.some(v => e[v]?.startsWith("FAIL") || e[v] === "PASS-UNEXPECTED-ON-VERSION"));
if (failing.length) {
  console.log("\n" + "=".repeat(120));
  console.log(`Failing entries: ${failing.length}`);
  console.log("=".repeat(120));
  for (const e of failing) {
    console.log(`\n${e.id}`);
    for (const v of versions) {
      if (e[v]) {
        const msg = e[`${v}_msg`];
        console.log(`  ${v.padEnd(10)} ${e[v].padEnd(28)}${msg ? "  " + msg.slice(0, 80) : ""}`);
      }
    }
  }
}

// Full table (optional, only if --full)
if (process.argv.includes("--full")) {
  console.log("\n" + "=".repeat(120));
  console.log("Full per-entry results");
  console.log("=".repeat(120));
  for (const e of entries) {
    const cols = versions.map(v => (e[v] || "—").padEnd(28));
    console.log(`${e.id.padEnd(50)}  ${cols.join("")}`);
  }
}

// Write JSON export for CI artifact
const exportPath = path.resolve(dir, "report.json");
fs.writeFileSync(exportPath, JSON.stringify({ versions, entries }, null, 2));
console.log(`\nJSON export → ${exportPath}`);

const hasFailures = failing.length > 0;
process.exit(hasFailures ? 1 : 0);
