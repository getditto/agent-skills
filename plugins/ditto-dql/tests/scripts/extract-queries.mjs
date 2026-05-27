// scripts/extract-queries.mjs
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const SKILL_ROOT = path.resolve(import.meta.dirname, "..", "..", "skills", "dql");
const OUT = path.resolve(import.meta.dirname, "..", "catalog", "catalog.json");
const IGNORE = path.resolve(import.meta.dirname, "..", "catalog", "ignore.json");

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

    if (/^#{1,6}\s/.test(line)) currentHeading = line.trim();
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
        id: hashId(file, sqlStart, sql),
        source: {
          file: path.relative(path.join(SKILL_ROOT, "..", "..", "..", ".."), file),
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
  return entries;
}

function hashId(file, line, sql) {
  const h = crypto.createHash("sha1").update(`${file}:${line}:${sql}`).digest("hex").slice(0, 8);
  const slug = path.basename(file, ".md").replace(/[^a-z0-9]/gi, "_");
  return `sk_${slug}_${h}`;
}

function inferAvailableIn(tag) {
  if (!tag) return ["4.14.x", "5.0.x"];
  if (/^5\.0/.test(tag)) return ["5.0.x"];
  if (/^4\./.test(tag))   return ["4.14.x", "5.0.x"];   // 4.x features generally work in 5.0 too unless explicitly removed
  if (/^4\.x/i.test(tag)) return ["4.14.x"];            // "v4.x only" markers
  return ["4.14.x", "5.0.x"];
}

const ignore = fs.existsSync(IGNORE) ? new Set(JSON.parse(fs.readFileSync(IGNORE, "utf8"))) : new Set();
const all = walk(SKILL_ROOT).flatMap(extract).filter(e => !ignore.has(e.id));
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(all, null, 2));
console.log(`Extracted ${all.length} queries → ${OUT}`);
console.log(`  Negative examples (expectError=true): ${all.filter(e => e.expectError).length}`);
console.log(`  Param-only (likely non-runnable):     ${all.filter(e => e._hints.hasOnlyParams).length}`);
