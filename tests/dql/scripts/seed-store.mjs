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
