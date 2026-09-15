---
title: DQL CRDT types and mutators
description: REGISTER, MAP, COUNTER (4.13+), PN_COUNTER (4.11+), and ATTACHMENT — semantics, declaration syntax, mutation patterns, and the cross-version strict-mode flip. Covers Ditto SDK 4.14.x, 5.0.x, and 5.1.x; version-gated features are tagged inline.
---

# DQL CRDT types and mutators

> All examples in this file query the `movies` / `reviews` schema documented in [`schema.md`](schema.md).

Authoritative reference for the five CRDT types DQL exposes on **Ditto SDK 4.14.x, 5.0.x, and 5.1.x**, the type-definition syntax you use to declare them on `INSERT`/`UPDATE`, and the mutation clauses that touch each one.

All three SDK versions ship the same `CrdtType` enum: `REGISTER`, `MAP`, `COUNTER` (state-based, SDK 4.13+), `PN_COUNTER` (legacy positive-negative counter, SDK 4.11+), and `ATTACHMENT`. The user-visible difference across versions is the **default strict-mode setting**, which decides whether bare object values become `REGISTER` (4.14.x default) or `MAP` (5.0.x and 5.1.x default). See [§7](#7-strict-mode-and-the-dql_strict_mode-system-parameter).

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
             |  COUNTER       -- SDK 4.13+
             |  PN_COUNTER    -- SDK 4.11+
             |  ATTACHMENT
```

Rules that apply to every CRDT type:

- The declaration is **per-statement**. It does not create a global schema; it tells the engine how to interpret values in *this* statement.
- A type definition is **required** whenever the statement touches a non-`REGISTER` field — `MAP`, `COUNTER`, `PN_COUNTER`, or `ATTACHMENT`. Without it, strict-mode v4 will silently store the value as `REGISTER`; see [§7](#7-strict-mode-and-the-dql_strict_mode-system-parameter).
- Fields omitted from the list default to `REGISTER`.
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

**Declaration syntax:** `MAP` with an optional nested type definition. Sub-fields you don't list default to `REGISTER`.

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

**Mutation pattern:** `SET` on a MAP field is a **bulk merge**, not a replace. Sub-fields you don't mention are left intact. To remove a sub-field, `UNSET` the parent and re-insert, or rebuild it.

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

> **Available in:** Ditto SDK 4.13+.

**Merge semantics:** state-based distributed counter. Every peer maintains its own contribution; the merged value is the sum across peers. Increments from concurrent offline peers all survive.

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

Counters can be combined with other mutation clauses in one statement; see [`statements.md`](statements.md) §2.5.

---

## 4. PN_COUNTER

> **Available in:** Ditto SDK 4.11+.

**Merge semantics:** positive-negative counter — the legacy CRDT counter design that pre-dates `COUNTER`. Like `COUNTER` it sums concurrent contributions, but it **does not support `RESTART`** and uses its own dedicated mutator keyword (`PN_INCREMENT BY`).

**When to use it:**

- Documents that already use `PN_COUNTER` on existing peers (your old code base — migrating these fields would require coordinated rewrites).
- Targeting an SDK pinned between 4.11 and 4.12 (i.e. before `COUNTER` shipped).

**When NOT to use it:**

- New code on SDK 4.13+. Prefer `COUNTER` for everything new — it has the same merge semantics plus `RESTART WITH`.

**Declaration syntax:** *not* identical to `COUNTER`. A `PN_COUNTER` **cannot be declared on an inline `INSERT`** on any supported SDK version — 4.14.4, 5.0.0 and 5.1.0 all reject it:

```sql
-- ✗ REJECTED on 4.14.x, 5.0.x and 5.1.x:
--   "Documents with counter CRDT fields are not supported
--    when inserting with inline expressions"
INSERT INTO COLLECTION movies (legacy_views PN_COUNTER)
DOCUMENTS ({ '_id': 'tt0111161', 'legacy_views': 0 });
```

Insert the document without the counter field, then create the counter with an `UPDATE ... APPLY`:

```sql
-- ✓ Insert the document first, with no counter field…
INSERT INTO movies DOCUMENTS ({ '_id': 'tt0111161', 'title': 'The Shawshank Redemption' })
ON ID CONFLICT DO NOTHING;

-- …then establish the PN_COUNTER via APPLY
UPDATE COLLECTION movies (legacy_views PN_COUNTER)
APPLY  legacy_views PN_INCREMENT BY 1
WHERE  _id = 'tt0111161';
```

> **⚠ On 4.14.x this only works in lenient mode.** Under 4.14.x's default `dql_strict_mode = true`, `APPLY … PN_INCREMENT BY` against a field that does not yet exist **reports success and silently does nothing** — the field never materialises. Seeding the field first as a plain value (`'legacy_views': 0`) makes it worse, not better: strict mode stores it as a `REGISTER` and every subsequent increment is silently discarded. Run `ALTER SYSTEM SET dql_strict_mode = false` before creating counters on 4.14.x, or create them on a 5.x peer. On 5.0.x and 5.1.x the default is already lenient and the `APPLY` above works as written. The same caveat applies to `COUNTER` created via `APPLY`.

> The equivalent inline `INSERT` for a plain `COUNTER` **does** work (see §3) — the restriction on inline document expressions is specific to `PN_COUNTER`, which has no inline insert path at all.

**Mutation pattern:** `APPLY <field> PN_INCREMENT BY <expr>`. **No `RESTART`** clause.

```sql
UPDATE COLLECTION movies (legacy_views PN_COUNTER)
APPLY  legacy_views PN_INCREMENT BY 1
WHERE  _id = 'tt0111161';
```

### Which counter should I use?

| Need                                                  | Pick           | Why                                                |
| ----------------------------------------------------- | -------------- | -------------------------------------------------- |
| New code, SDK 4.13+ or 5.0.x                          | `COUNTER`      | Adds `RESTART WITH`, otherwise identical merge.    |
| Code targeting SDK 4.11 or 4.12 only                  | `PN_COUNTER`   | `COUNTER` does not exist yet.                      |
| Existing field in production storage already `PN_COUNTER` | `PN_COUNTER`   | Don't change the type of an existing field. See [`best-practices.md`](../best-practices.md#schema-versioning-best-practices). |
| Need to roll a counter to zero each period            | `COUNTER`      | `PN_COUNTER` has no `RESTART`.                     |

---

## 5. ATTACHMENT

**Merge semantics:** binary blob stored out-of-band. The document field is a *handle* containing the blob's id, length, and metadata; the bytes themselves live in attachment storage. The handle field merges as last-write-wins (like a `REGISTER`), but the blob is content-addressed by id.

**When to use it:**

- Files larger than 250 KB — see the [`best-practices.md`](../best-practices.md#document-size-limits) document-size limits. Inlining large bytes into a `REGISTER` causes sync slowdowns and exceeds the 5 MB hard cap.
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
| `metadata` | object | Application-defined metadata. Optional but commonly used.   |

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

This is the single most important cross-version behaviour change between SDK 4.14.x and the 5.x versions (5.0.x and 5.1.x share the lenient default).

When the engine encounters an **object literal** in `INSERT`/`UPDATE` and no type definition tells it what to do, it picks one of two CRDT types:

- `REGISTER` (last-write-wins on the whole object) — **strict mode**
- `MAP` (per-field merge) — **lenient mode**

The choice is controlled by the user-facing system parameter `dql_strict_mode`. Its default flips between the two SDK versions:

| Behavior                                 | v4.14.x default                          | v5.0.x default                           |
| ---------------------------------------- | ---------------------------------------- | ---------------------------------------- |
| `dql_strict_mode` (user-facing)          | `true` (strict)                          | `false` (lenient)                        |
| `INSERT`/`UPDATE` object → CRDT type     | `REGISTER` (strict)                      | `MAP` (lenient)                          |
| `DQL_MUTATOR_OBJECTS_AS_MAPS` (internal) | OFF (`false`), derived from strict mode  | ON (`true`), derived from strict mode    |
| Explicit type definition REQUIRED for `MAP`? | Yes — without one, strict mode picks `REGISTER` | No — lenient picks `MAP` by default, but declaring is still recommended for clarity |

> `DQL_MUTATOR_OBJECTS_AS_MAPS` is the **internal** feature flag derived from `dql_strict_mode`; you may see it referenced in internal docs or error messages, but `dql_strict_mode` is the knob you set.

### Worked example: same statement, different results

```sql
-- Same INSERT on both versions, no type definition
INSERT INTO movies DOCUMENTS ({
  '_id'      : 'tt0111161',
  'title'    : 'The Shawshank Redemption',
  'director' : { 'name': 'Frank Darabont', 'born': 1959 }
});
```

- On **4.14.x** (strict): `director` is stored as `REGISTER`. Two peers that concurrently write `director.born` and `director.awards.oscars` will overwrite the whole object on merge; one update is lost.
- On **5.0.x** (lenient): `director` is stored as `MAP`. The same concurrent edits both survive — per-field merge.

This is a behaviour difference that does **not** show up at parse time. Both statements succeed on both versions; the difference appears only when peers reconcile.

### Cross-version recommendation

> Always declare types explicitly when you mean `MAP`, `COUNTER`, `PN_COUNTER`, or `ATTACHMENT` — even on 5.0.x.

That gives you:

- **Portability** — the same statement does the same thing on 4.14.x and 5.0.x, regardless of either peer's setting.
- **Resilience to setting changes** — a future `ALTER SYSTEM` on either peer can't silently change your data shape.
- **Clarity for reviewers** — the intent is in the query, not in engine config.

To inspect the current mode and override it on a peer (rarely needed when you declare types explicitly):

```sql
-- On v4.14.x: opt into lenient (object → MAP) behavior
ALTER SYSTEM SET dql_strict_mode = false

-- On v5.0.x: opt back into strict (object → REGISTER) behavior
ALTER SYSTEM SET dql_strict_mode = true

-- Check current setting
SHOW dql_strict_mode
```

> **Cross-peer note:** the setting is per-peer. Mismatched peers can produce per-peer divergent views of the same documents even though replication is correct. The fix is always to declare types in the statement, not to chase down every peer's setting. For deeper guidance see [`best-practices.md`](../best-practices.md#strict-mode).

---

## 8. Quick decision matrix

| Need                                                       | Type           | Mutator             |
| ---------------------------------------------------------- | -------------- | ------------------- |
| Scalar overwritten as a whole (title, score, status)       | `REGISTER`     | `SET` / `UNSET`     |
| Object with independently edited sub-fields                | `MAP`          | `SET` (bulk merge), dotted-path `SET`, nested `APPLY` |
| Distributed counter — new code, SDK 4.13+                  | `COUNTER`      | `APPLY ... INCREMENT BY`, `APPLY ... RESTART [WITH]` |
| Distributed counter — legacy, pre-4.13                     | `PN_COUNTER`   | `APPLY ... PN_INCREMENT BY` |
| Binary blob (image, video, file > 250 KB)                  | `ATTACHMENT`   | `SET` (new handle) / `UNSET` |

For the broader "embedded vs flat" data-modelling decision, the document-size limits, and the schema-versioning rules that constrain which type changes are safe over time, see the skill-level [`best-practices.md`](../best-practices.md).
