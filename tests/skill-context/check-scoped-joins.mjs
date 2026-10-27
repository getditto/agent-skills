// Regression checks for the scoped parent-reference examples, using the DQL SDK install.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadSdk } from "../dql/runner/version-shim.mjs";
import { loadEnv } from "../lib/load-env.mjs";

loadEnv();
const license = process.env.DITTO_OFFLINE_LICENSE || process.env.DITTO_PLAYGROUND_TOKEN;
assert.ok(license, "Set DITTO_OFFLINE_LICENSE using the repository .env or environment");
const sdk = await loadSdk("5.1.0");
await sdk.init();
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ditto-scoped-joins-"));
let ditto;
const root = path.resolve(import.meta.dirname, "../..");
const read = file => fs.readFileSync(path.join(root, "skills/data-modeling/examples", file), "utf8");
const blocks = text => [...text.matchAll(/```sql\n([\s\S]*?)```/g)].map(match => match[1]);
try {
  ditto = await sdk.Ditto.open(new sdk.DittoConfig(
    process.env.DITTO_DATABASE_ID || "00000000-1111-2222-3333-444444444444",
    { mode: "smallPeersOnly" }, directory));
  ditto.setOfflineOnlyLicenseToken(license);
  const execute = query => ditto.store.execute(query);
  const batch = async text => {
    // These fixtures have no comment markers or semicolons inside string values.
    const statements = text.split("\n").map(line => line.split("--")[0]).join("\n");
    for (const query of statements.split(";").filter(value => value.trim())) await execute(query);
  };
  const rows = async query => (await execute(query.trim().replace(/;$/, ""))).items.map(item =>
    typeof item.value === "function" ? item.value() : item.value);
  const order = read("order-management.md");
  const itemBlock = blocks(order).find(block => block.includes("INSERT INTO order_items"));
  const indexStart = itemBlock.indexOf("CREATE INDEX");
  await batch(itemBlock.slice(0, indexStart));
  await execute("INSERT INTO orders DOCUMENTS ({'_id': {'store_id': 42, 'order_id': 'order-2026-00042'}}), ({'_id': {'store_id': 43, 'order_id': 'order-2026-00042'}})");
  await execute("INSERT INTO order_items DOCUMENTS ({'_id': 'other-store', 'parent_id': {'store_id': 43, 'order_id': 'order-2026-00042'}, 'qty': 99})");
  const orderJoin = order.match(/`(SELECT \* FROM orders o INNER JOIN[^`]+)`/)[1];
  await assert.rejects(() => rows(orderJoin), /index support/,
    "The right-side parent reference needs an index");
  await batch(itemBlock.slice(indexStart));
  const orderRows = await rows(orderJoin.replace("SELECT *", "SELECT i.qty AS qty") + " WHERE o._id = {'store_id': 42, 'order_id': 'order-2026-00042'}");
  assert.equal(orderRows.length, 1, "Order JOIN must not include the same order number in another store");
  assert.equal(orderRows[0].qty, 2);
  const relational = read("relational-migration.md");
  await batch(blocks(relational)[0]);
  await execute("INSERT INTO comments DOCUMENTS ({'_id': {'team_id': 'other', 'comment_id': 'c-7001'}, 'ticket_id': {'team_id': 'other', 'ticket_id': 'k-100'}, 'body': 'wrong team'})");
  const joinBlock = blocks(relational).find(block => block.includes("LEFT JOIN comments"));
  await batch(joinBlock.slice(0, joinBlock.indexOf("SELECT")));
  const comments = await rows(joinBlock.slice(joinBlock.indexOf("SELECT")));
  assert.equal(comments.length, 1, "Ticket JOIN must not include the same ticket number in another team");
  assert.equal(comments[0].body, "Parts ordered");
  console.log("PASS: both documented scoped JOINs exclude cross-scope matches on SDK 5.1.0");
} finally {
  if (ditto) await ditto.close();
  fs.rmSync(directory, { recursive: true, force: true });
}
