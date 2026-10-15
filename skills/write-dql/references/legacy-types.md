# Legacy types — Ditto

## Contents

- [4. PN_COUNTER](#4-pn_counter)
- [Which counter should I use?](#which-counter-should-i-use)
- [7. Strict mode and the `dql_strict_mode` system parameter](#7-strict-mode-and-the-dql_strict_mode-system-parameter)
- [Worked example: same statement, different results](#worked-example-same-statement-different-results)
- [Recommendation: lenient everywhere, migrate strict peers off](#recommendation-lenient-everywhere-migrate-strict-peers-off)

Topic index: [types-mutators.md](types-mutators.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x and 5.1.x; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

## 4. PN_COUNTER

> **Available in:** Ditto SDK 4.11+.

**Merge semantics:** positive-negative counter — the legacy CRDT counter design that pre-dates `COUNTER`. Like `COUNTER` it sums concurrent contributions, but it **does not support `RESTART`** and uses its own dedicated mutator keyword (`PN_INCREMENT BY`).

**When to use it:**

- Documents that already use `PN_COUNTER` on existing peers (your old code base — migrating these fields would require coordinated rewrites).
- Targeting an SDK older than 4.14 (before `COUNTER` shipped — note these releases are no longer supported).

**When NOT to use it:**

- New code on SDK 4.14+. Prefer `COUNTER` for everything new — increments merge identically, and it adds `RESTART WITH` (whose set-wins semantics are the one behavioural difference; see §3).

**Declaration syntax:** *not* identical to `COUNTER`. A `PN_COUNTER` **cannot be declared on an inline `INSERT`** on any supported SDK version — 4.14.6, 5.0.3 and 5.1.0 all reject it:

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
| New code, SDK 4.14+ or 5.0.x                          | `COUNTER`      | Increments merge identically; adds set-wins `RESTART WITH`. |
| Code targeting an SDK older than 4.14 (unsupported)     | `PN_COUNTER`   | `COUNTER` does not exist yet.                      |
| Existing field in production storage already `PN_COUNTER` | `PN_COUNTER`   | Don't change the type of an existing field. See [`best-practices.md`](modeling-patterns.md#schema-versioning-best-practices). |
| Need to roll a counter to zero each period            | `COUNTER`      | `PN_COUNTER` has no `RESTART`.                     |

---

## 7. Strict mode and the `dql_strict_mode` system parameter

`dql_strict_mode` is a per-peer, runtime-only engine flag (4.11+; not persisted across restarts) that decides how plain JSON maps onto CRDT types when a statement doesn't declare them. This is the single most important cross-version behaviour change between SDK 4.14.x and the 5.x versions (5.0.x and 5.1.x share the lenient default). **This skill assumes `dql_strict_mode = false` (lenient) on every peer** — the factory default on 5.x and the migration target for every 4.14.x mesh — and all examples are written for that world.

The flag changes behavior on **both writes and reads**:

| Behavior | `false` (lenient) — **baseline** | `true` (strict) — legacy 4.14.x default |
| --- | --- | --- |
| `INSERT`/`UPDATE` object → CRDT type | `MAP` (per-field merge) — the engine duck-types JSON into CRDT intent | `REGISTER` (whole-object last-write-wins) |
| Scalars and arrays | `REGISTER` (arrays are always registers) | `REGISTER` |
| `MAP`/`REGISTER` keywords on writes | **Not needed — do not write them.** The inferred default is the intended behavior | **Required** for every non-REGISTER field — an undeclared object silently stores as `REGISTER` |
| Type declarations on reads | **Not needed — do not write them.** `SELECT` returns the most recent value of every field, whatever its CRDT type | **Required** — a MAP/COUNTER field the query doesn't re-declare is **omitted from the result entirely, as if it never existed** (no error) |
| `COUNTER` / `PN_COUNTER` / `ATTACHMENT` declarations | Still required — inference can't guess them from a JSON value | Required |
| `DQL_MUTATOR_OBJECTS_AS_MAPS` (internal) | ON (`true`), derived from strict mode | OFF (`false`), derived from strict mode |

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

- On **4.14.x** (strict factory default): `director` is stored as `REGISTER`. Two peers that concurrently write `director.born` and `director.awards.oscars` will overwrite the whole object on merge; one update is lost.
- On **5.0.x** (lenient factory default): `director` is stored as `MAP`. The same concurrent edits both survive — per-field merge.

This is a behaviour difference that does **not** show up at parse time. Both statements succeed on both versions; the difference appears only when peers reconcile.

### Recommendation: lenient everywhere, migrate strict peers off

- **On 5.x: never set the flag to `true`.** The lenient default is designed to match JSON intuition; per-field keywords exist to *override* a default (force `REGISTER` on an atomic object) or to declare what inference can't infer (`COUNTER` seeds on INSERT, `ATTACHMENT`) — not to restate it.
- **On 4.14.x (default `true`): migrate every peer to `false` — mesh-wide, and before upgrading to v5** so the version jump changes no merge behavior.
- **Transition window** (strict peers still present): declare MAP/COUNTER explicitly on every statement a strict peer executes — writes *and* reads. A strict peer silently omits undeclared non-REGISTER fields from query results, and stores undeclared objects as REGISTERs. Once every peer is lenient, stop writing `MAP`/`REGISTER` declarations.

To inspect the current mode and set it on a peer (re-apply at every app start — the flag is not persisted):

```sql
-- On v4.14.x: opt into lenient (object → MAP) behavior
ALTER SYSTEM SET dql_strict_mode = false

-- On v5.0.x: opt back into strict (object → REGISTER) behavior
ALTER SYSTEM SET dql_strict_mode = true

-- Check current setting
SHOW dql_strict_mode
```

> **Cross-peer note:** the setting is per-peer. Mismatched peers can produce per-peer divergent views of the same documents even though replication is correct. The fix is standardizing every peer on `false` — with explicit MAP/COUNTER declarations only for still-strict peers during the transition. For deeper guidance see [`best-practices.md`](strict-mode-safety.md#strict-mode).

---
