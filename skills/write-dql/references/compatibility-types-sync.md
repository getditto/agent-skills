# Compatibility types sync — Ditto

## Contents

- [5. Defaults that flip between versions](#5-defaults-that-flip-between-versions)
- [6. `XOR` is unavailable; `DO MERGE` aliases `DO UPDATE`](#6-xor-is-unavailable-do-merge-aliases-do-update)
- [7. Detecting your SDK version](#7-detecting-your-sdk-version)

Topic index: [versions.md](versions.md). Covers Ditto SDK 4.14.x (LTS),
5.0.x, 5.1.x and 5.2.0; version-specific notes remain inline. Read only the topic needed.

For movies/reviews examples, see the [schema](schema.md) only when adapting those examples; other examples define their own fields.

### 4.4 CRDT types

| Type          | Min SDK | 4.14.x | 5.0.x | 5.1.x | 5.2.0 | Notes                                                                            |
| ------------- | ------- | :----: | :---: | :---: | :---: | -------------------------------------------------------------------------------- |
| `REGISTER`    | 4.x     |   ✓    |   ✓   |   ✓   |   ✓   | Default for scalars; default for objects under `dql_strict_mode = true`.         |
| `MAP`         | 4.x     |   ✓    |   ✓   |   ✓   |   ✓   | Default for objects under `dql_strict_mode = false` (5.x default).               |
| `ATTACHMENT`  | 4.x     |   ✓    |   ✓   |   ✓   |   ✓   | Binary blob; handle merges as `REGISTER`, bytes content-addressed.               |
| `COUNTER`     | 4.14+   |   ✓    |   ✓   |   ✓   |   ✓   | Mutators: `APPLY … INCREMENT BY` / `APPLY … RESTART [WITH]`. Declarable on `INSERT`. |
| `PN_COUNTER`  | 4.11+   |   ✓    |   ✓   |   ✓   |   ✓   | Mutator: `APPLY … PN_INCREMENT BY`. No `RESTART`. **Cannot be declared on an inline `INSERT`** on any SDK version — see [`types-mutators.md`](types-mutators.md) §4. |

See [`types-mutators.md`](types-mutators.md) for full semantics and the "COUNTER vs PN_COUNTER" decision table.

### 4.8 Subscription-query restrictions

Subscriptions are validated at `registerSubscription()` time, synchronously, before sync starts.

| Restriction                                   | 4.14.x | 5.0.x | 5.1.x | 5.2.0 | Effect                                                                            |
| --------------------------------------------- | :----: | :---: | :---: | :---: | ----------------------------------------------------------------------------------- |
| V1 surface only (`SELECT *`, one collection, no `DISTINCT` / `GROUP BY` / `HAVING` / `USE IDS` / JOIN) | ✓ | ✓ | ✓ | ✓ | Always on for `registerSubscription`. |
| `ORDER BY` / `LIMIT` rejected                 |   ✗    |   ✓   |   ✓   |   ✓   | **SDK 5.0+**. `OFFSET` alone stays legal on every SDK version. See [`select.md`](select.md) §12. |

> These restrictions are **not** settable engine parameters. `DQL_RESTRICT_TO_ORIGINAL_SYNTAX` and `DQL_RESTRICT_LIMIT_ORDER_BY` are internal Rust bitflags (`crates/ditto-dql/src/engine/mod.rs`) set by the subscription code path — `SHOW` and `ALTER SYSTEM SET` both reject those names on every version. The user-facing knob is **`dql_restrict_subscriptions`** (default `true`), which exists on 5.0.x, 5.1.x and 5.2.0 and **not** on 4.14.x.

---

## 5. Defaults that flip between versions

This is the most user-visible cross-version difference and the most likely cause of "it worked on my old SDK, why is it different now?" — see [`types-mutators.md`](types-mutators.md) §7 for the full discussion.

| Behavior                                   | 4.14.x default                            | 5.0.x default                             | 5.1.x default                             | 5.2.0 |
| ------------------------------------------ | ----------------------------------------- | ----------------------------------------- | ----------------------------------------- | ----------------------------------------- |
| `dql_strict_mode` (user-facing knob)       | `true` (strict)                           | `false` (lenient)                         | `false` (lenient)                         | `false` (lenient)                         |
| Bare object value on `INSERT` / `UPDATE`   | stored as `REGISTER` (whole-object LWW)   | stored as `MAP` (per-field merge)         | stored as `MAP` (per-field merge)         | stored as `MAP` (per-field merge)         |
| `DQL_MUTATOR_OBJECTS_AS_MAPS` (internal flag, derived from strict mode) | OFF (`false`)            | ON (`true`)                               | ON (`true`)                               | ON (`true`)                               |
| Explicit type definition required for `MAP`? | Yes — without it, strict mode picks `REGISTER` | No — lenient picks `MAP` by default, but declaring is still recommended | No — same as 5.0.x | No — same as 5.0.x |

**Portability rule:** the recommended end-state is `dql_strict_mode = false` on every peer (the 5.x default) — flip 4.x peers before upgrading them. While strict 4.x peers remain in a mixed mesh, declare types explicitly with the `INTO COLLECTION coll (field MAP, …)` syntax on every statement those peers execute that touches a non-`REGISTER` field; strict peers can't see undeclared non-REGISTER fields, on reads either.

---

## 6. `XOR` is unavailable; `DO MERGE` aliases `DO UPDATE`

- **`XOR` operator.** The docs once listed `XOR` as v4-only; the harness shows 4.14.6, 5.0.3, **and** 5.1.0 all reject it (`XOR is not supported` / `No infix parser`). Treat `XOR` as unavailable everywhere until it actually ships. **Workaround:** `a XOR b` ≡ `(a OR b) AND NOT (a AND b)`. See [`operators.md`](operators.md) §11.
- **`INSERT ... ON ID CONFLICT DO MERGE`.** SDK 4.14.6, 5.0.3, and 5.1.0 all accept `MERGE` and map it to the same action as `DO UPDATE`. It is a portable alias, not a distinct merge mode. Prefer `DO UPDATE` as the canonical spelling. See [`statements.md`](statements.md) §1.6.

---

## 7. Detecting your SDK version

Two angles. Combine them when you're not sure.
