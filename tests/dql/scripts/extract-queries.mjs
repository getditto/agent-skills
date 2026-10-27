// scripts/extract-queries.mjs
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

// tests/dql/scripts -> <repo>/skills/write-dql
const SKILL_ROOT = path.resolve(import.meta.dirname, "..", "..", "..", "skills", "write-dql");
// Repo root, for repo-relative source paths in the catalog
const REPO_ROOT = path.resolve(SKILL_ROOT, "..", "..");
const OUT = path.resolve(import.meta.dirname, "..", "catalog", "catalog.json");
const IGNORE = path.resolve(import.meta.dirname, "..", "catalog", "ignore.json");
const BLOCKS = path.resolve(import.meta.dirname, "..", "catalog", "blocks.json");
const GOLDENS = path.resolve(import.meta.dirname, "..", "catalog", "goldens.json");

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return walk(p);
    if (e.isFile() && p.endsWith(".md")) return [p];
    return [];
  });
}

function extract(file) {
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split("\n");
  const entries = [];
  let currentHeading = "";
  let nearbyAvailableIn = null;
  let inSqlBlock = false;
  let sqlBuf = [];
  let sqlStart = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (/^#{1,6}\s/.test(line)) {
      currentHeading = line.trim();
      // A version marker only applies within its own section; reset on heading change.
      nearbyAvailableIn = null;
    }
    const availMatch = line.match(/Available in:.*?(?:SDK\s+)?([\d.]+(?:\.x|\+)?)/i);
    if (availMatch) nearbyAvailableIn = availMatch[1];

    if (!inSqlBlock && /^```sql\s*$/.test(line)) {
      inSqlBlock = true; sqlBuf = []; sqlStart = i + 1; continue;
    }
    if (inSqlBlock && /^```\s*$/.test(line)) {
      inSqlBlock = false;
      const sql = sqlBuf.join("\n").trim();
      // Skip negative examples (search recent lines for "WRONG" / "❌")
      const recentContext = lines.slice(Math.max(0, sqlStart - 6), sqlStart).join("\n");
      const isWrong = /❌|WRONG|do not use|don't use/i.test(recentContext);
      // Skip parameter-only queries (no concrete substitution possible)
      const hasOnlyParams = sql.includes(":") && !sql.match(/=\s*[0-9'"]/);

      entries.push({
        id: null, // assigned below, once per-file occurrence indices are known
        _idKey: normalizeForId(sql),
        source: {
          file: path.relative(REPO_ROOT, file),
          line: sqlStart,
          heading: currentHeading
        },
        query: sql,
        availableIn: inferAvailableIn(nearbyAvailableIn),
        expectError: isWrong,
        _hints: { isWrong, hasOnlyParams }
      });
      continue;
    }
    if (inSqlBlock) sqlBuf.push(line);
  }

  // Assign IDs once the whole file is parsed. The ID is content-addressed on the
  // NORMALIZED sql (see normalizeForId) plus an occurrence index that only
  // disambiguates byte-identical queries within the same file. Deliberately NOT
  // a function of the line number or of comment/whitespace formatting, so that
  // editing prose, reflowing a block, or rewording a `--` comment does not
  // silently re-key the catalog. See "Entry IDs" in tests/dql/README.md.
  const seen = new Map();
  for (const e of entries) {
    const occ = seen.get(e._idKey) ?? 0;
    seen.set(e._idKey, occ + 1);
    e.id = hashId(file, e._idKey, occ);
    delete e._idKey;
  }
  return entries;
}

/**
 * Canonical form of a SQL block for ID purposes: `--` comments removed (quote-
 * and backtick-aware, so a `--` inside a string literal survives) and all
 * whitespace runs collapsed. Two blocks that differ only in comments,
 * indentation or line breaks share an ID; any change to the statement itself
 * mints a new one.
 */
function normalizeForId(sql) {
  let out = "";
  let inStr = false, inTick = false;
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i];
    if (!inTick && c === "'") inStr = !inStr;
    else if (!inStr && c === "`") inTick = !inTick;
    if (!inStr && !inTick && c === "-" && sql[i + 1] === "-") {
      while (i < sql.length && sql[i] !== "\n") i++;
      out += " ";
      continue;
    }
    out += c;
  }
  return out.replace(/\s+/g, " ").trim();
}

function hashId(file, normalizedSql, occurrence) {
  // Hash the repo-relative path so IDs are stable across machines and repo moves.
  const rel = path.relative(REPO_ROOT, file);
  const h = crypto.createHash("sha1")
    .update(`${rel}\0${normalizedSql}\0${occurrence}`)
    .digest("hex").slice(0, 8);
  const slug = path.basename(file, ".md").replace(/[^a-z0-9]/gi, "_");
  return `sk_${slug}_${h}`;
}

function inferAvailableIn(tag) {
  if (!tag) return ["4.14.x", "5.0.x", "5.1.x"];
  if (/^5\.1/.test(tag)) return ["5.1.x"];              // "5.1+"
  if (/^5\.0/.test(tag)) return ["5.0.x", "5.1.x"];     // "5.0+" — 5.1 is a superset
  if (/^5\./.test(tag))  return ["5.0.x", "5.1.x"];
  if (/^4\./.test(tag))   return ["4.14.x", "5.0.x", "5.1.x"];  // 4.x features generally carry forward to 5.x unless explicitly removed
  if (/^4\.x/i.test(tag)) return ["4.14.x"];            // "v4.x only" markers
  return ["4.14.x", "5.0.x", "5.1.x"];
}

const ignore = fs.existsSync(IGNORE) ? new Set(JSON.parse(fs.readFileSync(IGNORE, "utf8"))) : new Set();
// Stash the curated catalog's captured assertions before we overwrite it with
// the raw draft. Extraction is destructive, so without this every `npm run
// extract` would silently discard the `expect` goldens (rowCount / firstRow)
// and downgrade the harness to a smoke test. Re-attached by curate-catalog.mjs.
// This only works because ids are content-addressed and survive doc edits.
if (fs.existsSync(OUT)) {
  const prior = JSON.parse(fs.readFileSync(OUT, "utf8"));
  const goldens = Object.fromEntries(
    prior.filter(e => e && e.expect !== undefined).map(e => [e.id, e.expect]));
  const merged = fs.existsSync(GOLDENS)
    ? { ...JSON.parse(fs.readFileSync(GOLDENS, "utf8")), ...goldens }
    : goldens;
  if (Object.keys(merged).length) fs.writeFileSync(GOLDENS, JSON.stringify(merged, null, 2));
}

const everything = walk(SKILL_ROOT).flatMap(extract);
const all = everything.filter(e => !ignore.has(e.id));
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(all, null, 2));

// Full inventory of every sql block, including the ones filtered out above.
// Curation uses this to prune ignore ids whose block no longer exists — without
// it, a deleted or edited block's id would be carried forward forever.
fs.writeFileSync(BLOCKS, JSON.stringify(
  everything.map(e => ({ id: e.id, file: e.source.file, line: e.source.line })), null, 2));

console.log(`Extracted ${all.length} queries → ${OUT}`);
console.log(`  Block inventory (${everything.length} total) → ${BLOCKS}`);
console.log(`  Negative examples (expectError=true): ${all.filter(e => e.expectError).length}`);
console.log(`  Param-only (likely non-runnable):     ${all.filter(e => e._hints.hasOnlyParams).length}`);
