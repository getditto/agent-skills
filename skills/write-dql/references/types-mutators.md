---
title: DQL CRDT types and mutators
description: REGISTER, MAP, COUNTER (4.14+), PN_COUNTER (4.11+), and ATTACHMENT — semantics, declaration syntax, mutation patterns, and the cross-version strict-mode flip (this skill assumes `dql_strict_mode = false`; `true` is the legacy 4.14.x default to migrate off). Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL CRDT types and mutators

## Contents

- [Type-definition syntax (recap)](#type-definition-syntax-recap)
- [1. REGISTER](#1-register)
- [2. MAP](#2-map)
- [3. COUNTER](#3-counter)
- [4. PN_COUNTER](#4-pn_counter)
- [5. ATTACHMENT](#5-attachment)
- [6. Reading typed fields with `SELECT`](#6-reading-typed-fields-with-select)
- [7. Strict mode and the `dql_strict_mode` system parameter](#7-strict-mode-and-the-dql_strict_mode-system-parameter)
- [8. Quick decision matrix](#8-quick-decision-matrix)

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative reference for the five CRDT types DQL exposes on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**, the type-definition syntax you use to declare them on `INSERT`/`UPDATE`, and the mutation clauses that touch each one.

All three SDK versions ship the same `CrdtType` enum: `REGISTER`, `MAP`, `COUNTER` (settable counter, SDK 4.14+), `PN_COUNTER` (legacy positive-negative counter, SDK 4.11+), and `ATTACHMENT`. The user-visible difference across versions is the **factory default of `dql_strict_mode`** (`true` on 4.14.x, `false` on 5.x) — and this skill assumes `false` on every peer, the state every 4.14.x mesh migrates to. See [§7](legacy-types.md#7-strict-mode-and-the-dql_strict_mode-system-parameter).

Cross-references:

- For `INSERT` / `UPDATE` clause grammar and how `SET` / `UNSET` / `APPLY` are sequenced, see [`statements.md`](statements.md) §1 and §2.
- For nested-field expressions, `IS MISSING`, and `OBJECT(...)` literals, see [`expressions.md`](expressions.md).
- For data-modelling trade-offs (embedded vs flat, schema versioning, when to use `ATTACHMENT`) see the skill-level [`best-practices.md`](../best-practices.md).

---

## Type-definition syntax (recap)

CRDT types are declared inline, per statement, in parentheses after the collection name:

```
INSERT INTO COLLECTION <coll> ( <field> <crdt_type> [, ...] ) DOCUMENTS ( ... )
UPDATE       COLLECTION <coll> ( <field> <crdt_type> [, ...] ) SET ...
SELECT ... FROM COLLECTION  <coll> ( <field> <crdt_type> [, ...] ) WHERE ...

<crdt_type> ::= REGISTER
             |  MAP [ ( <field> <crdt_type> [, ...] ) ]   -- nested type def
             |  COUNTER       -- SDK 4.14+
             |  PN_COUNTER    -- SDK 4.11+
             |  ATTACHMENT
```

Rules that apply to every CRDT type:

- The declaration is **per-statement**. It does not create a global schema; it tells the engine how to interpret values in *this* statement.
- A type definition is **required** only where inference can't help or a strict peer is involved. `COUNTER`, `PN_COUNTER`, and `ATTACHMENT` always need declaration. `MAP`/`REGISTER` need **none** under the lenient baseline (`dql_strict_mode = false`) — but on a strict-mode peer (legacy 4.14.x default) every non-`REGISTER` field must be declared or it silently stores as `REGISTER`; see [§7](legacy-types.md#7-strict-mode-and-the-dql_strict_mode-system-parameter).
- Fields omitted from the list are **inferred from the value under the lenient baseline** (`dql_strict_mode = false`): an object becomes a `MAP`, everything else — scalars and arrays — a `REGISTER`. Only under strict mode does an omitted field default to `REGISTER` whatever its shape. Verified on 4.14.6 and 5.1.0: with strict `false`, `INSERT INTO COLLECTION c (n COUNTER) DOCUMENTS ({'obj': {'a':1,'b':2}, …})` leaves `obj` a MAP — `SET obj.a = 99` keeps `b` — while the same statement under strict `true` stores a REGISTER and rejects the dotted `SET`.
- `_id` may **never** appear in a type definition.
- Duplicate field names in one definition raise a parse error.

A full schema-style declaration on the `movies` collection:

```sql
INSERT INTO COLLECTION movies (
  director    MAP (name REGISTER, born REGISTER),
  ratings     MAP,
  watch_count COUNTER,
  poster      ATTACHMENT
)
DOCUMENTS ({
  '_id'   : 'tt0816692',
  'title' : 'Interstellar',
  'year'  : 2014,
  'director'    : { 'name': 'Christopher Nolan', 'born': 1970 },
  'ratings'     : { 'imdb': 8.6, 'rotten_tomatoes': 73 },
  'watch_count' : 0
});
```

Why declare types here when 5.0 would have inferred `MAP` for you? Because the *same* statement must work on a 4.x peer, which would otherwise have stored `director` and `ratings` as `REGISTER`. Declaring explicitly is the only portable way to write cross-version code.

---

## 1. REGISTER

**Merge semantics:** last-write-wins per field. Each concurrent write produces one winner; losers are dropped.

**When to use it:**

- Scalars that are only ever overwritten (title, year, status, flag).
- Whole-document replacements where you genuinely want LWW behaviour (e.g. `score` on a `reviews` row).
- The default for any field you don't declare — no ceremony required.

**When NOT to use it:**

- A counter incremented from multiple peers. Two peers each `SET views = views + 1` offline will lose one increment on merge. Use [`COUNTER`](#3-counter) instead.
- An object whose sub-fields are independently edited by different peers. The whole object will be overwritten on merge. Use [`MAP`](#2-map) instead.
- An array you intend to extend rather than replace. Arrays inside a `REGISTER` are atomic: a peer that writes `[a, b, c]` and a peer that writes `[a, b, d]` will not merge to `[a, b, c, d]`; one whole array wins.

**Declaration syntax:** the default. You only need to name it explicitly when you want to *force* `REGISTER` on an object value (overriding 5.0's lenient `MAP` default).

```sql
-- Force REGISTER on an object — needed on 5.0 when you want LWW on the whole object.
UPDATE COLLECTION movies (ratings REGISTER)
SET ratings = { 'imdb': 9.4, 'rotten_tomatoes': 98, 'metacritic': 99 }
WHERE _id = 'tt0111161';
```

**Mutation pattern:** plain `SET` / `UNSET` on `UPDATE`, or assignment inside a document literal on `INSERT`.

```sql
-- INSERT — every REGISTER field is just a key in the document literal
INSERT INTO movies DOCUMENTS
  ({ '_id': 'tt0468569', 'title': 'The Dark Knight', 'year': 2008, 'is_classic': true });

-- UPDATE — SET overwrites, UNSET removes
UPDATE movies
SET    is_classic = true,
       box_office_millions = 28.34
UNSET  tags
WHERE  _id = 'tt0111161';
```

`UNSET` removes the field entirely. To set a `REGISTER` to `NULL` rather than remove it, use `SET field = NULL`.

---

## 2. MAP

**Merge semantics:** nested CRDT object with per-field merge. Each sub-field is itself a CRDT (defaulting to `REGISTER`) and merges independently of its siblings.

**When to use it:**

- Objects whose fields are edited independently by different peers (`director`, `ratings`, `profile`).
- Anywhere you want concurrent updates to coexist rather than overwrite — e.g. one peer edits `ratings.imdb` while another edits `ratings.rotten_tomatoes`; both survive.
- As a container for nested counters (`MAP (impressions COUNTER, clicks COUNTER)`).

**When NOT to use it:**

- Objects whose semantics are atomic — a complete address record where the city must match the postcode. Use `REGISTER` for those, so a half-updated object can't appear post-merge.
- Hot append-only logs. Use a separate collection of small documents; `MAP` is not a list.

**Declaration syntax:** `MAP` with an optional nested type definition. Sub-fields you don't list follow the same inference rule as top-level fields: under the lenient baseline a nested object becomes a `MAP` at any depth (verified on 4.14.6 and 5.1.0 — `SET d.sub.x = 99` on an undeclared `d.sub` leaves its siblings intact), scalars and arrays become `REGISTER`s. Under strict mode every unlisted sub-field is a `REGISTER`.

```sql
-- Bare MAP — all sub-fields default to REGISTER
INSERT INTO COLLECTION movies (director MAP)
DOCUMENTS ({ '_id': 'tt0111161', 'director': { 'name': 'Frank Darabont', 'born': 1959 } });

-- Nested MAP — director.name is REGISTER, director.awards is itself a MAP
INSERT INTO COLLECTION movies (
  director MAP (name REGISTER, awards MAP)
)
DOCUMENTS ({
  '_id': 'tt0111161',
  'director': { 'name': 'Frank Darabont', 'awards': { 'oscars': 0, 'baftas': 1 } }
});
```

**Mutation pattern:** `SET` on a MAP field is a **bulk merge**, not a replace. Sub-fields you don't mention are left intact. To remove one sub-field, dotted-path `UNSET` (e.g. `UNSET ratings.imdb`) writes a per-key tombstone; clearing many keys is cheaper with `UNSET` on the parent field (less tombstone metadata).

```sql
-- Only ratings.imdb changes; rotten_tomatoes and metacritic survive
UPDATE COLLECTION movies (ratings MAP)
SET    ratings = { 'imdb': 9.4 }
WHERE  _id = 'tt0111161';

-- Dotted-path SET targets exactly one sub-field
UPDATE COLLECTION movies (director MAP)
SET    director.born = 1959
WHERE  _id = 'tt0111161';

-- Mix sub-field SET and parent-level bulk merge in one statement
UPDATE COLLECTION movies (director MAP, ratings MAP)
SET    director.born = 1959,
       ratings = { 'imdb': 9.4 }
WHERE  _id = 'tt0111161';
```

You can also nest a `COUNTER` inside a `MAP`:

```sql
UPDATE COLLECTION movies (engagement MAP (views COUNTER, likes COUNTER))
APPLY  engagement.views INCREMENT BY 1
WHERE  _id = 'tt0111161';
```

---

## 3. COUNTER

> **Available in:** Ditto SDK 4.14+.

**Merge semantics:** a **settable** counter — internally an LWW base register plus a per-actor counter. Every peer maintains its own contribution and the merged value is the base plus the sum across actors, so increments from concurrent offline peers all survive. A *set* (`RESTART [WITH]`) is different: sets resolve last-write-wins against each other, and **a set beats increments it raced with** — the winning side's base is taken and the losing side's accumulated increments are discarded. Plan `RESTART` for moments when nobody else is incrementing.

**When to use it:**

- View counts, like counts, inventory levels, score totals that multiple peers update.
- Anything where "add one" from two peers must produce "+2" after merge.

**When NOT to use it:**

- Numbers you want to *overwrite* rather than accumulate. Use `REGISTER` for `year`, `score`, `temperature_reading`.
- Numbers that need arbitrary arithmetic (`x = x * 2`, `x = max(x, n)`). `COUNTER` only supports `INCREMENT BY` and `RESTART [WITH]`.

**Declaration syntax:**

```sql
INSERT INTO COLLECTION movies (watch_count COUNTER)
DOCUMENTS ({ '_id': 'tt0111161', 'title': 'The Shawshank Redemption', 'watch_count': 0 });
```

The initial value seeds the counter at zero (or whatever number you pass) and is part of the inserted document.

**Mutation pattern:** `APPLY <field> INCREMENT BY <expr>` or `APPLY <field> RESTART [WITH <expr>]`. `INCREMENT BY` accepts negative numbers (decrement). `RESTART` resets the counter to a new baseline — handy for nightly rollovers — and is **`COUNTER`-only** (no `PN_COUNTER` equivalent).

```sql
-- Increment / decrement
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY  watch_count INCREMENT BY 1
WHERE  _id = 'tt0111161';

UPDATE COLLECTION movies (watch_count COUNTER)
APPLY  watch_count INCREMENT BY -1
WHERE  _id = 'tt0111161';

-- Reset to baseline (rolls last period's count over)
UPDATE COLLECTION movies (watch_count COUNTER)
APPLY  watch_count RESTART WITH 0
WHERE  title = 'The Shawshank Redemption';
```

Counters can be combined with other mutation clauses in one statement — but `APPLY` must come **first**, before `SET` and `UNSET`; the parser rejects any other order. See [`statements.md`](statements.md) §2.1 and §2.5.

---

## 4. PN_COUNTER

See [legacy-types.md](legacy-types.md#4-pn_counter) for this topic.

## 5. ATTACHMENT

**Merge semantics:** binary blob stored out-of-band. The document field is a *handle* containing the blob's id, length, and metadata; the bytes themselves live in attachment storage. The handle field merges as last-write-wins (like a `REGISTER`), but the blob is content-addressed by id.

**When to use it:**

- Files larger than 250 KB — see the [`best-practices.md`](modeling-patterns.md#document-size-limits) document-size limits. Inlining large bytes into a `REGISTER` causes sync slowdowns and exceeds the 5 MB hard cap.
- Images, audio, video, PDFs, anything binary.
- Anywhere you want the blob fetched lazily rather than streamed with every document update.

**When NOT to use it:**

- Small, structured data — JSON, short text, numeric arrays. Just use `REGISTER`.
- Anything that needs to be queried by content. `ATTACHMENT` is opaque from DQL's point of view.

**Handle shape:** the value of an `ATTACHMENT` field is an object with these keys (the public HTTP shape — your SDK may also accept its internal shape):

| Key        | Type   | Notes                                                       |
| ---------- | ------ | ----------------------------------------------------------- |
| `id`       | string | Content id returned when the SDK created the attachment.    |
| `len`      | int    | Byte length of the blob.                                    |
| `metadata` | object | Application-defined string map. **Required** — a token literal without it is rejected (`attachment property 'metadata' is missing`); pass `{}` if you have none. |

**Declaration syntax:**

```sql
INSERT INTO COLLECTION movies (poster ATTACHMENT)
DOCUMENTS ({
  '_id'   : 'tt0111161',
  'title' : 'The Shawshank Redemption',
  'poster': { 'id': 'RUEJm...', 'len': 184230, 'metadata': { 'mime': 'image/jpeg' } }
});
```

**Mutation pattern:** `SET` to a new handle replaces the attachment; `UNSET` removes it. There is no partial-update mutator — the blob is atomic.

```sql
-- Replace the poster with a new attachment handle the SDK just created
UPDATE COLLECTION movies (poster ATTACHMENT)
SET    poster = :new_handle
WHERE  _id = 'tt0111161';

-- Remove the attachment entirely
UPDATE movies UNSET poster WHERE _id = 'tt0111161';
```

You typically obtain `:new_handle` by calling your SDK's attachment-upload API and binding the returned handle as a parameter. The raw bytes never travel through DQL.

---

## 6. Reading typed fields with `SELECT`

The same per-statement type-definition syntax applies on `SELECT`. Declare the types of any `MAP`-or-`COUNTER` fields you want to navigate or aggregate over — otherwise the planner sees them as opaque `REGISTER` values and dotted-path access can degrade.

```sql
-- Read director.name as a MAP sub-field
SELECT director.name, ratings.imdb
FROM   COLLECTION movies (director MAP, ratings MAP)
WHERE  _id = 'tt0111161';

-- Aggregate over a COUNTER
SELECT SUM(watch_count) AS total_views
FROM   COLLECTION movies (watch_count COUNTER);
```

See [`select.md`](select.md) for the rest of the `SELECT` grammar.

---

## 7. Strict mode and the `dql_strict_mode` system parameter

See [legacy-types.md](legacy-types.md#7-strict-mode-and-the-dql_strict_mode-system-parameter) for this topic.

## 8. Quick decision matrix

| Need                                                       | Type           | Mutator             |
| ---------------------------------------------------------- | -------------- | ------------------- |
| Scalar overwritten as a whole (title, score, status)       | `REGISTER`     | `SET` / `UNSET`     |
| Object with independently edited sub-fields                | `MAP`          | `SET` (bulk merge), dotted-path `SET`, nested `APPLY` |
| Distributed counter — new code, SDK 4.14+                  | `COUNTER`      | `APPLY ... INCREMENT BY`, `APPLY ... RESTART [WITH]` |
| Distributed counter — legacy, pre-4.14 (unsupported)         | `PN_COUNTER`   | `APPLY ... PN_INCREMENT BY` |
| Binary blob (image, video, file > 250 KB)                  | `ATTACHMENT`   | `SET` (new handle) / `UNSET` |

For the broader "embedded vs flat" data-modelling decision, the document-size limits, and the schema-versioning rules that constrain which type changes are safe over time, see the skill-level [`best-practices.md`](../best-practices.md).
