---
title: Retail joins cookbook
description: JOIN recipes against the retail dataset (orders, customers, stores, products, order_items, inventory, categories, product_types). Requires Ditto SDK 5.1+. Companion to `retail-cookbook.md`, which solves the same tasks without JOINs.
---

# Retail joins cookbook

Task-by-task JOIN recipes for the **retail dataset**: 8 collections — `orders`, `order_items`, `customers`, `stores`, `products`, `product_types`, `categories`, `inventory` — a classic star schema with foreign keys everywhere.

> **Available in:** Ditto SDK **5.1+**. Every query below fails to parse on 4.14.x / 5.0.x — see [`retail-cookbook.md`](retail-cookbook.md) for the same tasks written without JOINs so you can compare the two styles side by side.

## The dataset

```
┌──────────┐  customer_id ┌───────────┐           ┌────────┐
│ customers│◄─────────────│  orders   │──────────►│ stores │
└──────────┘              └─────┬─────┘ store_id  └────────┘          ┌───────────────┐
      ▲ primary_store_id        │ order_id                             │  categories   │
      └─────────────────────────┘                                      └──────▲────────┘
                          ┌─────▼────────┐ product_id ┌──────────┐  category_id │           ┌───────────────┐
                          │ order_items  │───────────►│ products │──────────────┘           │ product_types │
                          └──────────────┘            └─────▲────┘   type_id                └───────────────┘
                                                            └───────────────────────────────┘
┌───────────┐                                                │ product_id
│ inventory │◄───────────────────────────────────────────────┘
└───────────┘  composite _id: {store_id, product_id}
```

Notes that matter for everything below:

- **Join key index rule** (5.1): the right-side match key in an `ON` clause must be `_id` or an indexed field, or the statement fails with `Joining to "<alias>" disallowed without appropriate index support. Please run ADVISE for recommendations.` Tasks J6–J8 demonstrate this.
- `inventory._id` is a **composite [object `_id`](../references/schema.md)**: `{store_id, product_id}` — you can index and join on its subfields (`i._id.product_id`).
- Timestamps are ISO-8601 strings; string comparison is chronological. `total`, `stock_level`, `cost`, `base_price` are numbers.

---

### Task J1 — An order with its store details (INNER JOIN)

> **Available in:** SDK **5.1+**.

**Goal:** One row for a specific order, enriched with the store name and city — the classic "look at one order" query Forge-style UIs emit.

**Query:**

```sql
SELECT o._id, o.total, s.store_name, s.location.city
FROM orders AS o
INNER JOIN stores AS s ON o.store_id = s._id
WHERE o._id = 'order_20221210_0001';
```

**Notes:** the right-side match is `s._id` — always indexed, so no extra index is needed. Without a JOIN (4.14.x/5.0.x) this is two statements: read the order, read the store by `o.store_id`. See Task R1.

### Task J2 — Orders joined to customers

> **Available in:** SDK **5.1+**.

**Goal:** Recent orders with the customer's name attached — the list view behind a shop dashboard.

**Query:**

```sql
SELECT o._id, o.total, o.order_date, c.first_name, c.last_name
FROM orders AS o
INNER JOIN customers AS c ON o.customer_id = c._id
WHERE o.deleted = false
ORDER BY o.order_date DESC
LIMIT 10;
```

### Task J3 — The items of an order, with product names

> Indexed match key: `order_items.order_id` — see Task J8 for the `CREATE INDEX`.

**Goal:** The line-item breakdown of one order — item quantity, unit price, and the product name — in a single statement instead of an N+1 loop over `products`.

**Setup index (right-side match key):**

```sql
CREATE INDEX IF NOT EXISTS items_order ON order_items (order_id);
```

> **Available in:** SDK **5.1+** (the join below).

**Query:**

```sql
SELECT i._id, i.quantity, i.line_total, p.product_name, p.base_price
FROM order_items AS i
INNER JOIN products AS p ON i.product_id = p._id
WHERE i.order_id = 'order_20221210_0001'
ORDER BY i._id;
```

**Notes:** this is the shape the benchmarks call `items__join__products`. Doing it without JOINs means one query for items plus a second `WHERE p._id IN (...)` resolution — see Task R3.

### Task J4 — Revenue per store (JOIN + GROUP BY)

> Indexed match key: `orders.store_id` — the right side of this join is `orders` matched on a foreign key.

```sql
CREATE INDEX IF NOT EXISTS orders_store ON orders (store_id);
```

> **Available in:** SDK **5.1+**.

**Goal:** Total revenue for every store, with the store name — a rollup that reads as one statement.

**Query:**

```sql
SELECT s._id, s.store_name, SUM(o.total) AS revenue
FROM stores AS s
INNER JOIN orders AS o ON o.store_id = s._id
WHERE o.deleted = false
GROUP BY s._id, s.store_name
ORDER BY revenue DESC;
```

**Notes:** `WHERE o.deleted = false` in a filter applies after the join; the join itself is unaffected.

### Task J5 — Stores above a revenue threshold (JOIN + HAVING)

> **Available in:** SDK **5.1+**.

**Goal:** The rollup from J4, but only stores that cleared a bar — `HAVING` applies to the aggregate after grouping.

**Query:**

```sql
SELECT s._id, s.store_name, SUM(o.total) AS revenue
FROM stores AS s
INNER JOIN orders AS o ON o.store_id = s._id
WHERE o.deleted = false
GROUP BY s._id, s.store_name
HAVING SUM(o.total) > 300000
ORDER BY revenue DESC;
```

### Task J6 — Customers who have never ordered (anti-join)

> Indexed match key: `orders.customer_id` — the LEFT JOIN's right side here is `orders` matched on a **foreign key**, not `_id`, so the index is mandatory on 5.1+.

**Goal:** Dormant customers — present in `customers`, absent from `orders`.

**Setup index (right-side match key):**

```sql
CREATE INDEX IF NOT EXISTS orders_customer ON orders (customer_id);
```

> **Available in:** SDK **5.1+** (the join below).

**Query:**

```sql
SELECT c._id, c.first_name, c.last_name
FROM customers AS c
LEFT OUTER JOIN orders AS o ON o.customer_id = c._id
WHERE o._id IS MISSING AND c.deleted = false
LIMIT 10;
```

**Notes:** the `o._id IS MISSING` filter is the anti-join idiom — it keeps only customers whose join produced no order row. Without JOINs this requires fetching both collections and diffing in application code (compare Task R6).

### Task J7 — Projection discipline with joins

> **Available in:** SDK **5.1+**.

**Goal:** Project only what you need, alias columns for the consumer, and order by a joined field.

**Query:**

```sql
SELECT o._id AS order_ref, o.total AS amount, s.store_name AS store
FROM orders AS o
INNER JOIN stores AS s ON o.store_id = s._id
WHERE o.deleted = false
ORDER BY s.store_name
LIMIT 10;
```

**Notes:** `ORDER BY` may reference joined aliases/columns (`s.store_name`). `LIMIT` and `OFFSET` paginate joined results exactly like single-collection queries.

### Task J8 — Inventory value by product (composite _id join)

> Indexed match key: `inventory (product_id)` — or index the composite id subfield: `CREATE INDEX … ON inventory (_id.product_id)`.

**Goal:** Current stock valuation per product — `stock_level × cost` joined to product names.

**Setup index (plain FK index — works on every version):**

```sql
CREATE INDEX IF NOT EXISTS inv_product ON inventory (product_id);
```

> **Available in:** SDK **5.1+** (composite index form):

```sql
CREATE INDEX IF NOT EXISTS orders_store_date ON orders (store_id ASC, order_date DESC);
```

> **Available in:** SDK **5.1+** (the join below).

**Query:**

```sql
SELECT p._id, p.product_name, SUM(i.stock_level) AS units_on_hand, SUM(i.stock_level * p.cost) AS inventory_value
FROM inventory AS i
INNER JOIN products AS p ON i.product_id = p._id
WHERE i.deleted = false
GROUP BY p._id, p.product_name
ORDER BY inventory_value DESC
LIMIT 10;
```

**Notes:** the second `CREATE INDEX` is a **composite (multi-column) index** — also new in 5.1 — shaped for "all orders of a store, newest first" (`store ASC, order_date DESC`, the ESR rule — see [`indexing.md`](../references/indexing.md) §8.1).

---

## When JOINs beat the old pattern — measured

The numbers below are from [`dql-metrics-benchmark`](https://github.com/getditto/dql-metrics) `benchmarks/retail-joins/` against this same dataset (single-store slice, warm cache, medians). Directionally:

| Pattern | Two-query baseline | JOIN (5.1) |
|---|---|---|
| Order + store name (J1) | 2 round-trips, ordered | 1 statement |
| Items with product names (J3) | 1 + N queries (N = items) | 1 statement |
| Customers without orders (J6) | full scan of both collections + app-side diff | 1 statement with index |
| Revenue per store (J4) | scan `orders`, sum in app, resolve store names | 1 statement |

The point of the JOIN is not only speed: the semantics live in one statement, so subscriptions, EXPLAIN output, and pagination stay consistent.

> **Caveat from the QE probes:** a `LIMIT` on an INNER JOIN leaked one store transaction per execution in a 5.1.0 preview build (`5.1.0-experimental-join.1`). If you run a join with `LIMIT` in a long-lived process and see `BeginTransactionTimeout`, that's the known leak — see the `joins-limit-probe` suite for the reproducer.

## Cross references

- JOIN grammar and rules — [`select.md`](../references/select.md) §14
- Composite indexes / ESR / ADVISE — [`indexing.md`](../references/indexing.md) §§1, 8, 9
- Aggregates in projections — [`functions.md`](../references/functions.md) §aggregates
- The non-JOIN writeups of these exact tasks — [`retail-cookbook.md`](retail-cookbook.md)
