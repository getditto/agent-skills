// scripts/seed-store.mjs
import fs from "node:fs";
import path from "node:path";

const FIXTURE = path.resolve(import.meta.dirname, "..", "fixtures", "movies-pedagogical.ndjson");

let cachedDocs = null;
function loadDocs() {
  if (cachedDocs) return cachedDocs;
  cachedDocs = fs.readFileSync(FIXTURE, "utf8").split("\n").filter(Boolean).map(JSON.parse);
  return cachedDocs;
}

/**
 * Seeds the movies dataset into a Ditto Store. Idempotent — uses
 * ON ID CONFLICT DO UPDATE so re-seeding restores state after destructive
 * tests. Returns the number of docs seeded.
 */
export async function seedMovies(store) {
  const docs = loadDocs();
  // Type-declare the collection so director/ratings stay MAP across both SDK versions
  // (v4 default = strict / REGISTER, v5 default = lenient / MAP — be explicit for stability)
  for (const d of docs) {
    await store.execute(
      `INSERT INTO COLLECTION movies (director MAP, ratings MAP) DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE`,
      { doc: d }
    );
  }
  return docs.length;
}

/**
 * Removes any documents inserted by tests (anything with _id starting with 'test_seed_')
 * or with a __test_seed marker field. Run between destructive tests.
 */
export async function cleanupTestDocs(store) {
  try { await store.execute(`EVICT FROM movies WHERE __test_seed = true`); } catch {}
}

/**
 * Wipes movies entirely. Use sparingly — slow. After this, seedMovies is required.
 */
export async function resetMovies(store) {
  await store.execute(`EVICT FROM movies`);
}

// ---------------------------------------------------------------------------
// Retail dataset (former dql-metrics retail-joins-1k fixture)
// ---------------------------------------------------------------------------

const RETAIL_DIR = path.resolve(import.meta.dirname, "..", "fixtures", "retail");

// Field type declarations that matter for cross-version reads: on 4.14.x
// (strict mode default) bare objects become REGISTER; on 5.0+ they become
// MAP. Declaring MAP explicitly keeps `store.location.city`-style nested
// reads identical across versions.
const RETAIL_TYPED_FIELDS = {
  stores: "location MAP",
  products: "specifications MAP",
  categories: "seasonal_multipliers MAP",
  inventory: "location MAP",
};

let cachedRetail = null;
function loadRetailDocs() {
  if (cachedRetail) return cachedRetail;
  cachedRetail = {};
  for (const file of fs.readdirSync(RETAIL_DIR)) {
    if (!file.endsWith(".ndjson")) continue;
    const collection = file.slice(0, -".ndjson".length);
    cachedRetail[collection] = fs
      .readFileSync(path.join(RETAIL_DIR, file), "utf8")
      .split("\n")
      .filter(Boolean)
      .map(JSON.parse);
  }
  return cachedRetail;
}

/**
 * Seeds the retail dataset (orders, customers, stores, products, order_items,
 * inventory, categories, product_types). Idempotent. Returns doc count.
 */
export async function seedRetail(store) {
  const byCollection = loadRetailDocs();
  let n = 0;
  for (const [collection, docs] of Object.entries(byCollection)) {
    const typed = RETAIL_TYPED_FIELDS[collection];
    const sql = typed
      ? `INSERT INTO COLLECTION ${collection} (${typed}) DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE`
      : `INSERT INTO ${collection} DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE`;
    for (const d of docs) {
      await store.execute(sql, { doc: d });
      n++;
    }
  }
  return n;
}
