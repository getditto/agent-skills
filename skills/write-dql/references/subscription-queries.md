# Subscription queries — Ditto

## Contents

- [12. Subscription patterns and constraints](#12-subscription-patterns-and-constraints)
- [12.1 Feature flags that restrict subscription syntax](#121-feature-flags-that-restrict-subscription-syntax)
- [12.2 What is — and isn't — allowed in a subscription](#122-what-is--and-isnt--allowed-in-a-subscription)
- [12.3 Portable subscription patterns](#123-portable-subscription-patterns)

Topic index: [select.md](select.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## 12. Subscription patterns and constraints

DQL `SELECT` statements can be used as **subscriptions** — long-lived queries that emit incremental updates as documents change. The engine restricts the surface that subscription queries can use, to keep cache invalidation cheap. Two feature flags control that surface; when each applies is covered below.

### 12.1 Feature flags that restrict subscription syntax

> **These are internal engine bitflags, not settable parameters.** `DQL_RESTRICT_TO_ORIGINAL_SYNTAX` and `DQL_RESTRICT_LIMIT_ORDER_BY` are Rust `FeatureFlags` constants (`crates/ditto-dql/src/engine/mod.rs`) that the subscription code path sets for you. `SHOW` and `ALTER SYSTEM SET` reject both names on **every** version with `unknown parameter` — you cannot inspect or override them from DQL. They are named here only because they appear in engine error paths.

| Restriction                       | Applies on      | Effect on subscription `SELECT`                                                                                                       |
| --------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| V1 surface only<br>(`DQL_RESTRICT_TO_ORIGINAL_SYNTAX`) | 4.14.x, 5.0.x, 5.1.x | `SELECT *` only (no expression projection), a single collection (no JOIN), no `USE IDS`, no `DISTINCT`, no `GROUP BY`/`HAVING`. |
| `ORDER BY` / `LIMIT` rejected<br>(`DQL_RESTRICT_LIMIT_ORDER_BY`) | **SDK 5.0+** | `ORDER BY` and `LIMIT` are rejected in subscription queries. `OFFSET` on its own stays legal. Use a one-shot store query for paginated or sorted reads. |

The V1-surface restriction is always on for `registerSubscription` on every SDK version — there is no unrestricted subscription path. The `ORDER BY`/`LIMIT` rejection is driven by the system parameter **`dql_restrict_subscriptions`** (default `true`), which exists on 5.0.x, 5.1.x and 5.2.0 and **not** on 4.14.x — that one *is* readable with `SHOW dql_restrict_subscriptions`. SDK 4.14.x accepts both clauses; queries using `LIMIT` maintain boundary state and should avoid mutable filter or sort fields. See the `sync-subscriptions` skill for the full version matrix and exact error strings.

### 12.2 What is — and isn't — allowed in a subscription

The table below collapses both flags. "OK" means the syntax works in a subscription across SDK 4.14.x, 5.0.x, and 5.1.x. "Restricted" means at least one of the flags above blocks it.

| Feature                              | One-shot `SELECT` | Subscription `SELECT`                                                  |
| ------------------------------------ | ----------------- | ---------------------------------------------------------------------- |
| `SELECT *`                           | OK                | OK                                                                     |
| Expression projection / `AS` aliases | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `DISTINCT`                           | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `USE IDS`                            | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `USE INDEX` / `USE DIRECTIVES`       | OK                | OK (planner hints are honoured)                                        |
| `WHERE`                              | OK                | OK                                                                     |
| `GROUP BY` / `HAVING`                | OK                | Restricted under `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`                     |
| `ORDER BY`                           | OK                | **Restricted under `DQL_RESTRICT_LIMIT_ORDER_BY`** (default on 5.0+; accepted, stateful, on 4.14.x) |
| `LIMIT`                              | OK                | **Restricted under `DQL_RESTRICT_LIMIT_ORDER_BY`** (default on 5.0+; accepted, stateful, on 4.14.x) |
| `OFFSET` alone                       | OK                | OK — the restriction fires only on `LIMIT` / `ORDER BY`                |

### 12.3 Portable subscription patterns

If you need to subscribe to a filtered set on 4.14.x, 5.0.x, and 5.1.x alike, stick to the lowest-common-denominator surface:

```sql
-- Portable subscription: SELECT * with WHERE only
SELECT * FROM movies WHERE year >= 1990 AND is_classic = true;

SELECT * FROM reviews WHERE movie_id = :movie_id;

SELECT * FROM movies WHERE array_contains(genres, 'Drama');
```

Expression projections are never available in a subscription, on any supported SDK version — model partial documents as a separate collection or an attachment instead. `ORDER BY` / `LIMIT` subscriptions work only on 4.14.x:

```sql
-- SDK 4.14.x only. LIMIT makes this stateful: boundary changes invalidate
-- and re-evaluate the query, so never filter or sort on mutable fields.
-- On SDK 5.0.x and 5.1.x, use a one-shot local query instead.
SELECT * FROM movies
WHERE year >= 1990
ORDER BY title ASC
LIMIT 50;
```

On SDK 5.x, subscribe to the unsorted set and apply presentation constraints locally.

For sorting and pagination across a subscription stream, do the sort/limit **in the host application** over the unsorted subscription result, rather than relying on the engine to maintain a sorted projection.

---
