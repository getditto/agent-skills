// scripts/curate-catalog.mjs
//
// Mechanical curation pass over the auto-extracted catalog.json:
//
//   Rule A: Multi-statement blocks -> split into `query` + postQueries.
//   Rule B: hasOnlyParams           -> ignore, unless we can substitute concrete values.
//   Rule C: isWrong                 -> keep, expectError stays true.
//   Rule D: INSERT entries          -> add postQueries that EVICT the inserted id(s).
//   Rule E: UPDATE/EVICT/TOMBSTONE  -> add preQueries that INSERT the target doc.
//   Rule F: Strip `_hints` from final output.
//
// This is mechanical only -- assertion authoring happens in Task 11.

import fs from "node:fs";
import path from "node:path";

const TESTS_DIR  = path.resolve(import.meta.dirname, "..");
const CATALOG    = path.join(TESTS_DIR, "catalog", "catalog.json");
const IGNORE     = path.join(TESTS_DIR, "catalog", "ignore.json");

const SEED_ID    = "573a1390f29313caabcd4135"; // real _id from movies-pedagogical.ndjson (for SELECT-only)
const SYNTH_ID   = "test_seed_id";              // synthetic id we seed+evict for mutation tests

const RAW_CATALOG = JSON.parse(fs.readFileSync(CATALOG, "utf8"));
const PRIOR_IGNORE = new Set(JSON.parse(fs.readFileSync(IGNORE, "utf8")));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TOP_LEVEL_KEYWORDS = [
  "SELECT", "INSERT", "UPDATE", "EVICT", "TOMBSTONE", "DELETE",
  "CREATE", "DROP", "ALTER", "SHOW", "EXPLAIN", "MATCH", "PROFILE",
  "SYNC", // SYNC CONTEXT (...) SELECT ...
];

/** Strip inline `-- comments` from a single line. */
function stripLineComment(line) {
  // Naively chop everything after `--`. DQL has no `'--'` style string we
  // need to worry about across the catalog.
  const i = line.indexOf("--");
  return i === -1 ? line : line.slice(0, i);
}

/**
 * Returns the first uppercase keyword on the line, ignoring leading whitespace
 * and `/*+ ... *\/` planner-hint blocks. Returns null if line is empty/comment-only.
 */
function leadingKeyword(line) {
  const stripped = stripLineComment(line).trim();
  if (!stripped) return null;
  if (stripped.startsWith("/*")) return null;
  // First word, alphanumeric and underscore only.
  const m = stripped.match(/^([A-Za-z_]+)\b/);
  if (!m) return null;
  return m[1].toUpperCase();
}

/** Is `kw` a keyword that begins a top-level DQL statement? */
function isTopLevelKeyword(kw) {
  return kw !== null && TOP_LEVEL_KEYWORDS.includes(kw);
}

/**
 * Split a (possibly) multi-statement query into an array of statement strings.
 * Heuristic:
 *   - If a line whose first uppercase token is a TOP_LEVEL_KEYWORD comes after
 *     we've already accumulated at least one such line, treat it as a new
 *     statement boundary.
 *   - Trailing semicolons are preserved on each statement.
 *   - Pure comment / blank / `/*+ ... *\/` lines are attached to the next
 *     real statement (they're parsing hints or doc context).
 */
function splitStatements(rawQuery) {
  const lines = rawQuery.split("\n");
  /** @type {Array<{lines: string[]}>} */
  const stmts = [];
  let current = null;
  let seenTopKw = false;
  let depth = 0; // paren nesting depth — keywords inside `( … )` are not statement boundaries

  for (const line of lines) {
    const kw = leadingKeyword(line);

    // New top-level statement boundary? Only at depth 0, so that (e.g.)
    // `SELECT ... WHERE x IN (SELECT ...)` is not split at the subquery.
    if (depth === 0 && isTopLevelKeyword(kw) && seenTopKw) {
      // Look back at `current` -- if it ends with `;`, close cleanly.
      stmts.push(current);
      current = { lines: [line] };
      // Reset seenTopKw for this new statement (will be set immediately after).
      seenTopKw = true;
      continue;
    }

    if (!current) current = { lines: [] };
    current.lines.push(line);
    if (isTopLevelKeyword(kw)) seenTopKw = true;
    // Track paren nesting, ignoring `-- comments` (string literals with
    // unbalanced parens are not a pattern this catalog contains).
    const code = stripLineComment(line);
    for (const ch of code) {
      if (ch === "(") depth++;
      else if (ch === ")") depth = Math.max(0, depth - 1);
    }
  }
  if (current) stmts.push(current);

  return stmts
    .map(s => s.lines.join("\n").trim())
    .filter(s => s.length > 0);
}

/** Strip both leading `--` lines and leading blank lines. */
function stripLeadingComments(stmt) {
  const lines = stmt.split("\n");
  let i = 0;
  while (i < lines.length) {
    const t = lines[i].trim();
    if (t === "" || t.startsWith("--")) { i++; continue; }
    break;
  }
  return lines.slice(i).join("\n");
}

/**
 * Remove a trailing statement terminator (`;`) after trimming.
 * `store.execute` takes exactly one DQL statement with no terminator —
 * a source-verbatim `;` fails with "Unexpected token ;".
 */
function stripTerminator(stmt) {
  // Strip `-- comments` per line (a comment may share the line with the `;`),
  // then drop the trailing `;` itself. Line-based, not a single regex: avoids
  // catastrophic backtracking (CodeQL js/redos).
  const lines = stmt.trim().split("\n");
  const stripped = lines.map(stripLineComment).join("\n").replace(/\s+$/, "");
  return stripped.replace(/;\s*$/, "");
}

/** Returns the first top-level keyword in a statement (after leading comments). */
function firstKeyword(stmt) {
  const lines = stripLeadingComments(stmt).split("\n");
  for (const l of lines) {
    const kw = leadingKeyword(l);
    if (kw) return kw;
  }
  return null;
}

/** True when the statement has a top-level FROM clause (depth 0, outside parens). */
function hasTopLevelFrom(stmt) {
  const code = stmt.split("\n").map(stripLineComment).join("\n");
  let depth = 0, inStr = false;
  for (let i = 0; i < code.length; i++) {
    const ch = code[i];
    if (ch === "'") inStr = !inStr;
    if (inStr) continue;
    if (ch === "(") depth++;
    else if (ch === ")") depth = Math.max(0, depth - 1);
    else if (depth === 0 && /from/i.test(code.slice(i, i + 4))) {
      const before = code[i - 1], after = code[i + 4];
      if ((before === undefined || /\s/.test(before)) && (after === undefined || /\s/.test(after))) return true;
    }
  }
  return false;
}

/**
 * Returns true if `stmt`, after stripping comments and planner hints, contains
 * no recognizable top-level statement.
 */
function isCommentOnly(stmt) {
  return firstKeyword(stmt) === null || !isTopLevelKeyword(firstKeyword(stmt));
}

/**
 * Detect param references like `:foo`. Excludes `system:vitals` style
 * namespaces (preceded by an alphanumeric) and YYYY-MM-DDTHH:mm:ssZ-style
 * format placeholders that aren't real DQL params.
 *
 * Heuristic: param is `:[a-zA-Z_][a-zA-Z0-9_]*` not preceded by an
 * alphanumeric character. Also drop the well-known false positives
 * (`:vitals`, `:active_requests`, `:collections`, `:mm`, `:ssZ`).
 */
const FALSE_POSITIVE_PARAMS = new Set([
  "vitals", "active_requests", "collections", "mm", "ssZ",
]);

function findParams(q) {
  const params = new Set();
  const re = /(^|[^a-zA-Z0-9_])(:[a-zA-Z_][a-zA-Z0-9_]*)/g;
  let m;
  while ((m = re.exec(q)) !== null) {
    const name = m[2].slice(1);
    if (FALSE_POSITIVE_PARAMS.has(name)) continue;
    params.add(name);
  }
  return [...params];
}

// ---------------------------------------------------------------------------
// Parameter substitution
// ---------------------------------------------------------------------------

/**
 * Concrete substitutions for common params. Values are DQL literal strings
 * (already quoted/formatted). If a param isn't in the map we leave it alone.
 *
 * `id` substitution is special: for read-only SELECT statements we use a real
 * id from the seeded dataset (so the query has a chance to return rows). For
 * mutations we use a synthetic id so we don't clobber/evict real seed data.
 */
function paramSubstitutions(isReadOnly) {
  const idValue = isReadOnly ? `'${SEED_ID}'` : `'${SYNTH_ID}'`;
  return {
    id:             idValue,
    movie_id:       isReadOnly ? `'${SEED_ID}'` : `'${SYNTH_ID}'`,
    withdrawn_id:   `'${SYNTH_ID}'`, // tombstones are always destructive
    user_id:        `'u-42'`,
    user:           `'u-42'`,
    sender_id:      `'u-42'`,
    title:          `'Inception'`,
    year:           `2010`,
    make:           `'Tesla'`,
    model:          `'Model 3'`,
    color:          `'blue'`,
    actor_name:     `'Morgan Freeman'`,
    min_imdb:       `7.0`,
    min_priority:   `3`,
    decade_start:   `1990`,
    decade_end:     `1999`,
    page_size:      `25`,
    page_offset:    `0`,
    offset:         `0`,
    limit:          `25`,
    currentVersion: `1`,
    schema_version: `1`,
    value1:         `'value1'`,
    value2:         `'value2'`,
    text:           `'hello'`,
    search:         `'inception'`,
    status:         `'active'`,
    g:              `'Drama'`,
    v:              `1`,
    new_handle:     `'alice'`,
    id_list:        isReadOnly ? `('${SEED_ID}')` : `('${SYNTH_ID}')`,
    top_ids:        isReadOnly ? `('${SEED_ID}')` : `('${SYNTH_ID}')`,
    movies:         `'movies'`,
  };
}

/**
 * Substitute params with concrete literals. Returns
 *   { result, substituted: string[], remaining: string[] }.
 *
 * - `substituted` is the list of param names we replaced.
 * - `remaining`  is the list of param names that have no substitution.
 *
 * `isReadOnly` selects between SEED_ID (real, for SELECT) and SYNTH_ID (for
 * mutation statements that we'll seed+evict around).
 */
function substituteParams(query, isReadOnly) {
  const subs = paramSubstitutions(isReadOnly);
  const params = findParams(query);
  const substituted = [];
  const remaining = [];
  let out = query;
  for (const p of params) {
    if (subs[p] !== undefined) {
      const re = new RegExp(`(^|[^a-zA-Z0-9_]):${p}\\b`, "g");
      out = out.replace(re, (_full, prefix) => `${prefix}${subs[p]}`);
      substituted.push(p);
    } else {
      remaining.push(p);
    }
  }
  return { result: out, substituted, remaining };
}

// ---------------------------------------------------------------------------
// INSERT id extraction
// ---------------------------------------------------------------------------

/**
 * Extract `_id` values and collection name from an INSERT statement. Returns
 * { collection, ids } where `ids` is the array of string ids found in the
 * `DOCUMENTS (...)` clause. `ids` may be empty if the INSERT relies on
 * auto-generated ids.
 */
function parseInsert(stmt) {
  const collMatch = stmt.match(/INSERT\s+INTO\s+(?:COLLECTION\s+)?([A-Za-z_][A-Za-z0-9_]*)/i);
  if (!collMatch) return null;
  const collection = collMatch[1];

  const ids = [];
  // Find all `'_id'\s*:\s*'<value>'` occurrences.
  const idRe = /['"]_id['"]\s*:\s*['"]([^'"]+)['"]/g;
  let m;
  while ((m = idRe.exec(stmt)) !== null) {
    ids.push(m[1]);
  }
  return { collection, ids };
}

/**
 * Extract collection and (best-effort) where-clause target from an
 * UPDATE / EVICT / TOMBSTONE. Returns { kind, collection, idGuess } or null.
 *
 * `idGuess` is the string the WHERE clause says `_id =` to, if any. We use
 * this to decide whether to seed a pre-state doc.
 */
function parseMutation(stmt) {
  const m = stmt.match(/^\s*(?:--[^\n]*\n)*\s*(UPDATE|EVICT|TOMBSTONE)\s+(?:FROM\s+|COLLECTION\s+)?([A-Za-z_][A-Za-z0-9_]*)/i);
  if (!m) return null;
  const kind = m[1].toUpperCase();
  const collection = m[2];
  const idMatch = stmt.match(/_id\s*=\s*['"]([^'"]+)['"]/);
  const idGuess = idMatch ? idMatch[1] : null;
  return { kind, collection, idGuess };
}

// ---------------------------------------------------------------------------
// Main curation
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Curation overrides — catalog/overrides.json
// ---------------------------------------------------------------------------
// Manual decisions applied after the mechanical rules, keyed by entry id
// (ids are stable: hash of repo-relative file + line + query text).
//
//   availableIn:  replace the entry's version tag — used for features the
//                 docs describe but neither tested SDK ships yet ([] =
//                 expected to fail on every version).
//   ignore:       drop the entry from the catalog and record the reason —
//                 used for placeholders, illustrative fragments, and
//                 snippets that embed JS.
const OVERRIDES_PATH = path.join(TESTS_DIR, "catalog", "overrides.json");

// Seed reasons from the previous run so persistent ignores keep their reason.
const REASONS_PATH = path.join(TESTS_DIR, "catalog", "ignore-reasons.json");
const PRIOR_REASONS = fs.existsSync(REASONS_PATH)
  ? JSON.parse(fs.readFileSync(REASONS_PATH, "utf8"))
  : {};

const ignored = new Set(PRIOR_IGNORE);
const curated = [];

const ignoreReasons = new Map(Object.entries(PRIOR_REASONS)); // id -> reason

let counters = {
  total: RAW_CATALOG.length,
  multiStmt: 0,
  splitDropped: 0,    // statements after the first that we drop (e.g. cleanup duplicates)
  insertPostAdded: 0,
  mutationPreAdded: 0,
  paramsSubstituted: 0,
  paramsRemaining: 0,
  ignoredNoStatement: 0,
  ignoredUnsubstitutedParams: 0,
};

for (const entry of RAW_CATALOG) {
  const hints = entry._hints || {};
  const isWrong = hints.isWrong === true;

  // Rule A: split statements
  const stmts = splitStatements(entry.query);

  // If everything is comment-only -> drop, UNLESS the entry is a negative
  // example (isWrong). For isWrong entries we keep the raw query as-is so the
  // runner can verify the parse / runtime failure.
  const realStmts = stmts.filter(s => !isCommentOnly(s));
  if (realStmts.length === 0) {
    if (isWrong) {
      // Strip leading comments but otherwise pass-through.
      curated.push({
        id: entry.id,
        source: entry.source,
        query: stripTerminator(stripLeadingComments(entry.query)) || stripTerminator(entry.query),
        availableIn: entry.availableIn,
    unavailableReason: entry.unavailableReason,
        unavailableReason: entry.unavailableReason,
        expectError: true,
      });
      continue;
    }
    counters.ignoredNoStatement++;
    ignored.add(entry.id);
    ignoreReasons.set(entry.id, "no executable statement (pure comments / fragment)");
    continue;
  }

  let primary = realStmts[0];
  const tail = realStmts.slice(1);

  if (stmts.length > 1) counters.multiStmt++;

  // Rule B: param-only substitution (post-split, applied to the primary stmt)
  // First detect what kind of statement this is so we pick the right id.
  const primaryKwForSub = firstKeyword(stripLeadingComments(primary));
  const isReadOnlyPrimary = primaryKwForSub === "SELECT"
                         || primaryKwForSub === "SHOW"
                         || primaryKwForSub === "EXPLAIN"
                         || primaryKwForSub === "PROFILE";
  const subResult = substituteParams(primary, isReadOnlyPrimary);
  primary = subResult.result;
  counters.paramsSubstituted += subResult.substituted.length;
  counters.paramsRemaining   += subResult.remaining.length;

  // After substitution, recompute remaining params. If `isWrong`, we tolerate
  // any leftover params (the runner will see a parse/runtime error either way).
  const remainingParams = findParams(primary);

  if (remainingParams.length > 0 && !isWrong) {
    // Rule B: drop to ignore.json -- the runner can't bind these.
    counters.ignoredUnsubstitutedParams++;
    ignored.add(entry.id);
    ignoreReasons.set(
      entry.id,
      `unsubstituted parameters: ${remainingParams.map(p => `:${p}`).join(", ")}`,
    );
    continue;
  }

  // Rule G: SELECT without FROM. DQL requires a FROM clause, so standalone
  // SELECTs that demonstrate expression semantics (functions.md etc.) can
  // never run against a store -- ignore them.
  if (primaryKwForSub === "SELECT" && !hasTopLevelFrom(primary)) {
    counters.ignoredNoFrom = (counters.ignoredNoFrom || 0) + 1;
    ignored.add(entry.id);
    ignoreReasons.set(entry.id, "SELECT without FROM clause (expression-semantics example)");
    continue;
  }

  // Build the curated entry shell.
  primary = stripTerminator(primary);
  const curatedEntry = {
    id: entry.id,
    source: entry.source,
    query: primary,
    availableIn: entry.availableIn,
    unavailableReason: entry.unavailableReason,
    expectError: entry.expectError === true || isWrong,
  };

  // Tail handling: split into "cleanup" (post) vs ambient SELECT/SHOW (drop).
  /** @type {string[]} */
  const postQueries = [];
  for (const t of tail) {
    // Tail substitutions: assume non-read-only by default (tails are typically cleanup).
    const tKw = firstKeyword(stripLeadingComments(t));
    const tReadOnly = tKw === "SELECT" || tKw === "SHOW";
    const subT = substituteParams(t, tReadOnly);
    const tStripped = stripTerminator(stripLeadingComments(subT.result));
    if (findParams(tStripped).length > 0) {
      // Skip tail statements with unbindable params.
      counters.splitDropped++;
      continue;
    }
    const kw = firstKeyword(tStripped);
    if (kw === "SELECT" || kw === "SHOW" || kw === "EXPLAIN" || kw === "PROFILE") {
      // These are illustrative companion reads, not cleanup. Drop them.
      counters.splitDropped++;
      continue;
    }
    if (["INSERT", "EVICT", "TOMBSTONE", "UPDATE", "DELETE"].includes(kw)) {
      postQueries.push(tStripped);
    } else {
      counters.splitDropped++;
    }
  }

  // Rule D: INSERT entries -> add cleanup EVICTs to postQueries so reruns work.
  const primaryKw = firstKeyword(stripLeadingComments(primary));
  if (primaryKw === "INSERT") {
    const parsed = parseInsert(primary);
    if (parsed && parsed.ids.length > 0) {
      const idList = parsed.ids.map(id => `'${id}'`).join(", ");
      const evict = `EVICT FROM ${parsed.collection} WHERE _id IN (${idList})`;
      // Add as preQuery (clean before) and postQuery (clean after) so reruns work.
      curatedEntry.preQueries  = [evict];
      curatedEntry.postQueries = [...postQueries, evict];
      counters.insertPostAdded++;
    } else if (postQueries.length > 0) {
      curatedEntry.postQueries = postQueries;
    }
  } else if (["UPDATE", "EVICT", "TOMBSTONE"].includes(primaryKw)) {
    // Rule E: ensure a target doc exists.
    const m = parseMutation(stripLeadingComments(primary));
    if (m && m.idGuess) {
      // Seed a minimal doc with that id; clean it up after.
      const seed = `INSERT INTO ${m.collection} DOCUMENTS ({ '_id': '${m.idGuess}', '__test_seed': true }) ON ID CONFLICT DO UPDATE`;
      const evict = `EVICT FROM ${m.collection} WHERE _id = '${m.idGuess}'`;
      curatedEntry.preQueries  = [seed];
      curatedEntry.postQueries = [...postQueries, evict];
      counters.mutationPreAdded++;
    } else if (postQueries.length > 0) {
      curatedEntry.postQueries = postQueries;
    }
  } else if (postQueries.length > 0) {
    curatedEntry.postQueries = postQueries;
  }

  // Rule H: ALTER SYSTEM SET leaves global engine state — append a RESET to
  // restore the default for every subsequent entry in the run.
  if (primaryKw === "ALTER") {
    const m = /^\s*ALTER\s+SYSTEM\s+SET\s+(\w+)/i.exec(stripLeadingComments(primary));
    if (m) {
      curatedEntry.postQueries = [...(curatedEntry.postQueries || []), `ALTER SYSTEM RESET ${m[1]}`];
      counters.alterResetAdded = (counters.alterResetAdded || 0) + 1;
    }
  }

  // Rule F: do not copy _hints into final output.
  curated.push(curatedEntry);
}

// ---------------------------------------------------------------------------
// Apply curation overrides
// ---------------------------------------------------------------------------

if (fs.existsSync(OVERRIDES_PATH)) {
  const overrides = JSON.parse(fs.readFileSync(OVERRIDES_PATH, "utf8"));
  const ignoreMap = overrides.ignore || {};
  const availMap = overrides.availableIn || {};
  const setupMap = overrides.setup || {};
  const unavailMap = overrides.unavailableReason || {};
  for (let i = curated.length - 1; i >= 0; i--) {
    const e = curated[i];
    if (ignoreMap[e.id] !== undefined) {
      curated.splice(i, 1);
      ignored.add(e.id);
      ignoreReasons.set(e.id, ignoreMap[e.id]);
      continue;
    }
    if (availMap[e.id] !== undefined) {
      e.availableIn = availMap[e.id];
    }
    if (unavailMap[e.id] !== undefined) {
      // Justification for an entry that runs on no supported SDK. Without one,
      // the runner reports BROKEN-EVERYWHERE and fails the run.
      e.unavailableReason = unavailMap[e.id];
    }
    if (setupMap[e.id]) {
      // Manual statement decorations, e.g. CREATE INDEX before a JOIN whose
      // right-side match key must be indexed on 5.1+.
      if (setupMap[e.id].preQueries) {
        e.preQueries = [...setupMap[e.id].preQueries, ...(e.preQueries || [])];
      }
      if (setupMap[e.id].postQueries) {
        e.postQueries = [...(e.postQueries || []), ...setupMap[e.id].postQueries];
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Write outputs
// ---------------------------------------------------------------------------

// Prune orphans before writing. `ignored` and `ignoreReasons` are seeded from
// the previous run so persistent ignores keep their hand-written reason, but
// that also means an id whose sql block was edited or deleted would be carried
// forward forever. Keep only ids that correspond to a block seen in THIS run
// (the raw catalog is every block in skills/dql, pre-filter).
const BLOCKS_PATH = path.join(TESTS_DIR, "catalog", "blocks.json");
const liveIds = fs.existsSync(BLOCKS_PATH)
  ? new Set(JSON.parse(fs.readFileSync(BLOCKS_PATH, "utf8")).map(b => b.id))
  : new Set([...RAW_CATALOG.map(e => e.id), ...ignored]); // no inventory: prune nothing
const orphans = [...ignored].filter(id => !liveIds.has(id));
for (const id of orphans) { ignored.delete(id); ignoreReasons.delete(id); }

// Re-attach captured assertions stashed by extract-queries.mjs, keyed by the
// (stable) entry id. Without this, re-extracting drops every golden.
const GOLDENS_PATH = path.join(TESTS_DIR, "catalog", "goldens.json");
let reattached = 0;
if (fs.existsSync(GOLDENS_PATH)) {
  const goldens = JSON.parse(fs.readFileSync(GOLDENS_PATH, "utf8"));
  for (const e of curated) {
    if (e.expect === undefined && goldens[e.id] !== undefined) { e.expect = goldens[e.id]; reattached++; }
  }
  console.log(`Re-attached ${reattached} golden(s) from ${GOLDENS_PATH}`);
}

fs.writeFileSync(CATALOG, JSON.stringify(curated, null, 2));
fs.writeFileSync(IGNORE,  JSON.stringify([...ignored].sort(), null, 2));

// Also drop a sidecar file with reasons -- useful for Task 12 audit.
fs.writeFileSync(REASONS_PATH, JSON.stringify(Object.fromEntries(ignoreReasons), null, 2));

if (orphans.length) console.log(`Pruned ${orphans.length} orphaned ignore id(s): ${orphans.join(", ")}`);

console.log("=== Curation summary ===");
console.log(`Input entries:                    ${counters.total}`);
console.log(`Output entries:                   ${curated.length}`);
console.log(`Ignored (no executable stmt):     ${counters.ignoredNoStatement}`);
console.log(`Ignored (unsubstituted params):   ${counters.ignoredUnsubstitutedParams}`);
console.log(`Total ignored:                    ${ignored.size}`);
console.log(`Multi-statement entries:          ${counters.multiStmt}`);
console.log(`Tail statements dropped:          ${counters.splitDropped}`);
console.log(`INSERTs with cleanup added:       ${counters.insertPostAdded}`);
console.log(`Mutations with pre-state added:   ${counters.mutationPreAdded}`);
console.log(`Param substitutions applied:      ${counters.paramsSubstituted}`);
console.log(`Param refs left unhandled:        ${counters.paramsRemaining}`);
console.log(`expectError=true entries:         ${curated.filter(e => e.expectError).length}`);
console.log(`Entries with preQueries:          ${curated.filter(e => e.preQueries).length}`);
console.log(`Entries with postQueries:         ${curated.filter(e => e.postQueries).length}`);
console.log(`Wrote ${CATALOG}`);
console.log(`Wrote ${IGNORE} (${ignored.size} ids)`);
console.log(`Wrote ${REASONS_PATH}`);
