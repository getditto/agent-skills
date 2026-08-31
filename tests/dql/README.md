# DQL Skill Tests

Automated tests that run every DQL example query in the `ditto-dql` skill against actual Ditto Node SDK installations. The harness proves that every documented query works on the SDK version it claims to support, and that the version-availability tags are honest.

## Current status

| SDK | PASS | PASS-AS-EXPECTED-FAIL | FAIL | FAIL-ASSERTION |
|---|---|---|---|---|
| `@dittolive/ditto@4.14.4` | 196 | 54 | 0 | 0 |
| `@dittolive/ditto@5.0.0`  | 213 | 37 | 0 | 0 |
| `@dittolive/ditto@5.1.0`  | 242 | 8  | 0 | 0 |

Catalog size: **250 entries** (plus 26 ignored) extracted from `skills/dql/**/*.md`, covering two datasets: `movies-pedagogical` (194 docs) and `retail-1k` (4,859 docs across 8 collections — from the dql-metrics `retail-joins-1k` benchmark fixture).

**Strict-mode baseline:** the runner sets `ALTER SYSTEM SET dql_strict_mode = false` at startup and re-asserts it before every catalog entry, matching the skill's documented assumption (lenient mode on every peer — the 5.x default and the 4.x migration target). On 4.14.4 this flips the peer off its strict factory default; the catalog's own `ALTER SYSTEM` examples can therefore not leak flag state into neighboring entries.

## How it works

1. **Extraction.** `scripts/extract-queries.mjs` walks every `.md` file under `skills/dql/`, pulls every ` ```sql ` code block, and emits a draft catalog entry per query. Each entry has an ID that's a stable hash of `(file, line, query text)`.

2. **Curation.** `scripts/curate-catalog.mjs` splits multi-statement blocks (paren-depth aware, so subqueries aren't chopped), substitutes concrete values for `:param` placeholders, marks version-gated features with `availableIn`, strips statement-terminator semicolons (the SDK takes exactly one statement, no `;`), ignores `SELECT`s with no top-level `FROM` clause, and applies the manual decisions in `catalog/overrides.json` — version corrections for features the tested SDKs don't actually ship, plus ignores with reasons. Entry IDs are stable: a hash of the repo-relative `(file, line, query)`, independent of machine and repo location.

3. **Transformation.** `scripts/transform-dataset.mjs` reads the real `~/Developer/dql-metrics/benchmarks/skills-test/movies.ndjson`, strides across it for an even era distribution, and writes 194 pedagogical-schema docs to `fixtures/movies-pedagogical.ndjson`. This is committed to the repo. The `fixtures/retail/*.ndjson` files come from the dql-metric's `retail-joins-1k` benchmark suite (committed as-is) and are seeded alongside the movies data by `seed-store.mjs`.

4. **Execution.** `runner/run.mjs` (one invocation per SDK version) opens a Ditto Small Peer using the version-shim, seeds the movies dataset, and runs every catalog entry as `[preQueries], query, [postQueries]`. Results are classified and written to `results/<version>.json`.

5. **Reporting.** `scripts/report.mjs` produces a unified pass/fail table across versions.

## Supported versions

- `@dittolive/ditto@4.14.4` (LTS)
- `@dittolive/ditto@5.0.0`
- `@dittolive/ditto@5.1.0` (current — JOINs, composite indexes, RETURNING, ADVISE)

Each SDK lives in its own `node_modules` tree under `sdks/v<version>/` because they cannot coexist in the same Node process (objc class conflict on macOS, and APIs differ enough that one shim wouldn't suffice anyway).

## Status semantics

| Status | Meaning |
|---|---|
| `PASS` | Query ran without error and any `expect` assertions held. |
| `PASS-AS-EXPECTED-FAIL` | Query errored as expected — either `expectError: true` or `availableIn` doesn't include the running version. |
| `PASS-UNEXPECTED-ON-VERSION` | Query passed on a version it's tagged as unavailable for. **Action:** update `availableIn` to include that version. |
| `FAIL` | Query errored unexpectedly. Either the documented query is broken, the SDK rejects it, or the catalog has a bug. |
| `FAIL-ASSERTION` | Query ran but row count or first-row check disagreed with `expect`. Usually golden drift. |
| `FAIL-UNEXPECTED-PASS` | Query was marked `expectError: true` but the SDK accepted it. **Action:** flip `expectError` to `false`. |

## Setup

### Requirements

- Node 24+ (required by the GitHub Actions matrix; Node 20 is deprecated as of June 2026)
- A Ditto offline license token — put `DITTO_OFFLINE_LICENSE` in the **repo-root `.env`** (`cp .env-sample .env`, gitignored) or export it in your shell; CI uses a repo secret. `DITTO_DATABASE_ID` is optional (harness defaults to the offline-playground zero UUID)
- macOS or Linux (the SDK ships native binaries for both)

Both test runners auto-load the repo-root `.env`; variables already set in the environment always win.

### One-time

```bash
cd tests/dql

# Install all isolated SDK trees
(cd sdks/v4.14.4 && npm install)
(cd sdks/v5.0.0 && npm install)
(cd sdks/v5.1.0 && npm install)

# Transform the real movies dataset to pedagogical schema (committed; only re-run if source changes)
npm run transform
```

## Running the tests

```bash
# All three versions (license picked up from repo-root .env)
npm test

# Single version
npm run test:v51
npm run test:v5
npm run test:v4

# Pretty report after a run
npm run report

# Capture expected outputs after content changes (rebuilds catalog goldens)
for v in 4.14.4 5.0.0 5.1.0; do
  DITTO_SDK_VERSION=$v node runner/run.mjs --capture-expected
done
node scripts/merge-captured.mjs

# Stop on first failure
npm run test:v5 -- --fail-fast
```

## Adding a new query to the skill

1. Add the ` ```sql ` block to the appropriate file under `skills/dql/`.
2. Regenerate: `node scripts/extract-queries.mjs && node scripts/curate-catalog.mjs` — your new query appears in `catalog/catalog.json` with a new hash ID.
3. Run the harness: `npm test`. If your new query passes on the SDK version(s) you intended, you're done.
4. If it errors:
   - Documented query is wrong → fix the skill markdown.
   - Query is genuinely version-gated → add its ID to `catalog/overrides.json` under `availableIn` (use `[]` for documented-but-unshipped features).
   - Query is illustrative-only (not meant to be executed) → add its ID and a reason to `catalog/overrides.json` under `ignore`.

## Layout

```
tests/dql/
├── README.md                              this file
├── package.json                           top-level scripts (extract, transform, test, report)
├── .gitignore                             results/, node_modules/, .ditto/
├── catalog/
│   ├── catalog.json                       200 curated entries
│   ├── overrides.json                     manual version / ignore decisions, applied by curation
│   ├── ignore.json                        generated: IDs intentionally skipped
│   ├── ignore-reasons.json                generated: why each is ignored
│   └── schema-mapping.json                pedagogical-schema mapping from the real dataset
├── scripts/
│   ├── extract-queries.mjs                markdown → catalog draft
│   ├── curate-catalog.mjs                 pre/post queries, param substitution
│   ├── transform-dataset.mjs              real ndjson → pedagogical ndjson (one-time)
│   ├── seed-store.mjs                     load fixture into a Ditto Store
│   ├── merge-captured.mjs                 merge --capture-expected outputs into catalog
│   └── report.mjs                         pretty report across versions
├── runner/
│   ├── run.mjs                            main runner (one version per invocation)
│   ├── version-shim.mjs                   loads @dittolive/ditto from versioned tree
│   └── assertions.mjs                     rowCount + firstRow checks
├── fixtures/
│   ├── movies-pedagogical.ndjson         194 docs spanning 1893–2002 (committed)
│   └── retail/*.ndjson                   8 collections, ~4.9k docs (committed, from dql-metrics retail-joins-1k)
├── sdks/
│   ├── v4.14.4/                           isolated node_modules
│   ├── v5.0.0/                            isolated node_modules
│   └── v5.1.0/                            isolated node_modules
└── results/                               generated, gitignored
    ├── 4.14.4.json
    ├── 5.0.0.json
    ├── 5.1.0.json
    └── report.json
```

## CI

`.github/workflows/dql-skill-tests.yml` runs the matrix on macOS for every PR touching `skills/dql/`, `tests/dql/`, or the workflow itself. Requires the `DITTO_OFFLINE_LICENSE` repo secret.

## Caveats

- **Golden conservatism.** `merge-captured.mjs` only writes assertions that cannot be flaky: `rowCount` is recorded only when every supported SDK version that ran the query agrees on it; `firstRow` only when it is byte-identical across versions *and* the query has an `ORDER BY`. EXPLAIN/PROFILE output is never asserted.
- **Dataset stability.** Some queries (especially those filtering on `imdb.votes`-derived `box_office_millions`) depend on the fixture's exact contents. If `fixtures/movies-pedagogical.ndjson` is regenerated, expected row counts may drift; re-run `--capture-expected` and review the diff.
- **First-row assertions are sparse.** We removed `firstRow` from entries where it was unstable across runs (JSON deep-equality on rows with floats, MAP fields, attachment blobs). Most entries only assert `rowCount`.
- **Genuinely unavailable features are expected-fail.** `catalog/overrides.json` tags documented-but-unshipped features with `availableIn: []` (e.g. `XOR`, `DO MERGE`, multi-id `USE IDS`, `TOMBSTONE ... RETURNING`, directive+subquery combos), so those queries count as PASS-AS-EXPECTED-FAIL until the SDK ships them. v5.1.0 features (JOINs, composite indexes, `RETURNING`, `ADVISE`) are documented, tested, and green.
- **Some queries have no FROM clause.** Many `references/functions.md` examples illustrate function semantics standalone (e.g., `SELECT duration_cast('2h22m', 'seconds')`). DQL requires a FROM clause, so curation ignores them automatically.

## What gets tested (and what doesn't)

**Tested:** every SELECT shape, every INSERT/UPDATE/EVICT/TOMBSTONE/DELETE variant we document, every function in `references/functions.md`, every operator with a concrete example, every CRDT type with a working example, the planner directives and EXPLAIN output shape (via `#profile`).

**Not tested:**
- Subscriptions (require a live mesh) — covered by `Store.execute` only
- Big-Peer-only flows (`SYNC CONTEXT (PEERS WHERE ...)`)
- Attachment binary upload/download (the attachment ID in the inline INSERT is a placeholder)
- Multi-peer replication (the runner uses one Small Peer)
- Parameterized queries (the runner doesn't bind `:param` at runtime — they get substituted during curation)
