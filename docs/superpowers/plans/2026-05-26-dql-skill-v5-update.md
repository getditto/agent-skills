# DQL Skill Update — Public Plugin Sync with v5.1.0 Internal Skill, Filtered for v5.0.0 SDK Compatibility

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lift the public `ditto-dql` plugin to parity with the internal v5.1.0 DQL skill across the supported Ditto SDK range (**v4.14.x through v5.0.0**), with every documented feature carrying its minimum-SDK-version annotation. Build the infrastructure so v5.1.0 features can be added in a follow-up without restructuring.

**Architecture:** A single `skills/dql/` skill (no per-version forks) with **version-tagged content**: every function, operator, statement, and expression is annotated with its minimum supported Ditto SDK version, verified against three source trees (`/Users/labeaaa/Developer/ditto-v4` for v4.14.x, `/Users/labeaaa/Developer/ditto-v5` for v5.0.0, `/Users/labeaaa/Developer/ditto-v5-experiments` for upcoming v5.1.0 we explicitly exclude). The agent asks the user which SDK version they are on at the start of any DQL task and filters accordingly. A dedicated `references/versions.md` is the single-pane compatibility matrix. Reuses the internal v5.1.0 layout (`SKILL.md` + `references/` + `examples/`). Preserves the existing best-practices content (strict mode, schema versioning, timestamps) which the internal skill does not cover.

**Tech Stack:** Claude Code plugin (skills + agents), markdown documentation, YAML frontmatter. Verification done via `grep`/`sed` against the Rust source under `/Users/labeaaa/Developer/ditto-v4/` (v4.14.x DQL implementation) and `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql*/` (v5.0.0 DQL).

---

## Compatibility Reference (locked findings)

These findings drive every task below. The v5.0.0 findings came from grepping `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql*` directly. The v4.14.x findings will be filled in by **Task 0** before reference-file work begins, and saved alongside this plan as `versions-audit.md`.

The plan ships content covering **two SDK lines**:
- **v4.14.x** — the LTS line still in production at customer sites; minimum supported feature set
- **v5.0.0** — the current shipped SDK; default target for new code

Anything that requires **v5.1.0** is intentionally excluded but cataloged in `references/versions.md` so it can be lifted in a follow-up plan when v5.1.0 ships.

### Version-annotation convention (used by every reference task below)

Every documented feature carries one of these blockquote tags:

```markdown
> **Available in:** Ditto SDK 4.11+
> **Available in:** Ditto SDK 5.0+
> **Behavior differs:** see versions.md
```

When a single feature behaves differently across versions, the section includes a "Cross-version notes" subsection with a small table. Anything with no tag means "supported on every version this skill covers" (v4.14.x and v5.0.0).

### v5.0.0 SUPPORTED (safe to document)

**Statements** (from `Statement` enum in `crates/ditto-dql-shared/src/ast/mod.rs:1094`):
`EXPLAIN`, `SELECT`, `INSERT`, `UPDATE`, `EVICT` / `TOMBSTONE` / `DELETE` (all map to `Remove`), `ALTER SYSTEM`, `SHOW`, `SYNC CONTEXT` (RemoteQuery), `CREATE INDEX`, `DROP INDEX`.

**Conflict policies** (`OnConflictAction` enum at `ast/mod.rs:1143`): `DoNothing`, `DoUpdate`, `DoUpdateDifferent` (= `DO UPDATE_LOCAL_DIFF`). Default = FAIL.

**Expressions:**
- `CASE` (simple + searched) — `Expr::Case` at `ast/mod.rs:760`
- `ANY|EVERY|ANY AND EVERY var IN|WITHIN expr SATISFIES condition END` — `ast/mod.rs:552`
- `ARRAY expr FOR [index:]var IN source [WHEN cond] END` — `ast/mod.rs:567`
- `OBJECT k:v FOR [name:]var IN source [WHEN cond] END` — `ast/mod.rs:568`
- Path expressions, parameter binding `:name`, literals (incl. hex), backtick identifiers
- `RETURNING` clause (`ast/remove.rs`, `ast/modification.rs`)

**Aggregates** (`crates/ditto-dql/src/execution/aggregate.rs`): `count`, `sum`, `min`, `max`, `avg`, `mid`, `median` (all with `DISTINCT` modifier).

**Functions:** the full v5.1.0 list from Agent 1's catalog EXCEPT `serialize_json()` and `object_size()` (which do not appear in `crates/ditto-dql/src/functions/`).

**Indexing:** `CREATE INDEX [IF NOT EXISTS] collection.name(keys) [ASC|DESC] [INCLUDE|EXCLUDE MISSING]`, `DROP INDEX [IF EXISTS]`, planner directives via `/*+ {...} */` / `--+ {...}` / `USE INDEX` / `USE DIRECTIVES`.

**USE IDS:** Available **only on `SELECT`** (`ast/query.rs:38`). Parser has `// TODO add USE IDS` for `UPDATE` and `REMOVE` (`parser.rs:450, 2689`). **Do not document USE IDS on mutations.**

**PROFILE keyword:** Accepted as a context-keyword that sets the `#profile` directive (`parser.rs:378`). Users CAN write `PROFILE SELECT ...` and receive profile output. **However**, the output shape is the planner-directive output, not the structured PROFILE-statement output the v5.1.0 skill teaches. Treat as supported with a caveat note.

### v5.0.0 NOT SUPPORTED (must exclude)

- `ADVISE` / `ADVISE AND PROVISION` — not in keyword list, not a statement variant.
- `XOR` operator — keyword not present in DQL parser (only in unrelated `ditto-type-logic` crate).
- `DO MERGE` conflict action — only `DoNothing`/`DoUpdate`/`DoUpdateDifferent` exist.
- `serialize_json()`, `object_size()` — not in `crates/ditto-dql/src/functions/`.
- `USE IDS` on `UPDATE` / `DELETE` / `EVICT` / `TOMBSTONE` — parser TODOs confirm not implemented.
- `INSERT ... SELECT` — no parser path; treat as not supported.
- `JOIN` / `UNION` / `UNNEST` — keywords reserved but no implementation; not supported.

### Existing-plugin correctness bugs to fix

1. `plugins/ditto-dql/skills/write-dql/SKILL.md` line ~19 says "No GROUP BY" — **wrong**; GROUP BY is supported and the same file uses it in examples.
2. `plugins/ditto-dql/skills/write-dql/dql-operators.md` lines 526-543 say "CASE/WHEN not supported; use decode()" — **wrong**; `Expr::Case` exists in v5.0.0.
3. `README.md` promises "Subscription query patterns" but the skill has no dedicated subscription section.

---

## File Structure (target layout)

```
plugins/ditto-dql/
├── .claude-plugin/
│   └── plugin.json                      [MODIFY — bump version to 2.0.0]
├── README.md                            [MODIFY — refresh feature list, link to new files]
├── agents/
│   └── dql-expert.md                    [MODIFY — point at new skill name]
└── skills/
    └── dql/                             [RENAME from write-dql]
        ├── SKILL.md                     [REWRITE — entry point + decision tree]
        ├── best-practices.md            [MODIFY — keep, retarget cross-references]
        ├── references/                  [NEW DIRECTORY]
        │   ├── versions.md              [NEW — SDK compatibility matrix; min-version per feature; what's coming in v5.1.0]
        │   ├── statements.md            [NEW — INSERT/UPDATE/EVICT/TOMBSTONE/DELETE/EXPLAIN/ALTER SYSTEM/SHOW/SYNC CONTEXT/CREATE INDEX/DROP INDEX, version-tagged]
        │   ├── select.md                [NEW — full SELECT clause reference, version-tagged]
        │   ├── operators.md             [NEW — replaces dql-operators.md; adds 4-valued logic; version-tagged]
        │   ├── functions.md             [NEW — complete v5.0.0-safe catalog, version-tagged per function]
        │   ├── expressions.md           [NEW — path, parameters, CASE, ANY/EVERY/SATISFIES, comprehensions, version-tagged]
        │   ├── types-mutators.md        [NEW — REGISTER/MAP/COUNTER/PN_COUNTER/ATTACHMENT, version-tagged]
        │   └── indexing.md              [NEW — CREATE INDEX, planner directives, USE IDS (SELECT only), EXPLAIN, #profile, version-tagged]
        └── examples/                    [NEW DIRECTORY]
            └── movies-cookbook.md       [NEW — 18 v5.0.0-safe end-to-end tasks on the movies dataset]
```

Old `skills/write-dql/dql-operators.md` is **deleted** — its content moves into `references/operators.md` plus `references/functions.md`.

---

## Working Directory & Branch

Already done before this plan was written:
- Branch: `dql-update-cookbook` (created from `main`)
- Working tree: `/Users/labeaaa/Developer/claude-code-plugins`

Source-of-truth references throughout the plan:
- **Internal v5.1.0 skill (port from):** `/Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/`
- **v5.0.0 SDK source (verify against):** `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql*/`

---

### Task 0: Audit v4.14.x DQL support and produce the version matrix

This task is **prerequisite** for every reference-writing task. The output is a working document at `docs/superpowers/plans/2026-05-26-dql-versions-audit.md` that downstream tasks consult when annotating features.

**Files:**
- Create: `docs/superpowers/plans/2026-05-26-dql-versions-audit.md` (working document, not part of the shipped plugin)

**Source trees:**
- v4.14.x: `/Users/labeaaa/Developer/ditto-v4/` (note the older repo layout — DQL is under `core/` rather than `crates/`)
- v5.0.0: `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql*/` (already audited; findings above)
- v5.1.0 reference: `/Users/labeaaa/Developer/ditto-v5-experiments/` (for comparison only — content here is excluded)

- [ ] **Step 1: Locate the v4 DQL implementation**

```bash
find /Users/labeaaa/Developer/ditto-v4 -type d -name "*dql*" 2>/dev/null | head -10
find /Users/labeaaa/Developer/ditto-v4 -type d -name "*query*" 2>/dev/null | head -10
find /Users/labeaaa/Developer/ditto-v4 -name "keywords.rs" 2>/dev/null | head -5
find /Users/labeaaa/Developer/ditto-v4 -name "functions" -type d 2>/dev/null | head -10
```

Expected: at least one DQL-related directory. If the layout differs significantly from v5, note where parser/functions/AST live for downstream tasks.

- [ ] **Step 2: Pull the v4 keyword list**

```bash
KW=$(find /Users/labeaaa/Developer/ditto-v4 -name "keywords.rs" | head -1)
echo "Found at: $KW"
grep -E "^    [A-Z_]+,$" $KW | sort -u
```

Expected: a complete list of v4.14.x DQL keywords.

- [ ] **Step 3: Pull the v4 Statement enum**

```bash
SHARED=$(find /Users/labeaaa/Developer/ditto-v4 -path "*/ditto-dql-shared/src/ast/mod.rs" -o -path "*ast/mod.rs" 2>/dev/null | grep -i dql | head -1)
echo "Found at: $SHARED"
awk '/pub enum Statement/,/^}/' $SHARED
```

Expected: enumeration of v4 top-level statements. Compare against the v5.0.0 list (Explain/Query/Insert/Update/Remove/AlterSystem/Show/RemoteQuery/CreateIndex/DropIndex) and note differences.

- [ ] **Step 4: Pull the v4 function inventory**

```bash
FN_DIR=$(find /Users/labeaaa/Developer/ditto-v4 -path "*ditto-dql*functions*" -type d 2>/dev/null | head -1)
echo "Found at: $FN_DIR"
ls $FN_DIR
grep -rh "fn [a-z_]*(" $FN_DIR | grep -oE "fn [a-z_]+" | sort -u
```

- [ ] **Step 5: Confirm or refute key feature presence in v4.14.x**

For each of these, grep v4 source and record YES/NO:

```bash
V4=/Users/labeaaa/Developer/ditto-v4
echo "=== CASE expression ===" && grep -rn "Expr::Case\|CaseExpr" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== ANY/EVERY SATISFIES ===" && grep -rn "Satisfies" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== ARRAY/OBJECT FOR comprehension ===" && grep -rn "ARRAY expr FOR\|OBJECT.*FOR.*IN" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== MID/MEDIAN ===" && grep -rn "Aggregate::Mid\|Aggregate::Median" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== CREATE INDEX ===" && grep -rn "CreateIndex" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== TOMBSTONE keyword ===" && grep -rn "TOMBSTONE" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== SYNC CONTEXT ===" && grep -rn "SyncContext\|parse_sync_context" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== RETURNING ===" && grep -rn "RETURNING" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== USE IDS ===" && grep -rn "use_ids\|USE IDS" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== COUNTER (4.13) ===" && grep -rn "Counter\|::Counter" $V4 --include="*.rs" 2>/dev/null | head -5
echo "=== PN_COUNTER ===" && grep -rn "PnCounter\|PN_COUNTER" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== DO UPDATE_LOCAL_DIFF ===" && grep -rn "DoUpdateDifferent\|UPDATE_LOCAL_DIFF" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== ALTER SYSTEM ===" && grep -rn "AlterSystem" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== SHOW ===" && grep -rn "Statement::Show\|parse_show" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== Planner directives (#profile etc) ===" && grep -rn "context_keyword\|ContextKeyword" $V4 --include="*.rs" 2>/dev/null | head -5
echo "=== EXPLAIN ===" && grep -rn "Statement::Explain" $V4 --include="*.rs" 2>/dev/null | head -3
echo "=== Strict mode flag ===" && grep -rn "DQL_STRICT_MODE\|MUTATOR_OBJECTS_AS_MAPS\|FeatureFlag" $V4 --include="*.rs" 2>/dev/null | head -5
```

- [ ] **Step 6: Confirm function-by-function which exist in v4.14.x**

```bash
V4_FN=$(find /Users/labeaaa/Developer/ditto-v4 -path "*ditto-dql*functions*" -type d 2>/dev/null | head -1)
for fn in abs ceil floor coalesce decode nvl isnull ismissing ismissingornull ifnull ifmissing ifmissingornull nullif missingif cast deserialize_json is_boolean is_number is_string type json_type byte_length char_length character_length length concat contains starts_with ends_with ltrim rtrim trim upper lower repeat split joinstr substr pos lpad rpad regexp_like array_contains array_contains_null array_length object_length object_keys object_values object_set object_unset object_concat object_rename object_content date_cast tz_offset clock date_format date_add date_sub date_diff date_range date_part date_trunc duration_cast duration_format count sum min max avg mid median request_info; do
  if grep -rqi "\"$fn\"\\|fn $fn\\b" $V4_FN 2>/dev/null; then
    echo "v4 YES  $fn"
  else
    echo "v4 NO   $fn"
  fi
done | sort
```

Save this output verbatim into the audit document.

- [ ] **Step 7: Write `docs/superpowers/plans/2026-05-26-dql-versions-audit.md`**

The audit document must contain at minimum:

```markdown
# DQL Versions Audit — v4.14.x vs v5.0.0

Reference source for the version annotations in `plugins/ditto-dql/skills/dql/references/*.md`.

## v4.14.x DQL implementation location

- Parser: <absolute path>
- AST: <absolute path>
- Functions: <absolute path>

## Top-level statements (v4.14.x)

<list from Step 3 + comparison against v5.0.0 list>

## Functions present in BOTH v4.14.x and v5.0.0

<list>

## Functions present in v5.0.0 ONLY (require SDK 5.0+)

<list>

## Functions present in v4.14.x ONLY (deprecated/removed in v5.0.0)

<list — usually empty, but record if any>

## Expressions and statements with version differences

| Feature                              | v4.14.x | v5.0.0 | Notes |
|--------------------------------------|---------|--------|-------|
| CASE expression                      | ?       | YES    |       |
| ANY/EVERY SATISFIES                  | ?       | YES    |       |
| ARRAY/OBJECT FOR comprehensions      | ?       | YES    |       |
| TOMBSTONE                            | ?       | YES    |       |
| SYNC CONTEXT                         | ?       | YES    |       |
| RETURNING                            | ?       | YES    |       |
| USE IDS on SELECT                    | ?       | YES    |       |
| USE IDS on UPDATE/DELETE/EVICT       | NO      | NO     | TODO in v5 parser; both versions excluded |
| COUNTER type                         | 4.13+   | YES    | Confirm 4.14.x has it |
| PN_COUNTER type                      | 4.11+   | YES    |       |
| DO UPDATE_LOCAL_DIFF                 | 4.12+   | YES    |       |
| ATTACHMENT type                      | ?       | YES    |       |
| ALTER SYSTEM / SHOW                  | ?       | YES    |       |
| EXPLAIN                              | ?       | YES    |       |
| #profile directive                   | ?       | YES    |       |
| Strict mode default                  | strict  | lenient | Plugin already documents this |

(Fill `?` cells from Steps 5/6 output.)

## Excluded from this skill (v5.1.0 only)

- ADVISE / ADVISE AND PROVISION
- XOR
- DO MERGE conflict
- serialize_json(), object_size()
- USE IDS on mutations
- Structured PROFILE statement output (the keyword works via #profile but output shape changes in v5.1)
```

- [ ] **Step 8: Commit the audit doc**

```bash
git add docs/superpowers/plans/2026-05-26-dql-versions-audit.md
git commit -m "docs(ditto-dql): audit v4.14.x vs v5.0.0 DQL feature support"
```

> **Downstream contract:** Tasks 4-11 MUST consult this audit when adding `> **Available in:** Ditto SDK X.Y+` blockquotes. If a feature has `?` cells unresolved at the time a reference task runs, the implementer must resolve them (run the targeted grep, update the audit) before writing the doc.

---

### Task 1: Scaffold the new directory layout

**Files:**
- Rename: `plugins/ditto-dql/skills/write-dql/` → `plugins/ditto-dql/skills/dql/`
- Create: `plugins/ditto-dql/skills/dql/references/` (directory)
- Create: `plugins/ditto-dql/skills/dql/examples/` (directory)

- [ ] **Step 1: Rename the skill folder**

```bash
cd /Users/labeaaa/Developer/claude-code-plugins
git mv plugins/ditto-dql/skills/write-dql plugins/ditto-dql/skills/dql
```

- [ ] **Step 2: Create the new subdirectories**

```bash
mkdir -p plugins/ditto-dql/skills/dql/references
mkdir -p plugins/ditto-dql/skills/dql/examples
```

- [ ] **Step 3: Verify layout**

```bash
ls -la plugins/ditto-dql/skills/dql/
```

Expected: `SKILL.md`, `dql-operators.md`, `best-practices.md`, `references/`, `examples/`. (`dql-operators.md` will be removed in Task 5.)

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/
git commit -m "refactor(ditto-dql): rename write-dql skill to dql and add references/examples scaffolding"
```

---

### Task 2: Fix correctness bugs in the existing files

These are wrong-today claims that must be corrected before adding more content on top.

**Files:**
- Modify: `plugins/ditto-dql/skills/dql/SKILL.md`
- Modify: `plugins/ditto-dql/skills/dql/dql-operators.md` (will be replaced entirely in Task 5, but fix until then so the skill is never internally inconsistent)

- [ ] **Step 1: Verify the bug in SKILL.md**

```bash
grep -n "No GROUP BY\|GROUP BY" plugins/ditto-dql/skills/dql/SKILL.md
```

Expected: see the "No GROUP BY" claim alongside GROUP BY examples.

- [ ] **Step 2: Remove the "No GROUP BY" claim from SKILL.md**

Find the line that reads (verbatim, approximate location ~line 19):

```
- **No GROUP BY** — Use separate queries
```

…and delete it. GROUP BY is supported; the same SKILL.md uses it.

- [ ] **Step 3: Verify the CASE bug**

```bash
grep -n "CASE\|case" plugins/ditto-dql/skills/dql/dql-operators.md | head -20
```

Expected: lines ~526-543 claim CASE is unsupported.

- [ ] **Step 4: Verify CASE actually works in v5.0.0**

```bash
grep -n "Expr::Case" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-shared/src/ast/mod.rs
```

Expected: match at line 760.

- [ ] **Step 5: Replace the "CASE not supported" section in `dql-operators.md`**

Replace lines ~526-543 (the entire "CASE/WHEN Expressions — Not supported" block) with a short note:

```markdown
## CASE expressions

DQL supports both simple and searched CASE.

```sql
-- Searched form (recommended)
SELECT title,
  CASE
    WHEN year < 1970 THEN 'Classic'
    WHEN year < 2000 THEN 'Modern'
    ELSE 'Contemporary'
  END AS era
FROM movies

-- Simple form
SELECT _id,
  CASE genres[0]
    WHEN 'Drama' THEN 'Heavy'
    WHEN 'Comedy' THEN 'Light'
    ELSE 'Other'
  END AS mood
FROM movies
```

`decode()` is still available and is preferable for short equality switches inside expressions. See `references/expressions.md` for the full pattern reference.
```

- [ ] **Step 6: Commit**

```bash
git add plugins/ditto-dql/skills/dql/SKILL.md plugins/ditto-dql/skills/dql/dql-operators.md
git commit -m "fix(ditto-dql): remove incorrect 'no GROUP BY' claim and document CASE support"
```

---

### Task 3: Port the movies dataset definition into the public plugin

The internal cookbook leans heavily on a `movies` + `reviews` dataset. Define it once, in `examples/movies-cookbook.md`, before writing examples elsewhere — so every reference example can pull from a shared schema.

**Files:**
- Create: `plugins/ditto-dql/skills/dql/examples/movies-cookbook.md`

- [ ] **Step 1: Confirm the schema against the internal source**

```bash
sed -n '1,200p' /Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/examples/movies-cookbook.md
```

Expected: see the schema block with `_id`, `title`, `year`, `runtime_minutes`, `genres`, `director` (MAP), `cast` (array of objects), `ratings` (MAP), `box_office_millions`, `tags`, `watch_count` (COUNTER), `is_classic`, `released`.

- [ ] **Step 2: Stub the file with frontmatter and the dataset section ONLY**

Create `plugins/ditto-dql/skills/dql/examples/movies-cookbook.md` with this header (the body will be filled in Task 11):

```markdown
---
title: DQL movies cookbook
description: 18 end-to-end DQL tasks against a sample movies dataset. Every statement here is verified to work on the Ditto v5.0.0 SDK.
---

# DQL Movies Cookbook

A practical walkthrough of every major DQL capability the v5.0.0 SDK supports. Each task is self-contained — paste it into a Ditto query interface and it should run.

> **Compatibility:** Tested against Ditto SDK v5.0.0. Features added in v5.1.0 (`ADVISE`, `PROFILE` structured output, `XOR`, `DO MERGE`, `serialize_json`, `object_size`) are intentionally excluded.

## Dataset

The cookbook uses two collections: `movies` and `reviews`.

### `movies` schema

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | IMDb id, e.g. `"tt0111161"` |
| `title` | string | REGISTER | |
| `year` | integer | REGISTER | |
| `runtime_minutes` | integer | REGISTER | |
| `genres` | array<string> | REGISTER | JSON array of genre names |
| `director` | object | **MAP** | `{name, born}` |
| `cast` | array<object> | REGISTER | `[{name, role}, ...]` |
| `ratings` | object | **MAP** | `{imdb, rotten_tomatoes, metacritic}` |
| `box_office_millions` | number | REGISTER | |
| `tags` | array<string> | REGISTER | |
| `watch_count` | integer | **COUNTER** | distributed counter |
| `is_classic` | boolean | REGISTER | |
| `released` | string | REGISTER | ISO-8601 `YYYY-MM-DD` |

### `reviews` schema

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | auto |
| `movie_id` | string | REGISTER | FK to `movies._id` |
| `user_id` | string | REGISTER | |
| `score` | integer | REGISTER | 1–5 |
| `comment` | string | REGISTER | |
| `created_at` | string | REGISTER | ISO-8601 timestamp |

<!-- Task bodies will be added in plan Task 11. -->
```

- [ ] **Step 3: Commit**

```bash
git add plugins/ditto-dql/skills/dql/examples/movies-cookbook.md
git commit -m "docs(ditto-dql): stub movies cookbook with shared dataset schema"
```

---

### Task 4: Write `references/operators.md`

The single biggest content uplift. Replaces the existing `dql-operators.md` (will be deleted in Task 5).

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/operators.md`
- Source to mirror: `/Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/references/operators.md`

- [ ] **Step 1: Verify the operator set against v5.0.0**

```bash
grep -E "^    [A-Z_]+,$" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/keywords.rs | grep -iE "AND|OR|NOT|XOR|BETWEEN|LIKE|ILIKE|SIMILAR|IS"
```

Expected: AND, OR, NOT, BETWEEN, LIKE, ILIKE, SIMILAR, IS present. **No XOR.**

- [ ] **Step 1.5: Read the version audit**

```bash
cat docs/superpowers/plans/2026-05-26-dql-versions-audit.md
```

Every section you write must end with the appropriate `> **Available in:** Ditto SDK X.Y+` blockquote, or — if the operator works identically on every version this skill covers (v4.14.x and v5.0.0) — no tag (the implicit default is "supported throughout"). For operators with cross-version behavior differences, add a "Cross-version notes" subsection.

- [ ] **Step 2: Author `references/operators.md`** with the following sections (in order):

1. **Precedence table** — full table from the internal skill.
2. **Arithmetic operators** — `+ - * / %`, unary `-`. Note integer-vs-float promotion.
3. **Comparison operators** — `= == <> != < > <= >=`. Document NULL/MISSING behaviour explicitly.
4. **Special unary** — `IS NULL`, `IS NOT NULL`, `IS MISSING`, `IS NOT MISSING`, `IS UNKNOWN`, `IS NOT UNKNOWN`, `IS TRUE`, `IS NOT TRUE`, `IS FALSE`, `IS NOT FALSE`.
5. **Range / membership** — `BETWEEN`, `IN`, `NOT IN`. **Call out** that `IN` is for scalar lists, **not** array containment — use `array_contains()` or `ANY ... SATISFIES` for array membership.
6. **Pattern matching** — `LIKE`, `ILIKE`, `SIMILAR TO`, `regexp_like()`.
7. **Logical operators with 4-valued logic** — AND/OR/NOT truth tables for TRUE/FALSE/NULL/MISSING. Take these tables verbatim from `/Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/references/operators.md`.
8. **String operator** — `||` (no implicit conversion; cast first).
9. **Array/object access** — `array[index]`, `object.field`, `object[expr]`.
10. **Critical warning section** — boolean operators must use words (`AND`/`OR`/`NOT`), not `&&`/`||`/`!`. Single quotes only for strings. (Carry these warnings forward from current plugin.)

**Explicitly exclude** any mention of `XOR` even though the v5.1.0 internal docs hint at it.

- [ ] **Step 3: Verify the file's example queries don't reference excluded features**

```bash
grep -E "XOR|ADVISE|PROFILE|DO MERGE|serialize_json|object_size" plugins/ditto-dql/skills/dql/references/operators.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/operators.md
git commit -m "docs(ditto-dql): add operators reference with 4-valued logic tables"
```

---

### Task 5: Write `references/functions.md` and retire `dql-operators.md`

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/functions.md`
- Delete: `plugins/ditto-dql/skills/dql/dql-operators.md`
- Source to mirror (filtered): `/Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/references/functions.md`

- [ ] **Step 1: Pull the v5.0.0 function inventory**

```bash
ls /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql/src/functions/
```

Expected: `array.rs conditionals.rs conversion.rs date.rs duration.rs math.rs object.rs request_info.rs string.rs types.rs` (plus `mod.rs`). Every function the skill documents must be defined in one of these.

- [ ] **Step 2: Confirm exclusions are absent**

```bash
grep -ri "serialize_json\|object_size" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql/src/functions/
```

Expected: no matches.

- [ ] **Step 2.5: Read the version audit and prepare per-function annotations**

```bash
cat docs/superpowers/plans/2026-05-26-dql-versions-audit.md
```

Every function entry MUST include its minimum SDK version. Format the function table with a version column:

```markdown
| Function | Min SDK | Description | Example |
|---|---|---|---|
| `count(expr)` | 4.x | ... | ... |
| `mid(expr)` | 5.0+ | ... | ... |  (only if confirmed v5-only)
```

Use the audit's per-function YES/NO output from Task 0 Step 6 as authoritative. If a function is listed `v4 YES` it's available throughout (use `4.x` or omit the column). If `v4 NO` and present in v5.0.0, mark as `5.0+`.

- [ ] **Step 3: Author `references/functions.md`** with these sections, each function getting signature + 1-2 line description + min-SDK + one short worked example using `movies` or `reviews`:

- **Math:** `abs`, `ceil`, `floor`
- **Conditional / null-handling:** `coalesce`, `decode`, `nvl`, `isnull`, `ismissing`, `ismissingornull`, `ifnull`, `ifmissing`, `ifmissingornull`, `nullif`, `missingif`
- **Type / conversion:** `cast` (both `cast(v, 'type')` and `CAST(v AS type)`), `deserialize_json`, `is_boolean`, `is_number`, `is_string`, `type`, `json_type` — **do not document `serialize_json`**
- **String:** `byte_length`, `char_length`, `character_length`, `length` (note: alias of `byte_length`, deprecated), `concat`, `contains`, `starts_with`, `ends_with`, `ltrim`, `rtrim`, `` `trim` ``, `upper`, `lower`, `repeat`, `split`, `joinstr`, `substr`, `pos`, `POSITION(substr IN str)` syntax, `lpad`, `rpad`, `regexp_like`, `TRIM([LEADING|TRAILING|BOTH] expr FROM expr)`
- **Array:** `array_contains`, `array_contains_null`, `array_length`
- **Object:** `object_length`, `object_keys`, `object_values`, `object_set`, `object_unset`, `object_concat`, `object_rename`, `object_content` — **do not document `object_size`**
- **Date/Time:** `date_cast`, `tz_offset`, `clock`, `date_format`, `date_add`, `date_sub`, `date_diff`, `date_range`, `date_part`, `date_trunc`
- **Duration:** `duration_cast`, `duration_format`
- **Aggregates:** `count` (incl. `count(*)` and `count(DISTINCT)`), `sum`, `min`, `max`, `avg`, `mid`, `median` — all support `DISTINCT`
- **Misc:** `request_info`

For each function, copy the signature/description directly from the internal v5.1.0 reference and adapt the example to the movies dataset.

- [ ] **Step 4: Cross-check the doc against the v5.0.0 function registry**

For each function name in the doc, run:

```bash
F=<function_name>; grep -rni "\"$F\"\|fn $F\b" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql/src/functions/ | head -3
```

Expected: at least one hit per documented function. Any zero-hit function is either misspelled or not in v5.0.0 — remove it.

- [ ] **Step 5: Delete the old combined file**

```bash
git rm plugins/ditto-dql/skills/dql/dql-operators.md
```

- [ ] **Step 6: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/functions.md
git commit -m "docs(ditto-dql): add complete functions reference and retire dql-operators.md"
```

---

### Task 6: Write `references/expressions.md`

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/expressions.md`
- Source to mirror: `/Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/references/expressions.md`

- [ ] **Step 1: Confirm v5.0.0 supports each section**

```bash
grep -n "Expr::Case\|SATISFIES\|FOR.*END\|Quantifier" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-shared/src/ast/mod.rs | head -10
```

Expected: `Expr::Case` at ~760, `SATISFIES` at ~552/944, `FOR ... END` comprehension grammar at ~567-568.

- [ ] **Step 1.5: Read the version audit**

For each expression construct (CASE, ANY/EVERY SATISFIES, ARRAY FOR, OBJECT FOR), look up the v4.14.x status in the audit. Add `> **Available in:** Ditto SDK X.Y+` blockquotes to any subsection where v4.14.x lacks the construct.

- [ ] **Step 2: Author the file** with these sections:

1. **Literals** — numbers (incl. hex `0x`), booleans, `NULL`, `MISSING`, strings (single-quoted), array literals, object literals
2. **Identifiers** — bare vs backtick-delimited; when backticks are required (dots, spaces, keyword collisions)
3. **Parameters** — `:name` syntax. Document where parameters are allowed: WHERE, ORDER BY, LIMIT, OFFSET, DOCUMENTS, mutator values, function arguments
4. **Path expressions** — `field`, `field.nested`, `field[index]`, `_id`
5. **`ANY ... IN ... SATISFIES ... END`** with example testing nested objects in `cast`
6. **`EVERY ... IN ... SATISFIES ... END`** with empty-input semantics
7. **`ANY AND EVERY ... IN ... SATISFIES ... END`** — every + non-empty
8. **`IN` vs `WITHIN`** — direct children vs recursive descent. Warn about the `WITHIN` + `IS MISSING` surprise.
9. **`ARRAY ... FOR ... IN ... [WHEN ...] END`** array comprehension
10. **`OBJECT k:v FOR ... IN ... [WHEN ...] END`** object comprehension
11. **CASE — simple form** `CASE expr WHEN val THEN result ... ELSE default END`
12. **CASE — searched form** `CASE WHEN cond THEN result ... ELSE default END`

Each section gets one runnable example against `movies` or `reviews`.

- [ ] **Step 3: Verify**

```bash
grep -E "XOR|ADVISE|serialize_json|object_size|DO MERGE" plugins/ditto-dql/skills/dql/references/expressions.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/expressions.md
git commit -m "docs(ditto-dql): add expressions reference with CASE, SATISFIES, comprehensions"
```

---

### Task 7: Write `references/statements.md`

Cover every statement EXCEPT `SELECT` (which gets its own file in Task 8) and indexing DDL (Task 10).

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/statements.md`

- [ ] **Step 1: Confirm the v5.0.0 Statement enum**

```bash
awk '/pub enum Statement/,/^}/' /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-shared/src/ast/mod.rs
```

Expected: Explain, Query, Insert, Update, Remove, AlterSystem, Show, RemoteQuery, CreateIndex, DropIndex.

- [ ] **Step 1.5: Read the version audit**

Annotate every statement with its min SDK. In particular:
- `DO UPDATE_LOCAL_DIFF`: SDK 4.12+
- `COUNTER` mutations (`APPLY ... INCREMENT BY`, `RESTART WITH`): SDK 4.13+ for COUNTER specifically (PN_COUNTER 4.11+)
- `RETURNING`: verify v4.14.x supports it; tag accordingly
- `TOMBSTONE`, `SYNC CONTEXT`: verify v4.14.x supports them; tag if v5-only

- [ ] **Step 2: Author the file** with these sections:

1. **`INSERT`** — full grammar incl. `INTO COLLECTION cols(...)`, `DOCUMENTS`, `VALUES`, `INITIAL`, `ON ID CONFLICT FAIL|DO NOTHING|DO UPDATE|DO UPDATE_LOCAL_DIFF`, `RETURNING`. **Do not document `DO MERGE`.** Tag `DO UPDATE_LOCAL_DIFF` as **4.12+**. Tag `RETURNING` per the audit.
2. **`UPDATE`** — `SET`, `UNSET`, `APPLY` for counters (`INCREMENT BY n`, `RESTART [WITH v]`), `WHERE`, `ORDER BY`, `LIMIT`, `OFFSET`, `RETURNING`. Note: **no `USE IDS` on UPDATE in v5.0.0.**
3. **`EVICT`** — local Small-Peer deletion; does not replicate.
4. **`TOMBSTONE`** — mesh-wide replicating deletion; Big-Peer-only behaviour.
5. **`DELETE`** — alias that resolves to EVICT or TOMBSTONE based on context.
6. **`EXPLAIN`** — wraps any of the above (use `EXPLAIN SELECT ...`).
7. **`ALTER SYSTEM`** — `SET key = value`, `RESET key`, `RESET ALL`. Note memory-only persistence.
8. **`SHOW`** — `SHOW ALL`, `SHOW name`, with `LIKE` / `ILIKE` filter syntax.
9. **`SYNC CONTEXT`** — peer-targeting wrapper for `SELECT` and `SHOW` (RemoteQuery). Note Big-Peer-only.
10. **PROFILE caveat** — `PROFILE SELECT ...` is accepted by the parser as a `#profile` directive. It returns plan timing data; output shape may evolve. **Do not document `ADVISE` or `ADVISE AND PROVISION` — not supported in v5.0.0.**

- [ ] **Step 3: Verification grep**

```bash
grep -E "ADVISE|DO MERGE|USE IDS.*UPDATE|USE IDS.*EVICT|USE IDS.*TOMBSTONE|USE IDS.*DELETE" plugins/ditto-dql/skills/dql/references/statements.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/statements.md
git commit -m "docs(ditto-dql): add statements reference (INSERT/UPDATE/EVICT/TOMBSTONE/etc)"
```

---

### Task 8: Write `references/select.md`

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/select.md`

- [ ] **Step 1: Confirm USE IDS is SELECT-only**

```bash
grep -n "USE IDS\|use_ids" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-shared/src/ast/query.rs
```

Expected: comment `// USE IDS` at ~line 38.

```bash
grep -n "TODO add USE IDS" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/parser.rs
```

Expected: matches in `parse_remove_statement` and `parse_update_statement` confirming USE IDS is missing on mutations.

- [ ] **Step 1.5: Read the version audit**

Annotate clauses where v4.14.x and v5.0.0 differ. Specifically: subscription constraint flags (`DQL_RESTRICT_LIMIT_ORDER_BY`) may differ in defaults across versions — check.

- [ ] **Step 2: Author the file** with these sections:

1. **Projection** — `SELECT *`, specific expressions, `AS` aliases, `DISTINCT`
2. **`FROM`** — collection name, backticks, optional datasource prefix `ds:collection`
3. **`USE IDS`** — single id, id list, parameter form `USE IDS LIST :ids` — note **SELECT-only in v5.0.0**
4. **`USE INDEX`** — by name with ASC/DESC
5. **`USE DIRECTIVES`** — JSON-object form
6. **`WHERE`** — examples using comparisons, ANY/EVERY/SATISFIES, `array_contains`
7. **`GROUP BY`** — single + multi-key
8. **`HAVING`** — filtering aggregates
9. **`ORDER BY`** — multi-key, ASC/DESC, NULL/MISSING sort order
10. **`LIMIT` / `OFFSET`** — including parameter binding
11. **Cross-type sort order** — Bool < Numeric < Binary < String < Array < Object < NULL < MISSING
12. **Subscription patterns** — what is and isn't allowed in subscriptions (no ORDER BY, no LIMIT — driven by `DQL_RESTRICT_LIMIT_ORDER_BY` flag). This closes the README gap.

- [ ] **Step 3: Verify**

```bash
grep -E "USE IDS.*UPDATE|USE IDS.*EVICT|USE IDS.*TOMBSTONE|USE IDS.*DELETE" plugins/ditto-dql/skills/dql/references/select.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/select.md
git commit -m "docs(ditto-dql): add SELECT reference and document subscription constraints"
```

---

### Task 9: Write `references/types-mutators.md`

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/types-mutators.md`

- [ ] **Step 1: Confirm CRDT type names in v5.0.0**

```bash
grep -rni "REGISTER\|PN_COUNTER\|COUNTER\|ATTACHMENT\|MAP" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/keywords.rs
```

Expected: all five present.

- [ ] **Step 1.5: Read the version audit**

Carry forward the known min-versions:
- COUNTER: 4.13+
- PN_COUNTER: 4.11+
- DO UPDATE_LOCAL_DIFF: 4.12+
- ATTACHMENT: confirm from audit
- Strict-mode default flip: v4 default = strict, v5 default = lenient — call this out with a "Cross-version notes" block

- [ ] **Step 2: Author the file** with sections for each CRDT type:

1. **`REGISTER`** — last-write-wins; the default when no type is declared.
2. **`MAP`** — nested CRDT object; field-level merges. Document the `MAP(field TYPE, ...)` declaration syntax used in INSERT.
3. **`COUNTER`** — distributed counter (state-based). `APPLY ... INCREMENT BY n`, `RESTART [WITH v]`. Note SDK version: COUNTER landed in 4.13.
4. **`PN_COUNTER`** — legacy positive-negative counter. `INCREMENT BY` only, no `RESTART`. Available from 4.11.
5. **`ATTACHMENT`** — binary blob with `id`/`len`/`metadata` fields. Show INSERT example. Mention >250KB recommendation.
6. **Type-definition syntax on INSERT** — `INSERT INTO COLLECTION movies (director MAP(name REGISTER, born REGISTER), ratings MAP, watch_count COUNTER) DOCUMENTS (...)`
7. **Strict mode interaction** — `DQL_MUTATOR_OBJECTS_AS_MAPS` flag; if off (strict on), objects on INSERT/UPDATE become REGISTERs unless explicitly typed. v5.0 default is OFF (strict). Defer detailed strict-mode discussion to `best-practices.md`.

- [ ] **Step 3: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/types-mutators.md
git commit -m "docs(ditto-dql): add CRDT types and mutators reference"
```

---

### Task 10: Write `references/indexing.md`

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/indexing.md`

- [ ] **Step 1: Confirm CREATE INDEX in v5.0.0**

```bash
sed -n '3139,3175p' /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/parser.rs
```

Expected: see the `parse_create_index` function header.

- [ ] **Step 2: Confirm ADVISE is absent**

```bash
grep -i "ADVISE" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/keywords.rs
```

Expected: no output.

- [ ] **Step 2.5: Read the version audit**

Confirm CREATE INDEX, DROP INDEX, planner directives, `#profile` directive availability in v4.14.x and tag any deltas.

- [ ] **Step 3: Author the file** with sections:

1. **`CREATE INDEX`** — full grammar: `CREATE INDEX [IF NOT EXISTS] name ON collection(key [ASC|DESC], ...) [INCLUDE|EXCLUDE MISSING]`. Alternative form `CREATE INDEX collection.name(...)`.
2. **`DROP INDEX`** — `DROP INDEX [IF EXISTS] name [ON collection]`
3. **Planner directives**
   - Comment form: `/*+ {"#disable_index_scan": true} */` or `--+ {...}`
   - Clause form: `USE DIRECTIVES { ... }`
   - Recognized keys: `#disable_index_scan`, `#disable_covering`, `#prefer_order`, `#intersects`, `#max_scans`, `#max_inlist`, `#max_serial_ranges`, `#auto_use_ids`, `#profile`, `#disable_special`, `#disable_intersect_eo`, `#reprepare`, `#disable_dml`. (Per-collection: `#prefer_order`, `#intersects`, `#index`.)
4. **`USE IDS`** — direct id lookup on `SELECT` only (cite the SELECT reference).
5. **`USE INDEX`** — index-name selection hint.
6. **`EXPLAIN`** — query-plan output. Show example output with `index_scan` (good), `collection_scan` (slow), `intersect`, `union`.
7. **`#profile` directive** — section titled "Profiling a query in v5.0.0". Show `PROFILE SELECT * FROM movies WHERE ...` and `SELECT /*+ {"#profile": true} */ * FROM movies WHERE ...`. Note: output shape will change in v5.1.0; for now read the timing/scan counts from the returned `#profile` blob.
8. **Indexing strategy** — ESR rule (Equality, Sort, Range), covering indexes, when not to index (write-heavy collections). Carry this content over from existing `best-practices.md` if it's there.
9. **Excluded:** clearly note that `ADVISE` and `ADVISE AND PROVISION` are v5.1.0 features and not available here.

- [ ] **Step 4: Verify**

```bash
grep -E "ADVISE\b" plugins/ditto-dql/skills/dql/references/indexing.md
```

Expected: only matches inside the "Excluded" note, if at all.

- [ ] **Step 5: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/indexing.md
git commit -m "docs(ditto-dql): add indexing reference with #profile and planner directives"
```

---

### Task 10b: Write `references/versions.md` (SDK compatibility matrix)

The user-facing single-pane compatibility document. Everything tagged in the other reference files gets summarized here.

**Files:**
- Create: `plugins/ditto-dql/skills/dql/references/versions.md`

- [ ] **Step 1: Re-read the audit document**

```bash
cat docs/superpowers/plans/2026-05-26-dql-versions-audit.md
```

- [ ] **Step 2: Author `references/versions.md`** with these sections:

```markdown
---
title: Ditto SDK Version Compatibility
description: Which DQL features work on which Ditto SDK versions, and how to know which version applies to you.
---

# Ditto SDK Version Compatibility

This skill covers DQL as it ships in the Ditto SDK lines below. Every feature in the reference files (`statements.md`, `select.md`, `operators.md`, `functions.md`, `expressions.md`, `types-mutators.md`, `indexing.md`) carries an `Available in:` tag with its minimum SDK version.

## Supported SDK lines

| Line   | Status                | Notes |
|--------|----------------------|-------|
| 4.14.x | LTS, still supported | Strict-mode default; conservative feature set |
| 5.0.x  | Current shipped      | Lenient-mode default; full feature set |

## Not yet supported by this skill (coming in v5.1.0)

These are real features in the upcoming v5.1.0 SDK but are intentionally excluded from this skill until v5.1.0 ships:

- `ADVISE` and `ADVISE AND PROVISION` statements
- Structured `PROFILE` statement output (the `#profile` directive works today — see `indexing.md`)
- `XOR` operator
- `INSERT ... ON ID CONFLICT DO MERGE`
- `serialize_json()`, `object_size()` functions
- `USE IDS` on `UPDATE` / `DELETE` / `EVICT` / `TOMBSTONE` (today, use `WHERE _id IN (...)`)

When v5.1.0 ships, these will be added to the skill in a follow-up plan and tagged `> Available in: Ditto SDK 5.1+`.

## Feature matrix (summary)

### Statements

| Statement      | 4.14.x | 5.0.x | Notes |
|----------------|--------|-------|-------|
| SELECT         |   ✓    |   ✓   | |
| INSERT         |   ✓    |   ✓   | `DO UPDATE_LOCAL_DIFF` is 4.12+ |
| UPDATE         |   ✓    |   ✓   | |
| EVICT / TOMBSTONE / DELETE | <fill from audit> |   ✓   | |
| EXPLAIN        | <fill> |   ✓   | |
| ALTER SYSTEM   | <fill> |   ✓   | |
| SHOW           | <fill> |   ✓   | |
| SYNC CONTEXT   | <fill> |   ✓   | |
| CREATE INDEX   | <fill> |   ✓   | |
| DROP INDEX     | <fill> |   ✓   | |

### Expressions

| Construct                         | 4.14.x | 5.0.x | Notes |
|-----------------------------------|--------|-------|-------|
| CASE (simple + searched)          | <fill> |   ✓   | |
| ANY/EVERY ... SATISFIES           | <fill> |   ✓   | |
| ARRAY FOR / OBJECT FOR comprehensions | <fill> | ✓ | |
| Parameter binding `:name`         |   ✓    |   ✓   | |
| Path expressions                  |   ✓    |   ✓   | |

### CRDT types

| Type        | Min SDK | Notes |
|-------------|---------|-------|
| REGISTER    | 4.x     | always available; default |
| MAP         | 4.x     | always available |
| ATTACHMENT  | <fill>  | |
| PN_COUNTER  | 4.11+   | |
| COUNTER     | 4.13+   | |

### Defaults that flip between versions

| Behavior                     | 4.14.x default | 5.0.x default |
|------------------------------|----------------|----------------|
| Strict mode                  | strict (on)    | lenient (off)  |
| `DQL_MUTATOR_OBJECTS_AS_MAPS`| ?              | ?              |

(Fill the `?` cells from the audit.)

## Finding out which version you're on

```sql
-- Returns the SDK version Ditto was compiled with
SHOW dql_version
SHOW ditto_version
```

(Confirm the exact `SHOW` parameter name from the audit.)

Or check the SDK package version in your application code (`Ditto.swift` / `build.gradle` / `package.json`).

## Why this matters

Writing a query that uses a v5-only construct against a v4.14.x peer will fail at parse time on the v4 peer. In a mixed-version mesh, write to the lowest common denominator.
```

- [ ] **Step 3: Commit**

```bash
git add plugins/ditto-dql/skills/dql/references/versions.md
git commit -m "docs(ditto-dql): add SDK version compatibility matrix"
```

---

### Task 11: Fill in `examples/movies-cookbook.md` (18 tasks)

Take the 23-task internal cookbook and drop tasks that rely on v5.1.0-only features. Reuse the file stubbed in Task 3.

**Source to filter:** `/Users/labeaaa/Developer/ditto-v5-experiments/.claude/skills/dql/examples/movies-cookbook.md`

**Drop or rewrite:**
- Task 20 (ADVISE / ADVISE AND PROVISION) — **DROP entirely**
- Task 19 (PROFILE for diagnosis) — **REWRITE** using `#profile` directive output rather than structured PROFILE statement output
- Any task using `serialize_json`, `object_size`, `DO MERGE`, `XOR` — **DROP**
- Any task using `USE IDS` on UPDATE/DELETE/EVICT/TOMBSTONE — **REWRITE** to use WHERE id IN (...)

**Version-tag each task header** with the lowest SDK version it works on, e.g.:

```markdown
## Task 11 — Increment watch counter

> **Available in:** Ditto SDK 4.13+ (COUNTER type)
```

Most tasks will work on v4.14.x. Tasks that require COUNTER (4.13+), PN_COUNTER (4.11+), `DO UPDATE_LOCAL_DIFF` (4.12+), or any feature flagged 5.0+ by the audit get the corresponding tag. The schema-block at the top of the cookbook also gets a note: "This dataset uses COUNTER for `watch_count`, requiring SDK 4.13+. For older SDKs, substitute a REGISTER and use SET."

**Keep (numbering for the public cookbook):**

1. Load movies with conflict-tolerant upserts (`INSERT ... ON ID CONFLICT DO UPDATE`) — internal task 1
2. Seed reviews with auto-generated ids — internal task 2
3. Top-rated movies in decade with pagination — internal task 3
4. Single-document lookup fastest path (`USE IDS` on `SELECT`) — internal task 4
5. Films featuring a specific actor (`ANY ... IN cast SATISFIES`) — internal task 5
6. Films in any of N genres (`ANY ... SATISFIES` on array) — internal task 6
7. Flat view with computed fields (`CASE`, `ARRAY FOR`) — internal task 7
8. Director leaderboard (GROUP BY, aggregates) — internal task 8
9. Per-movie review statistics — internal task 9
10. Two-step join: top movies by review average — internal task 10
11. Increment watch counter (`UPDATE ... APPLY ... INCREMENT BY`) — internal task 11
12. Update nested map without clobbering siblings — internal task 12
13. Flag pre-1980 films as classics with `RETURNING` — internal task 13
14. Remove a derived field post-backfill (`UNSET`) — internal task 14
15. Reset watch counter on re-release (`APPLY ... RESTART WITH`) — internal task 15
16. Local cleanup of pre-1950 films (`EVICT`) — internal task 16
17. Mesh-wide retraction of a withdrawn film (`TOMBSTONE`) — internal task 17
18. Bulk delete with id list (`DELETE ... WHERE _id IN (...)` — **rewritten** away from `USE IDS LIST`) — adapted from internal task 18

- [ ] **Step 1: For each kept task, copy the body from the internal cookbook and adjust where noted above**

For Task 18 specifically, the internal cookbook uses `DELETE FROM movies USE IDS LIST :ids`. Rewrite to:

```sql
DELETE FROM movies WHERE _id IN ('tt0000001', 'tt0000002', 'tt0000003')
```

…and call out in the explanation that `USE IDS` on `DELETE` is a v5.1.0 feature; use a `_id IN (...)` WHERE clause in v5.0.0.

- [ ] **Step 2: Add a final section "Diagnosing performance in v5.0.0"**

```sql
-- Get plan structure only
EXPLAIN SELECT * FROM movies WHERE year BETWEEN 1990 AND 2000

-- Execute and capture timing via the #profile directive
SELECT /*+ {"#profile": true} */ *
FROM movies
WHERE year BETWEEN 1990 AND 2000
ORDER BY box_office_millions DESC

-- Equivalent leading-keyword form
PROFILE SELECT * FROM movies
WHERE year BETWEEN 1990 AND 2000
ORDER BY box_office_millions DESC
```

Note: in v5.1.0 the SDK adds a structured `PROFILE` output shape and an `ADVISE` statement; until you upgrade, read the `#profile` blob in the result.

- [ ] **Step 3: Run the verification grep**

```bash
grep -nE "ADVISE\b|DO MERGE|serialize_json|object_size|XOR|USE IDS LIST" plugins/ditto-dql/skills/dql/examples/movies-cookbook.md
```

Expected: zero matches (except possibly an explanatory mention inside a "v5.1.0-only" callout).

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/dql/examples/movies-cookbook.md
git commit -m "docs(ditto-dql): add 18-task movies cookbook (v5.0.0-safe)"
```

---

### Task 12: Rewrite `SKILL.md` as the entry point

The new SKILL.md is short. It establishes the mental model and routes to the right reference file based on what the user is doing.

**Files:**
- Modify: `plugins/ditto-dql/skills/dql/SKILL.md`

- [ ] **Step 1: Replace SKILL.md contents with:**

```markdown
---
name: write-dql
description: Use when writing DQL (Ditto Query Language) — SELECT/INSERT/UPDATE/EVICT/TOMBSTONE/DELETE statements, subscriptions, CRDT types, query optimization (EXPLAIN/#profile), or ALTER SYSTEM/SHOW config. Covers Ditto SDK 4.14.x through 5.0.x. Confirm the user's SDK version before answering — feature support varies.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# DQL — Ditto Query Language

DQL is Ditto's SQL-like language for querying and mutating documents in a CRDT-aware, peer-to-peer database. It looks like SQL, but the semantics are different in three ways that matter every day:

1. **No joins, no subqueries, no UNION.** One `FROM` per statement.
2. **`NULL` and `MISSING` are distinct.** `NULL` = field exists, value is null. `MISSING` = field is absent. They behave differently in every operator.
3. **Every field is a CRDT.** The CRDT type (REGISTER, MAP, COUNTER, PN_COUNTER, ATTACHMENT) controls how concurrent edits merge.

## First: which SDK version is the user on?

DQL features land version by version. **Before answering a non-trivial DQL question, confirm the SDK version.** If the user has not said which Ditto SDK they're on, ask:

> "Which Ditto SDK version is this for? I support guidance for 4.14.x through 5.0.x."

If they don't know, ask them to check the SDK package version in their project (`Ditto.swift` / `build.gradle` / `package.json`) — or to run `SHOW dql_version`. Then filter the rest of the conversation to features available in that version (see `references/versions.md`).

If the user explicitly says "give me the latest" or "use the newest" without picking a version, default to 5.0.x and say so.

## Where to look

| If you're doing this... | Read |
|---|---|
| Picking which features apply to your SDK version | `references/versions.md` |
| Writing a `SELECT` | `references/select.md` |
| Writing `INSERT` / `UPDATE` / `EVICT` / `TOMBSTONE` / `DELETE` / `ALTER SYSTEM` / `SHOW` / `SYNC CONTEXT` | `references/statements.md` |
| Looking up an operator's precedence or NULL/MISSING behaviour | `references/operators.md` |
| Looking up a built-in function | `references/functions.md` |
| Writing `CASE`, `ANY ... SATISFIES`, `ARRAY FOR`, parameter binding | `references/expressions.md` |
| Declaring CRDT types in `INSERT`, picking COUNTER vs PN_COUNTER, using ATTACHMENT | `references/types-mutators.md` |
| `CREATE INDEX`, `EXPLAIN`, profiling with `#profile`, planner directives | `references/indexing.md` |
| Designing schemas, schema versioning, strict mode, timestamps | `best-practices.md` |
| Want a runnable end-to-end example | `examples/movies-cookbook.md` |

## Five things that bite people

1. **Use `AND` / `OR` / `NOT` keywords**, not `&&` / `||` / `!`.
2. **Single quotes for strings**, double quotes are not strings.
3. **`= NULL` is always NULL**, not TRUE. Use `IS NULL` / `IS NOT NULL` / `IS MISSING`.
4. **`INSERT` requires an explicit `ON ID CONFLICT`** for upserts. Default is FAIL.
5. **`EVICT` is local-only and reversible** (other peers will re-sync). **`TOMBSTONE` is mesh-wide and permanent** (subject to TTL). Don't mix them up.

## Compatibility

This skill covers **Ditto SDK 4.14.x through 5.0.x**. Every feature in the reference files is tagged with its minimum SDK version. See `references/versions.md` for the full matrix.

Some features land in v5.1.0 (still upcoming) and are intentionally excluded from this skill — they will be added in a follow-up when v5.1.0 ships:

- `ADVISE` / `ADVISE AND PROVISION` statements — use `EXPLAIN` and the indexing patterns in `references/indexing.md`
- Structured `PROFILE` output — use the `#profile` directive (see `references/indexing.md`)
- `XOR` operator
- `INSERT ... ON ID CONFLICT DO MERGE`
- `serialize_json()`, `object_size()` functions
- `USE IDS` on `UPDATE` / `DELETE` / `EVICT` / `TOMBSTONE` — use `WHERE _id IN (...)` instead

## Decision tree for query problems

```
Need to read documents?
├── By known id(s)?         → USE IDS on SELECT (references/select.md)
├── With aggregation?       → GROUP BY + aggregates (references/select.md)
├── Across array elements?  → ANY ... IN ... SATISFIES (references/expressions.md)
└── Otherwise               → WHERE clause (references/select.md, references/operators.md)

Need to write documents?
├── Adding new?       → INSERT (references/statements.md)
├── Modifying?        → UPDATE with SET / UNSET / APPLY (references/statements.md)
└── Removing?         → EVICT (local) or TOMBSTONE (mesh) (references/statements.md)

Need to make it fast?
├── See the plan?     → EXPLAIN (references/indexing.md)
├── See timing?       → #profile directive (references/indexing.md)
└── Add an index?     → CREATE INDEX (references/indexing.md)
```
```

- [ ] **Step 2: Commit**

```bash
git add plugins/ditto-dql/skills/dql/SKILL.md
git commit -m "docs(ditto-dql): rewrite SKILL.md as routing entry point"
```

---

### Task 13: Update `best-practices.md` to align with the new structure

The existing content (strict mode, schema versioning, timestamps, soft delete) is valuable and the internal v5.1.0 skill does **not** cover most of it. Keep it. Update cross-references only.

**Files:**
- Modify: `plugins/ditto-dql/skills/dql/best-practices.md`

- [ ] **Step 1: Replace any link to `dql-operators.md` with `references/operators.md` or `references/functions.md`**

```bash
grep -n "dql-operators" plugins/ditto-dql/skills/dql/best-practices.md
```

Fix every match.

- [ ] **Step 2: Add cross-references to the new reference files**

In the schema/strict-mode section, link to `references/types-mutators.md` for CRDT type docs.
In the indexing section, link to `references/indexing.md` for `EXPLAIN` / `#profile` / `CREATE INDEX` details.
In the pagination section, link to `references/select.md`.

- [ ] **Step 3: Strip or correct any v5.1.0-only assertions**

```bash
grep -E "ADVISE|XOR|serialize_json|object_size|DO MERGE|USE IDS.*UPDATE|USE IDS.*DELETE" plugins/ditto-dql/skills/dql/best-practices.md
```

Expected: no output. Remove or correct any matches.

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/skills/dql/best-practices.md
git commit -m "docs(ditto-dql): retarget best-practices cross-refs to references/"
```

---

### Task 14: Update `agents/dql-expert.md`

The agent must load the right skill at the right path.

**Files:**
- Modify: `plugins/ditto-dql/agents/dql-expert.md`

- [ ] **Step 1: Read the current agent file**

```bash
cat plugins/ditto-dql/agents/dql-expert.md
```

- [ ] **Step 2: Update references**

- The skill is now at `skills/dql/` (renamed from `skills/write-dql/`); change every path reference accordingly.
- The skill's frontmatter `name:` remains `write-dql` for stable activation — DO NOT change it without checking other callers. (Confirmed in Task 12.)
- Update the agent's workflow paragraph to mention the new reference files: when a user asks about an operator, read `references/operators.md`; when about a function, read `references/functions.md`; etc.

- [ ] **Step 3: Add the SDK-version-detection workflow to the agent**

Insert (or replace any existing compatibility paragraph) this block in the agent's instructions:

```markdown
## Determining the user's Ditto SDK version

Before answering any non-trivial DQL question, you MUST know which Ditto SDK version the user is targeting. The supported range for this skill is **4.14.x through 5.0.x**.

1. If the user's first message states a version, use it.
2. If the user does not state a version, ASK before answering:
   > "Which Ditto SDK version is this for? I support guidance for 4.14.x through 5.0.x. If you're not sure, check your project's Ditto package version, or run `SHOW dql_version`."
3. If the user says "the latest" or "newest" without a version, default to 5.0.x and tell them: "Assuming SDK 5.0.x — let me know if you need 4.14.x answers."
4. Once the version is known, filter the rest of the conversation:
   - Don't recommend features tagged with a higher minimum SDK version than the user's
   - When suggesting a feature that's gated by version, prefer a version-safe alternative if one exists
   - When asked about v5.1.0-only features (ADVISE, structured PROFILE, DO MERGE, XOR, serialize_json, object_size, USE IDS on mutations), explain they're not yet shipped and propose a workaround
5. Always consult `references/versions.md` when unsure — it's the authoritative compatibility matrix.
```

- [ ] **Step 4: Commit**

```bash
git add plugins/ditto-dql/agents/dql-expert.md
git commit -m "docs(ditto-dql): point dql-expert at new skill structure and require SDK version detection"
```

---

### Task 15: Bump plugin manifest and refresh README

**Files:**
- Modify: `plugins/ditto-dql/.claude-plugin/plugin.json`
- Modify: `plugins/ditto-dql/README.md`

- [ ] **Step 1: Bump version**

In `plugin.json`, change `"version": "1.0.0"` to `"version": "2.0.0"`.

- [ ] **Step 2: Update README** to reflect the new structure

Carry over the file map from this plan and the compatibility note. Mention movies cookbook and link to it. Drop any claim about subscription patterns that the skill doesn't deliver (subscriptions are now genuinely covered in `references/select.md` — keep the claim).

Add a prominent "Supported SDK versions" line near the top of README:

```markdown
## Supported Ditto SDK versions

- Ditto SDK **4.14.x** (LTS)
- Ditto SDK **5.0.x** (current)

Every documented feature is tagged with its minimum SDK version. See [`skills/dql/references/versions.md`](skills/dql/references/versions.md) for the full compatibility matrix. v5.1.0 features are excluded until v5.1.0 ships.
```

Add `multi-version` to the manifest's `keywords` array.

- [ ] **Step 3: Commit**

```bash
git add plugins/ditto-dql/.claude-plugin/plugin.json plugins/ditto-dql/README.md
git commit -m "chore(ditto-dql): bump to 2.0.0 and refresh README for new structure"
```

---

### Task 16: Final compatibility audit pass

A single sweep across the entire skill to catch any leaked v5.1.0-only feature.

- [ ] **Step 1: Run an exclusion grep across the whole skill**

```bash
grep -rnE "ADVISE\b|\\bXOR\\b|serialize_json|object_size|DO MERGE|USE IDS LIST" plugins/ditto-dql/
```

Expected: no matches (or only matches inside explicit "v5.1.0-only" compatibility-warning blocks in SKILL.md).

- [ ] **Step 2: Run a USE-IDS-on-mutation grep**

```bash
grep -rnE "(UPDATE|DELETE|EVICT|TOMBSTONE)[[:space:]]+.*USE IDS" plugins/ditto-dql/
```

Expected: no matches.

- [ ] **Step 3: For every function name appearing in `references/functions.md`, confirm it exists in v5.0.0**

```bash
for fn in $(grep -oE "^\\| \\`[a-z_]+\\(" plugins/ditto-dql/skills/dql/references/functions.md | tr -d '|`( ' | sort -u); do
  if ! grep -rqi "\"$fn\"\\|fn $fn\\b" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql/src/functions/; then
    echo "MISSING in v5.0.0: $fn"
  fi
done
```

Expected: empty output. Any function flagged here must be removed from the doc or moved to a "v5.1.0-only" section.

- [ ] **Step 4: For every documented statement keyword, confirm it's in v5.0.0 keywords**

```bash
for kw in INSERT UPDATE EVICT TOMBSTONE DELETE EXPLAIN ALTER SYSTEM SHOW SYNC CONTEXT CREATE INDEX DROP; do
  if ! grep -qE "^    $kw,\\b" /Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/keywords.rs; then
    echo "MISSING keyword: $kw"
  fi
done
```

Expected: empty output.

- [ ] **Step 4b: Verify version annotations are present and well-formed**

```bash
# Every reference file should contain at least one Available-in tag
for f in plugins/ditto-dql/skills/dql/references/{statements,select,operators,functions,expressions,types-mutators,indexing}.md; do
  if ! grep -q "Available in:" "$f"; then
    echo "NO VERSION TAGS in: $f"
  fi
done

# Find any malformed tags (typos in the convention)
grep -rn "Available in" plugins/ditto-dql/skills/dql/references/ | grep -v "Available in:\\*\\*"
```

Expected: no "NO VERSION TAGS" lines; no malformed tags reported.

- [ ] **Step 4c: Verify no reference file claims a feature is available in a version it isn't**

For each Available-in tag, cross-check the audit:

```bash
# List every distinct version tag used across the skill
grep -rhE "Available in:\\*\\* Ditto SDK [0-9]+\\.[0-9]+" plugins/ditto-dql/skills/dql/references/ | sort -u
```

Then manually verify each tagged version exists in the audit's "Functions present in v4.14.x" / "Functions present in v5.0.0" / "Cross-version" sections. Anything tagged `4.x` should be in the v4 audit YES list. Anything tagged `5.0+` should be `v4 NO` AND `v5.0 YES`.

- [ ] **Step 4d: Verify SKILL.md and agent file enforce version detection**

```bash
grep -l "Which Ditto SDK version" plugins/ditto-dql/skills/dql/SKILL.md plugins/ditto-dql/agents/dql-expert.md
```

Expected: both files listed.

- [ ] **Step 5: Tag and commit the audit log**

If any of the above produced unexpected output, fix the docs and re-run before committing. Once clean:

```bash
git commit --allow-empty -m "test(ditto-dql): pass final v5.0.0 compatibility audit"
```

---

## Self-review pass

Run through this list against the plan above before declaring done.

**1. Spec coverage:** the user's spec was "improve the DQL skills based on the v5.1.0 internal skill, ensure it works in v5.0.0 AND v4.14.x, version-tag every feature, and prepare for a v5.1.0 add later."
- v4.14.x compatibility audit → Task 0
- Skill restructure → Task 1
- Bug fixes from current plugin → Task 2
- Cookbook ported (with per-task version tags) → Tasks 3 + 11
- Operators + 4-valued logic + version tags → Task 4
- Function catalog with per-function min-SDK column → Task 5
- Expressions (CASE / SATISFIES / comprehensions) with version tags → Task 6
- Statements (incl. TOMBSTONE, SYNC CONTEXT, DO UPDATE_LOCAL_DIFF tagged 4.12+) → Task 7
- SELECT (incl. subscription constraints) → Task 8
- CRDT types with version tags (COUNTER 4.13+, PN_COUNTER 4.11+) + strict-mode cross-version block → Task 9
- Indexing + #profile, version-tagged → Task 10
- **SDK compatibility matrix (`references/versions.md`)** → Task 10b
- SKILL.md routing + version-detection guidance → Task 12
- Best-practices retargeted → Task 13
- Agent updated with mandatory version-detection workflow → Task 14
- Manifest + README + `multi-version` keyword + supported-versions block → Task 15
- Audit (incl. version-tag presence + correctness) → Task 16

Every v5.0.0-safe v5.1.0 feature gets a home with the right min-SDK tag. Every v5.1.0-only feature is excluded but cataloged in `versions.md` for the follow-up plan. Every reference file consults the audit document produced by Task 0.

**2. Placeholders:** every step has either a concrete file path, a concrete grep command, or a complete content block. No "TBD" / "add appropriate" / "similar to Task N".

**3. Type/name consistency:**
- The skill folder is `skills/dql/` throughout; the YAML frontmatter `name:` stays `write-dql` (preserves stable activation key)
- Reference paths are `skills/dql/references/<file>.md` everywhere
- Cookbook path is `skills/dql/examples/movies-cookbook.md` everywhere
- The plugin version bump is 1.0.0 → 2.0.0 in Task 15 (consistent with the new file layout being a breaking change)

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-26-dql-skill-v5-update.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks. Best for a 16-task plan where each task has well-defined inputs and outputs.
2. **Inline Execution** — work tasks in this session with checkpoints.

Which approach?
