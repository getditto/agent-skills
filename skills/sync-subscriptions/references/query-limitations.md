# Subscription Query Limitations

Subscription queries are a deliberately restricted subset of DQL. Validation
happens **at registration time** — an unsupported query fails the
`registerSubscription` call immediately with an error of the form:

```
<dql> Unsupported feature: <reason>
```

(Error text below is from SDK 5.1.x. 4.14.x and 5.0.x wording is equivalent
with two differences, called out inline: `use ids` is lowercase there, and
multi-collection `FROM` fails at parse time because those versions predate
the JOIN syntax.)

## The rules

### Must be a single `SELECT *` over one collection

```sql
-- OK
SELECT * FROM cars
SELECT * FROM cars WHERE color = 'blue' AND mileage < 50000

-- Rejected
SELECT make, model FROM cars
-- Unsupported feature: A projection other than wildcard (*)

SELECT * FROM cars, drivers
-- 5.1+: Unsupported feature: Joining
-- 4.14.x / 5.0.x: parse error (multi-collection FROM predates JOIN syntax)

SELECT * FROM cars USE IDS ['abc123']
-- 5.1+: Unsupported feature: USE IDS
-- 4.14.x / 5.0.x: Unsupported feature: use ids

SELECT DISTINCT * FROM cars
-- Unsupported feature: DISTINCT
-- (SELECT DISTINCT color ... never gets this far — the projection
--  check fires first: "A projection other than wildcard (*)")

SELECT * FROM cars GROUP BY color
-- Unsupported feature: Grouping

INSERT INTO cars DOCUMENTS (:doc)
-- Unsupported feature: non-SELECT statement in sync subscription
```

Additional consequences:

- **No projections, ever.** Sync moves whole documents. There is no way to
  subscribe to "some fields" — model that as a separate collection or an
  attachment instead.
- **No JOINs** — including SDK 5.1.x, where JOINs exist for store queries.
  Subscription validation is stricter than store-query validation on every
  version line. Non-collection `FROM` sources (5.1 expression sources) are
  likewise rejected: `Unsupported feature: An expression source`.
- `SELECT DISTINCT *` is rejected too — `DISTINCT` applies to the whole
  wildcard row, but the restriction still applies.
- **No aggregates.** Aggregate functions are only legal in projections,
  `HAVING`, and `ORDER BY` — all rejected — so they are unreachable in a
  subscription.
- **Arguments are fine.** `:argument` placeholders work and are the right way
  to parameterize a subscription.

### `LIMIT` and `ORDER BY`: version-dependent

This is the one rule that differs by SDK line:

| SDK | Behavior |
|---|---|
| 4.14.x (LTS) | `LIMIT` / `ORDER BY` **accepted**, evaluated statefully |
| 5.0.x, 5.1.x | **Rejected by default**: `Unsupported feature: Limit or Order by` |

The rejection on 5.x is controlled by the `dql_restrict_subscriptions` system
parameter (default `true`). Setting it to `false` restores 4.14 behavior —
acceptance with the same stateful performance cost. Treat that as a migration
escape hatch, not a recommendation. Note the restriction does not cover
`OFFSET` alone (`SELECT * FROM cars OFFSET 10` is accepted on 5.x) — unusual
in practice, and still discouraged.

> Public docs pages predate this change and may still describe
> accept-with-a-warning behavior for `LIMIT`/`ORDER BY` subscriptions on 5.x.
> The source-enforced default on 5.0+ is rejection.

Why they were restricted: a subscription with `LIMIT` (with or without
`ORDER BY`) is **stateful** — Ditto must track which documents currently fall
inside the limit boundary. Every change to a boundary document (a delete, a
`WHERE` match change, a sort-position move) invalidates cached state and
forces re-evaluation. On data whose filtered/sorted fields change often, this
degrades sync for the whole mesh. See
[Stateful Subscription Performance Guidelines](https://docs.ditto.live/stateful-subscriptions).

**Key rule (any version):** never filter (`WHERE`) or sort (`ORDER BY`) on
mutable fields when `LIMIT` is used.

### Complexity limits are operational, not syntactic

Deeply nested predicates (multiple levels of `AND`/`OR`, nested object
traversals) are *syntactically allowed* but operationally expensive —
especially against the Ditto Server, where overly complex subscription queries
can degrade the subscription server for all connected peers (symptom:
`503 Service Unavailable` when connecting). Flatten predicates, split into
multiple simple subscriptions, and review programmatically generated query
strings in debug logs.

## Why so strict?

Two design reasons:

1. **Subscriptions run continuously, everywhere.** A store query executes
   once, locally. A subscription is evaluated on every connected peer,
   against every document change, forever. Features that are merely expensive
   for a one-shot query (projections, grouping, sorting with limits) become
   standing costs multiplied across the mesh.
2. **Fail fast protects the mesh.** Subscription queries are exchanged between
   peers and compiled by the *receiving* side. Strict validation at
   registration guarantees no peer ever announces a query another peer cannot
   compile — one bad subscription must not be able to stall replication for
   everyone.

## Quick reference

| Feature | Subscription? | Store query? |
|---|---|---|
| `SELECT *` | Required | Yes |
| Projections | No | Yes |
| `WHERE` (single collection) | Yes | Yes |
| JOIN (5.1+) | No | Yes |
| `USE IDS` | No | Yes |
| `DISTINCT` | No | Yes |
| `GROUP BY` / aggregates | No | Yes |
| `LIMIT` / `ORDER BY` | 4.14: yes (stateful) · 5.x: no by default | Yes |
| `:arguments` | Yes | Yes |
