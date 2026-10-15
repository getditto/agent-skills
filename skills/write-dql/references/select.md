---
title: DQL SELECT reference
description: SELECT clauses (projection, FROM, USE IDS/INDEX/DIRECTIVES, WHERE, GROUP BY, HAVING, ORDER BY, LIMIT/OFFSET) plus subscription constraints. Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL SELECT reference

## Contents

- [Top-level grammar](#top-level-grammar)
- [1. Projection](#1-projection)
- [2. FROM clause](#2-from-clause)
- [3. USE IDS](#3-use-ids)
- [4. USE INDEX](#4-use-index)
- [5. USE DIRECTIVES](#5-use-directives)
- [6. WHERE clause](#6-where-clause)
- [7. GROUP BY](#7-group-by)
- [8. HAVING](#8-having)
- [9. ORDER BY](#9-order-by)
- [10. LIMIT / OFFSET](#10-limit--offset)
- [11. Cross-type sort order](#11-cross-type-sort-order)
- [12. Subscription patterns and constraints](#12-subscription-patterns-and-constraints)
- [13. Worked examples (movies dataset)](#13-worked-examples-movies-dataset)
- [14. `JOIN` — cross-collection reads](#14-join--cross-collection-reads)
- [15. Cross-reference index](#15-cross-reference-index)

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative reference for the `SELECT` statement on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**. All other top-level statements (`INSERT`, `UPDATE`, `EVICT`, `TOMBSTONE`, `DELETE`, `EXPLAIN`, `ALTER SYSTEM`, `SHOW`, `SYNC CONTEXT`, `PROFILE`) live in [`statements.md`](statements.md). `CREATE INDEX` / `DROP INDEX` live in [`indexing.md`](indexing.md).

Unless a section carries an "Available in:" note, the clause works identically on 4.14.x, 5.0.x, and 5.1.x.

Cross-references:

- Expression grammar (paths, literals, quantifiers, comprehensions) → [`expressions.md`](expressions.md)
- Operators (precedence, comparison, NULL/MISSING semantics, four-valued logic) → [`operators.md`](operators.md)
- Scalar and aggregate functions → [`functions.md`](functions.md)
- CRDT type definitions and mutators (`MAP`, `COUNTER`, `APPLY`) → [`types-mutators.md`](types-mutators.md)
- Index DDL and planner hints in depth → [`indexing.md`](indexing.md)

---

## Top-level grammar

```
SELECT [ DISTINCT ] <projection>
FROM <collection_ref>
  [ USE IDS <id_list> ]
  [ USE INDEX <name> [ ASC | DESC ] ]
  [ USE DIRECTIVES '<json_object>' ]
[ WHERE     <expr> ]
[ GROUP BY  <expr> [, <expr> ...] ]
[ HAVING    <expr> ]
[ ORDER BY  <expr> [ ASC | DESC ] [, <expr> [ ASC | DESC ] ...] ]
[ LIMIT     <int_or_param> ]
[ OFFSET    <int_or_param> ]
```

Clauses must appear in the order shown. The three `USE …` clauses are mutually orderable (any order, any subset), but each may appear at most once. Inline planner directives via comments (`/*+ … */` or `--+ …`) may precede the statement — see [`indexing.md`](indexing.md).

---

## 1. Projection

See [select-basics.md](select-basics.md#1-projection) for this topic.

## 2. FROM clause

See [select-basics.md](select-basics.md#2-from-clause) for this topic.

## 3. USE IDS

See [select-access.md](select-access.md#3-use-ids) for this topic.

## 4. USE INDEX

See [select-access.md](select-access.md#4-use-index) for this topic.

## 5. USE DIRECTIVES

See [select-access.md](select-access.md#5-use-directives) for this topic.

## 6. WHERE clause

See [select-basics.md](select-basics.md#6-where-clause) for this topic.

## 7. GROUP BY

See [select-basics.md](select-basics.md#7-group-by) for this topic.

## 8. HAVING

See [select-basics.md](select-basics.md#8-having) for this topic.

## 9. ORDER BY

See [select-basics.md](select-basics.md#9-order-by) for this topic.

## 10. LIMIT / OFFSET

See [select-basics.md](select-basics.md#10-limit--offset) for this topic.

## 11. Cross-type sort order

See [select-basics.md](select-basics.md#11-cross-type-sort-order) for this topic.

## 12. Subscription patterns and constraints

See [subscription-queries.md](subscription-queries.md#12-subscription-patterns-and-constraints) for this topic.

## 13. Worked examples (movies dataset)

See [select-basics.md](select-basics.md#13-worked-examples-movies-dataset) for this topic.

## 14. `JOIN` — cross-collection reads

See [joins.md](joins.md#14-join--cross-collection-reads) for this topic.

## 15. Cross-reference index

| Topic                                              | Go to                                       |
| -------------------------------------------------- | ------------------------------------------- |
| Operator precedence, NULL/MISSING, 4-valued logic  | [`operators.md`](operators.md)              |
| Path expressions, parameters, literals, CASE       | [`expressions.md`](expressions.md)          |
| `ANY` / `EVERY` / `SATISFIES`, comprehensions      | [`expressions.md`](expressions.md) §quantifiers |
| `array_contains`, `regexp_like`, type predicates   | [`functions.md`](functions.md)              |
| `count` / `sum` / `avg` / `min` / `max` / `median` | [`functions.md`](functions.md) §aggregates  |
| `INSERT` / `UPDATE` / `DELETE` / etc.              | [`statements.md`](statements.md)            |
| `USE IDS` mutation workaround (`WHERE _id IN …`)   | [`statements.md`](statements.md) §§3–5      |
| `MAP` / `COUNTER` / `APPLY` semantics              | [`types-mutators.md`](types-mutators.md)    |
| `CREATE INDEX`, `DROP INDEX`, full directive set   | [`indexing.md`](indexing.md)                |
| `EXPLAIN` / `PROFILE` (v5.0+ keyword)              | [`statements.md`](statements.md) §§6, 10    |
