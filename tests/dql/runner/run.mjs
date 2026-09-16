// runner/run.mjs
//
// Multi-version DQL test runner.
//
// Iterates the curated catalog (tests/dql/catalog/catalog.json),
// executes each entry's pre-/main/post DQL against a fresh Ditto Small Peer
// (persistence in a tmpdir), and writes per-version results to
// tests/results/<version>.json. Exits non-zero on any FAIL.
//
// Invoke via the package scripts:
//   DITTO_PLAYGROUND_TOKEN=<token> npm run test:v4
//   DITTO_PLAYGROUND_TOKEN=<token> npm run test:v5
//
// Flags:
//   --capture-expected   Write a sidecar tests/results/captured-<v>.json
//                        containing the observed rowCount + first 5 keys
//                        of the first row for every PASS. Used by Task 11
//                        to seed expect.* fields back into the catalog.
//   --fail-fast          Stop the run on the first FAIL/FAIL-* status.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { loadSdk } from "./version-shim.mjs";
import { assertRowCount, assertFirstRow } from "./assertions.mjs";
import { seedMovies, seedRetail } from "../scripts/seed-store.mjs";
import { loadEnv } from "../../lib/load-env.mjs";

loadEnv(); // repo-root .env (gitignored); real env vars / CI secrets win

const VERSION = process.env.DITTO_SDK_VERSION;
if (!VERSION) {
  console.error("Set DITTO_SDK_VERSION=4.14.4|5.0.3|5.1.0");
  process.exit(1);
}

const LICENSE = process.env.DITTO_OFFLINE_LICENSE || process.env.DITTO_PLAYGROUND_TOKEN;
if (!LICENSE) {
  console.error("Set DITTO_OFFLINE_LICENSE — in the repo-root .env (see .env-sample) or the environment");
  process.exit(1);
}

const DATABASE_ID = process.env.DITTO_DATABASE_ID || "00000000-1111-2222-3333-444444444444";
const CAPTURE_EXPECTED = process.argv.includes("--capture-expected");
const FAIL_FAST = process.argv.includes("--fail-fast");

// "4.14.4" -> "4.14.x", "5.0.3" -> "5.0.x"
const versionLine = VERSION.replace(/\.[0-9]+$/, ".x");

const catalogPath = path.resolve(import.meta.dirname, "..", "catalog", "catalog.json");
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));

console.log(`Running ${catalog.length} catalog entries against SDK ${VERSION}`);
console.log(`Version line:    ${versionLine}`);

const sdk = await loadSdk(VERSION);

// Both v4 and v5 require Ditto.init() before constructing.
if (typeof sdk.init === "function") {
  await sdk.init();
}

const storeDir = fs.mkdtempSync(path.join(os.tmpdir(), `ditto-dql-test-${VERSION}-`));
console.log(`Persistence dir: ${storeDir}`);

// v4 and v5 have divergent construction APIs:
//   v4 (4.14.x): `new Ditto({ type: "offlinePlayground", appID }, persistenceDir)`
//     — classic identity-config constructor; license applied after construction.
//   v5 (5.0.x):  `Ditto.open(new DittoConfig(databaseID, connect, persistenceDir))`
//     — bare `new Ditto(...)` throws "constructor is private".
let ditto;
try {
  if (versionLine === "4.14.x") {
    ditto = new sdk.Ditto(
      { type: "offlinePlayground", appID: DATABASE_ID }, // appID is the v4 SDK's own property name
      storeDir,
    );
  } else {
    // v5+: build a DittoConfig and call the static factory.
    const config = new sdk.DittoConfig(
      DATABASE_ID,
      { mode: "smallPeersOnly" },
      storeDir,
    );
    ditto = await sdk.Ditto.open(config);
  }
} catch (e) {
  console.error(`Cannot init Ditto on ${VERSION}: ${e.message}`);
  process.exit(1);
}

// Apply offline license — both versions expose this as an instance method.
if (typeof ditto.setOfflineOnlyLicenseToken === "function") {
  try {
    ditto.setOfflineOnlyLicenseToken(LICENSE);
  } catch (e) {
    console.warn("setOfflineOnlyLicenseToken failed:", e.message);
  }
}

// v4 only: disable legacy v3 sync protocol. Required before any DQL mutations.
// Without this, INSERT/UPDATE/DELETE/EVICT throw
// "Mutating DQL statements require ... disable sync with V3".
//
// IMPORTANT: disableSyncWithV3() returns Promise<void> in v4. Must await,
// otherwise the first INSERT races the propagation and fails with the
// V3-sync error even though the call succeeded. Locally this is masked by
// cached activation state in the persistence dir; CI hits a cold start
// every run and the race is exposed.
if (typeof ditto.disableSyncWithV3 === "function") {
  try {
    await ditto.disableSyncWithV3();
  } catch (e) {
    console.warn("disableSyncWithV3 failed:", e.message);
  }
}

// NOTE: deliberately NOT calling startSync() on v4. With
// disableSyncWithV3() set, calling startSync() causes the FFI layer to
// SIGABRT during the first DQL mutation (observed on 4.14.4). The tests
// are local-only DQL — no peer sync needed.

const store = ditto.store;
if (!store) {
  console.error(`Ditto.store is undefined on ${VERSION} — SDK API likely changed`);
  process.exit(1);
}

// Normalize to the documented baseline: dql_strict_mode = false on every peer.
// The skill's examples assume lenient mode (the 5.x default and the 4.x
// migration target). On 4.14.4 this flips the peer off the strict factory
// default; on 5.x it is a no-op. Runtime-only setting — applied per process.
try {
  await store.execute("ALTER SYSTEM SET dql_strict_mode = false");
} catch (e) {
  console.warn("ALTER SYSTEM dql_strict_mode = false failed:", e.message);
}

console.log("Seeding movies dataset...");
const seedStart = Date.now();
let seeded = 0;
try {
  seeded = await seedMovies(store);
  seeded += await seedRetail(store);
} catch (e) {
  console.error(`Seeding failed on ${VERSION}: ${e.message}`);
  console.error(
    "If you are running v4 with an unactivated license, DQL mutations are " +
      "blocked at the SDK layer. Obtain an offline-playground token from " +
      "https://portal.ditto.live and set DITTO_PLAYGROUND_TOKEN.",
  );
  process.exit(1);
}
console.log(`  seeded ${seeded} docs in ${Date.now() - seedStart}ms`);

const results = [];
const captured = {};
let needsReseed = false;
let i = 0;

// Heuristic for "did this entry destructively mutate the shared movies
// collection in a way that future entries depend on a fresh state?"
const MUTATES_MOVIES =
  /^\s*(EVICT|UPDATE|TOMBSTONE|DELETE)\s+(FROM\s+|COLLECTION\s+)?movies/i;
const HAS_ID_FILTER = /WHERE\s+_id\s*=/i;
const HAS_TEST_SEED = /__test_seed/i;

/** Extract a plain-object row from whatever envelope the SDK returns. */
function extractRows(result) {
  // v5: { items: [{ value: {...} | () => {...} }, ...] }
  // v4: similar but also seen as { documents: [...] } in some shapes
  // Bare-array fallback covers SDK quirks.
  const items = result?.items ?? result?.documents ?? result ?? [];
  if (!Array.isArray(items)) return [];
  return items.map((it) => {
    if (it == null) return it;
    const v = typeof it.value === "function" ? it.value() : it.value;
    return v !== undefined ? v : it;
  });
}

for (const entry of catalog) {
  i++;
  const inVersion = entry.availableIn?.includes(versionLine) ?? false;
  // An entry marked available on NO version is a documented example that works
  // nowhere. That is a documentation defect, not a passing test -- unless it is
  // deliberately illustrating an unsupported construct (a Big-Peer-only
  // statement, or a "this is rejected" example), which must be declared with an
  // `unavailableReason` in catalog/overrides.json.
  const availableNowhere =
    Array.isArray(entry.availableIn) && entry.availableIn.length === 0;
  const justified = Boolean(entry.unavailableReason);
  const result = { id: entry.id, version: VERSION, status: null, message: null };

  // Re-seed if the previous entry destructively mutated the shared movies state.
  if (needsReseed) {
    try {
      await store.execute(`EVICT FROM movies`);
      await seedMovies(store);
      await seedRetail(store);
    } catch (e) {
      console.warn(`Reseed failed before ${entry.id}:`, e.message);
    }
    needsReseed = false;
  }

  // Re-assert the documented baseline before every entry: catalog entries that
  // flip dql_strict_mode (the ALTER SYSTEM examples) must not leak that state
  // into the next entry. Runtime-only setting; a no-op on 5.x.
  try {
    await store.execute("ALTER SYSTEM SET dql_strict_mode = false");
  } catch {
    // intentionally ignored
  }

  try {
    // preQueries are best-effort setup; swallow errors so the main query
    // gets its chance to run.
    for (const q of entry.preQueries || []) {
      try {
        await store.execute(q);
      } catch {
        // intentionally ignored
      }
    }

    const r = await store.execute(entry.query);
    const rows = extractRows(r);

    if (entry.expectError) {
      result.status = "FAIL-UNEXPECTED-PASS";
      result.message = `Query expected to error but returned ${rows.length} rows`;
    } else if (!inVersion) {
      result.status = "PASS-UNEXPECTED-ON-VERSION";
      result.message = `Tagged unavailable on ${versionLine} but returned ${rows.length} rows`;
    } else {
      try {
        if (entry.expect?.rowCount !== undefined) {
          assertRowCount(rows.length, entry.expect.rowCount, entry.id);
        }
        if (entry.expect?.firstRow) {
          assertFirstRow(rows[0], entry.expect.firstRow, entry.id);
        }
        result.status = "PASS";
        if (CAPTURE_EXPECTED) {
          captured[entry.id] = {
            rowCount: rows.length,
            firstRow: rows[0]
              ? Object.fromEntries(Object.entries(rows[0]).slice(0, 5))
              : null,
          };
        }
      } catch (e) {
        result.status = "FAIL-ASSERTION";
        result.message = e.message;
      }
    }
  } catch (e) {
    const msg = String(e?.message || e).slice(0, 300);
    if (availableNowhere && !justified) {
      // Works on no supported SDK and nobody said why -- surface it.
      result.status = "BROKEN-EVERYWHERE";
      result.message = msg;
    } else if (entry.expectError || !inVersion) {
      result.status = "PASS-AS-EXPECTED-FAIL";
      result.message = msg;
    } else {
      result.status = "FAIL";
      result.message = msg;
    }
  }

  // postQueries are best-effort cleanup; never fail the test on them.
  for (const q of entry.postQueries || []) {
    try {
      await store.execute(q);
    } catch {
      // intentionally ignored
    }
  }

  // Mark for re-seed if this entry destructively mutated movies broadly.
  if (
    MUTATES_MOVIES.test(entry.query) &&
    !HAS_ID_FILTER.test(entry.query) &&
    !HAS_TEST_SEED.test(entry.query)
  ) {
    needsReseed = true;
  }

  results.push(result);
  if (i % 20 === 0 || i === catalog.length) {
    process.stdout.write(
      `  ${i}/${catalog.length}  ${result.status.padEnd(28)} ${entry.id}\n`,
    );
  }
  if (FAIL_FAST && (result.status?.startsWith("FAIL") || result.status === "BROKEN-EVERYWHERE")) {
    console.error("Fail-fast: stopping after first FAIL");
    break;
  }
}

// Teardown
try {
  if (typeof ditto.stopSync === "function") ditto.stopSync();
  if (typeof ditto.close === "function") ditto.close();
  else if (typeof ditto.stop === "function") await ditto.stop();
} catch (e) {
  console.warn("Teardown error:", e.message);
}
try {
  fs.rmSync(storeDir, { recursive: true, force: true });
} catch {
  // ignore
}

// Write results
const outDir = path.resolve(import.meta.dirname, "..", "results");
fs.mkdirSync(outDir, { recursive: true });
const outPath = path.join(outDir, `${VERSION}.json`);
fs.writeFileSync(outPath, JSON.stringify(results, null, 2));

if (CAPTURE_EXPECTED) {
  const capturePath = path.join(outDir, `captured-${VERSION}.json`);
  fs.writeFileSync(capturePath, JSON.stringify(captured, null, 2));
  console.log(
    `Captured ${Object.keys(captured).length} expected outputs → ${capturePath}`,
  );
}

const counts = results.reduce((a, r) => {
  a[r.status] = (a[r.status] || 0) + 1;
  return a;
}, {});

console.log("\nResults summary:");
for (const [k, v] of Object.entries(counts).sort()) {
  console.log(`  ${k.padEnd(28)} ${v}`);
}
console.log(`Detail: ${outPath}`);

const failures = results.filter(
  (r) => r.status?.startsWith("FAIL") || r.status === "BROKEN-EVERYWHERE",
);
process.exit(failures.length === 0 ? 0 : 1);
