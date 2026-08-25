---
title: Retail cookbook (no JOINs)
description: Retail dataset recipipes using only the single-collection DQL surface — two-query lookups, IN-list resolution, app-side merge. Works on every supported SDK (4.14.x, 5.0.x, 5.1.x). Companion to `retail-joins-cookbook.md`, which solves the same tasks with JOINs on SDK 5.1+.
---

# Retail cookbook — the pre-5.1 (no JOIN) way

Same retail dataset as [`retail-joins-cookbook.md`](retail-joins-cookbook.md): `orders`, `order_items`, `customers`, `stores`, `products`, `product_types`, `categories`, `inventory`. Every task below is solvable without `JOIN` — that's how production code on 4.14.x and 5.0.x does it today. Each task links to its JOIN counterpart so you can compare the two styles directly.

The non-JOIN toolbelt for cross-collection reads:

1. **Two-step lookup** — read the parent, then `WHERE _id = '…'` (or `USE IDS`) the child.
2. **IN-list resolution** — read children, then resolve references with `WHERE _id IN (...)` in one second query.
3. **Single-collection aggregates** — `GROUP BY` on the FK column, then resolve display fields with a follow-up query.
4. **Denormalization at write time** — store copies of display values on the referencing document (e.g. `orders.store_name`) so reads stay single-collection.
5. **App-side diff/merge** — fetch both collections and combine in application code when nothing else fits.

Everything here runs on 4.14.x, 5.0.x, and 5.1.x.

---

### Task R1 — An order with its store details

**Goal:** One order enriched with store name and city. (JOIN version: Task J1.)

**Query 1 — the order:**

```sql
SELECT _id, store_id, total, order_date
FROM orders
WHERE _id = 'order_20221210_0001';
```

**Query 2 — the store, using the FK from step 1:**

```sql
SELECT _id, store_name, location.city
FROM stores
USE IDS ('store_seattle');
```

**Notes:** two round trips, ordered — you cannot run them in parallel (the second depends on the first). `USE IDS` is SELECT-only and hits the primary id index directly (see [`select.md`](../references/select.md) §3). Micro-optimisation: if your UI shows the same store often, cache it — stores are tiny and stable.

### Task R2 — Recent orders with customer names

**Goal:** The order list view, with the customer name attached. (JOIN version: Task J2.)

**Query 1 — the orders:**

```sql
SELECT _id, customer_id, total, order_date
FROM orders
WHERE deleted = false
ORDER BY order_date DESC
LIMIT 10;
```

**Query 2 — resolve the customers in one shot:**

```sql
SELECT _id, first_name, last_name
FROM customers
WHERE _id IN ('edf7a497-c04e-4326-a08a-837de9335a9a', 'e652232a-95ab-4fcf-86b7-e40cea3d749d');
```

**Notes:** `WHERE _id IN (...)` is the supported list form; keep the list small enough to round-trip (hundreds is fine). Alternatives considered SQL-ish — correlated subqueries — are not needed here: ids from step 1 are plain values.

### Task R3 — The items of an order, with product names

**Goal:** Line items of one order with product names. (JOIN version: Task J3.)

**Query 1 — the items:**

```sql
SELECT _id, product_id, quantity, line_total
FROM order_items
WHERE order_id = 'order_20221210_0001';
```

**Query 2 — resolve the products:**

```sql
SELECT _id, product_name, base_price
FROM products
WHERE _id IN ('prod_hnd_0005', 'prod_grd_0048', 'prod_elc_0009');
```

**Notes:** this is the "1 + N" pattern: one query for N items, one follow-up `IN` query — N+1 total statements regardless of N. If you index `order_items.order_id` (single-column, works on every SDK), step 1 is an index seek:

```sql
CREATE INDEX IF NOT EXISTS items_order ON order_items (order_id);
```

### Task R4 — Revenue per store

**Goal:** Total revenue per store, with names. (JOIN version: Task J4.)

**Query 1 — aggregate on the FK column, no join needed:**

```sql
SELECT store_id, SUM(total) AS revenue
FROM orders
WHERE deleted = false
GROUP BY store_id
ORDER BY revenue DESC;
```

**Query 2 — resolve the names of the returned store ids:**

```sql
SELECT _id, store_name
FROM stores
WHERE _id IN ('store_seattle', 'store_redmond');
```

**Notes:** aggregates over the foreign key work fine without a join — the join only becomes necessary when the grouping or projection needs fields from *both* collections at once.

### Task R5 — Stores above a revenue threshold

**Goal:** J5 without a join — threshold the aggregate with `HAVING` directly. (JOIN version: Task J5.)

**Query:**

```sql
SELECT store_id, SUM(total) AS revenue
FROM orders
WHERE deleted = false
GROUP BY store_id
HAVING SUM(total) > 300000
ORDER BY revenue DESC;
```

**Notes:** `HAVING` works on single-collection groups the same as joined ones; only the name-resolution step is extra (same as R4).

### Task R6 — Customers who have never ordered

**Goal:** Find dormant customers. (JOIN version: Task J6.)

**Query 1:**

```sql
SELECT _id FROM customers WHERE deleted = false;
```

**Query 2:**

```sql
SELECT DISTINCT customer_id FROM orders;
```

Then compute `customers − orders-customer-ids` in application code. There is no set-difference operator in DQL, and no way to say "no matching row in another collection" without a join — this is the task where the non-JOIN version is the most awkward, and where the LEFT JOIN anti-join (Task J6) wins clearest.

**Notes:** for a bounded implementation, page both queries and diff in a set structure. `SELECT DISTINCT customer_id` keeps the second result small.

### Task R7 — Projection discipline without joins

**Goal:** The J7-style tidy projection: only the fields the screen shows. (JOIN version: Task J7.)

```sql
SELECT _id AS order_ref, total AS amount, store_id
FROM orders
WHERE deleted = false
ORDER BY order_date DESC
LIMIT 10;
```

**Notes:** no join means the sortable column must live on `orders` (or be fetched after sorting). This is the strongest argument for **denormalizing display fields at write time**: e.g. writing `store_name` onto each `orders` document removes the second lookup entirely.

### Task R8 — Inventory value by product

**Goal:** Current stock valuation per product. (JOIN version: Task J8.)

**Query 1 — aggregate stock on the inventory side:**

```sql
SELECT product_id, SUM(stock_level) AS units_on_hand
FROM inventory
WHERE deleted = false
GROUP BY product_id
ORDER BY units_on_hand DESC
LIMIT 10;
```

**Query 2 — resolve product names and costs, then multiply in app code:**

```sql
SELECT _id, product_name, cost
FROM products
WHERE _id IN ('prod_hnd_0005', 'prod_grd_0048');
```

**Notes:** the JOIN version computes `SUM(i.stock_level * p.cost)` inside one statement; without the join the multiplication happens in application code after the second query.

---

## Non-JOIN summary — when to use what

| Situation | Pre-5.1 approach | Caveat |
|---|---|---|
| Parent → single child (`store_id → stores`) | `WHERE _id = '<id>'` or `USE IDS ('…')` | Two ordered round trips |
| Parent → many children (`order → order_items`) | `WHERE order_id = '…'` + index on the FK | Add the FK index manually |
| Children → resolve display fields | `WHERE _id IN (…)` list | List size bounded |
| Group/aggregate by FK (`SUM(total) BY store_id`) | single-collection `GROUP BY` + follow-up name lookup | Display fields arrive late |
| "Missing on the other side" (anti-join) | app-side set difference | Fetches both sets |
| Deep chains (`order → items → products`) | 3+ queries | Consider a join when you can |

If any of the cost rows apply to hot paths AND every peer that reads the data is on SDK 5.1+, use the JOIN instead — the same tasks live in [`retail-joins-cookbook.md`](retail-joins-cookbook.md) with harness-verified examples.

## Cross references

- SELECT grammar, `USE IDS`, `WHERE … IN (…)` — [`select.md`](../references/select.md) §§3, 6
- FK indexing — [`indexing.md`](../references/indexing.md) §1
- Aggregates / `HAVING` — [`functions.md`](../references/functions.md); [`select.md`](../references/select.md) §§7–8
