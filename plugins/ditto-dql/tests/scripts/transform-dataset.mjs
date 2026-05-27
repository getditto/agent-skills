import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const cfg = JSON.parse(fs.readFileSync(
  path.resolve(import.meta.dirname, "..", "catalog", "schema-mapping.json"),
  "utf8"
));

const src = cfg.from.replace(/^~/, os.homedir());
const dst = path.resolve(import.meta.dirname, "..", "fixtures", "movies-pedagogical.ndjson");
fs.mkdirSync(path.dirname(dst), { recursive: true });

const lines = fs.readFileSync(src, "utf8").split("\n").filter(Boolean).slice(0, cfg.limit);
const out = lines.map(raw => {
  const r = JSON.parse(raw);
  const year = parseInt(r._id?.year || r.year, 10);
  return JSON.stringify({
    _id: r._id?.id || r._id,
    title: r._id?.title || r.title,
    year,
    runtime_minutes: r.runtime ?? null,
    genres: r.genres ?? [],
    director: { name: r.directors?.[0] ?? null, born: null },
    cast: (r.cast ?? []).map(name => ({ name, role: "" })),
    ratings: {
      imdb: r.imdb?.rating ?? null,
      rotten_tomatoes: r.tomatoes?.viewer?.meter ?? null,
      metacritic: null
    },
    box_office_millions: r.imdb?.votes ? Math.floor(r.imdb.votes / 10000) : null,
    tags: r.countries ?? [],
    watch_count: 0,
    is_classic: !Number.isNaN(year) && year < 1980,
    released: (r.released ?? "").slice(0, 10)
  });
}).join("\n");

fs.writeFileSync(dst, out + "\n");
console.log(`Wrote ${lines.length} docs to ${dst}`);
