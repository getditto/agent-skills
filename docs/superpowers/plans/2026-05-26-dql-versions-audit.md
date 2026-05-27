# DQL v4.14.x vs v5.0.0 Audit

**Purpose:** Working document for the ditto-dql plugin v2.0.0 update. Downstream tasks (#1–#16 of plan `2026-05-26-dql-skill-v5-update.md`) consult this when writing version annotations.

**Source trees inspected:**

- **v4.14.x:** `/Users/labeaaa/Developer/ditto-v4/` (Ditto SDK 4.14.3 — confirmed in `rust/dittolive-ditto/Cargo.toml:1`).
  DQL lives under `core/query/`, not `crates/`. Key paths:
  - Parser: `core/query/sqlparser/src/parser.rs`
  - AST: `core/query/sqlparser/src/ast/` (`mod.rs`, `query.rs`, `remove.rs`, `modification.rs`, `system.rs`, `sync.rs`, `crdt.rs`, `operator.rs`)
  - Keywords: `core/query/sqlparser/src/keywords.rs`
  - Functions: `core/query/src/functions/`
  - Execution / aggregates: `core/query/src/execution/`
  - Engine flags: `core/query/src/engine/mod.rs`
  - Reference docs: `core/query/docs/lang-ref/`
- **v5.0.0:** `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql*/` (already audited; lock provided by plan).
  - Parser: `crates/ditto-dql-parser/src/parser.rs`
  - AST: `crates/ditto-dql-shared/src/ast/`
  - Functions: `crates/ditto-dql/src/functions/`
  - Aggregates: `crates/ditto-dql/src/execution/aggregate.rs`
- **v5.1.0 reference:** `/Users/labeaaa/Developer/ditto-v5-experiments/` — excluded from this audit; v5.1.0-only features listed at the bottom.

All `file:line` references below have been grep-verified against the trees above.

---

## 1. Top-level statements

Driven from `parse_single_statement` in each parser.

| Statement       | v4.14.x | v5.0.0  | Notes |
| --------------- | ------- | ------- | ----- |
| `EXPLAIN`       | YES     | YES     | v4 `parser.rs:379`; v5 `parser.rs` (already audited) |
| `SELECT` / `WITH` | YES   | YES     | v4 `parser.rs:402` |
| `INSERT`        | YES     | YES     | v4 `parser.rs:408` |
| `UPDATE`        | YES     | YES     | v4 `parser.rs:409` |
| `EVICT FROM`    | YES     | YES     | v4 `parser.rs:410-412`; AST `ast/remove.rs:36` |
| `DELETE FROM`   | YES     | YES     | v4 `parser.rs:413-415` |
| `TOMBSTONE FROM`| YES (deprecated alias for DELETE) | YES | v4 `parser.rs:416-418`; AST `ast/remove.rs:32` ("Deprecated BP-only alias for `DELETE`") |
| `ALTER SYSTEM`  | YES     | YES     | v4 `parser.rs:4171-4205`; AST `ast/system.rs:14` (`SetParameter` / `ResetParameter`) |
| `SHOW <param>` / `SHOW ALL` | YES | YES | v4 `parser.rs:4209`; AST `ast/system.rs:46` (`Show(Option<Ident>)`) |
| `SYNC CONTEXT … SELECT/SHOW` (`RemoteQuery`) | YES | YES | v4 `parser.rs:493-525` |
| `CREATE INDEX [IF NOT EXISTS] …` | YES | YES | v4 `parser.rs:4227,4232,4257` |
| `DROP INDEX [IF EXISTS] …`       | YES | YES | v4 `parser.rs:4312-4334` |
| `ADVISE`        | NO      | NO      | Not present in either grep. v5.1.0-only. |

**v4 `Statement` enum (`ast/mod.rs:1115-1136`):** `Explain`, `Query`, `Insert`, `Update`, `Remove`, `AlterSystem`, `Show`, `RemoteQuery`, `CreateIndex`, `DropIndex` — identical surface to v5.0.0 (`ditto-dql-shared/src/ast/mod.rs:1094`).

---

## 2. INSERT ON ID CONFLICT (OnConflictAction)

Both versions define the same four variants in `ast/mod.rs`:

| Action               | v4.14.x | v5.0.0  | Notes |
| -------------------- | ------- | ------- | ----- |
| `FAIL` (default)     | YES     | YES     | v4 `ast/mod.rs:1167`; default behavior |
| `DO NOTHING`         | YES     | YES     | v4 `ast/mod.rs:1164` |
| `DO UPDATE`          | YES     | YES     | v4 `ast/mod.rs:1165` |
| `DO UPDATE_LOCAL_DIFF` | YES   | YES     | v4 `ast/mod.rs:1166`; SDK 4.12+ minimum per existing plugin note |
| `DO MERGE` (alias for `DO UPDATE`) | YES | TBD (see plan lock) | v4 `parser.rs:3717` accepts `[Keyword::UPDATE, Keyword::MERGE]` and both map to `DoUpdate`. Plan lock lists "DO MERGE — v5.1.0-only and excluded". v4 evidence here contradicts that lock — flag for review when writing the statements reference. |

---

## 3. Expression / statement feature matrix

| Feature                                  | v4.14.x | v5.0.0 | Notes |
| ---------------------------------------- | ------- | ------ | ----- |
| `CASE [<operand>] WHEN … THEN … [ELSE …] END` | YES | YES | v4 `ast/mod.rs:525` (`Expr::Case` with optional `operand`); both simple & searched forms |
| `IS NULL` / `IS NOT NULL`                | YES | YES | v4 `ast/mod.rs:338-340` |
| `IS MISSING` / `IS NOT MISSING`          | YES | YES | v4 `ast/mod.rs:342-344` |
| `IS DISTINCT FROM` / `IS NOT DISTINCT FROM` | YES | YES | v4 `parser.rs:1633-1637`; AST `ast/mod.rs:346-348` |
| `IS [NOT] TRUE` / `IS [NOT] FALSE` / `IS [NOT] UNKNOWN` | YES | YES | v4 `ast/operator.rs:175-188` |
| `[NOT] BETWEEN … AND …`                  | YES | YES | v4 `ast/mod.rs:374-378` |
| `[NOT] IN (list)`                        | YES | YES | v4 `ast/mod.rs:350-354` |
| `[NOT] IN (SELECT …)` (subquery)         | YES | YES | v4 `ast/mod.rs:356-360` |
| `[NOT] IN UNNEST(array_expr)`            | YES | YES | v4 `ast/mod.rs:362-366` |
| `[NOT] IN array_expr`                    | YES | YES | v4 `ast/mod.rs:368-372` |
| `LIKE` / `NOT LIKE`                      | YES | YES | v4 `ast/mod.rs:386-392` |
| `ILIKE` / `NOT ILIKE`                    | YES | YES | v4 `ast/mod.rs:394-399` |
| `SIMILAR TO` (regex)                     | YES | YES | v4 `ast/mod.rs:401-406` |
| Subquery `(SELECT …)`                    | YES | YES | v4 `ast/mod.rs:539` |
| `EXISTS(SELECT …)` / `NOT EXISTS(SELECT …)` | YES | YES | v4 `ast/mod.rs:533-536` |
| `ARRAY(SELECT …)` (array subquery)       | YES | YES | v4 `ast/mod.rs:541` |
| Array literal `[1, 2, …]`                | YES | YES | v4 `ast/mod.rs:555` |
| Object literal `{'k': v, …}`             | YES | YES | v4 `ast/mod.rs:557` |
| `CAST(… AS …)` / `TRY_CAST` / `SAFE_CAST`| YES | YES | v4 `ast/mod.rs:418-435`; v5 keeps `CAST` keyword |
| `EXTRACT(field FROM expr)`               | YES | YES | v4 `ast/mod.rs:444-447` |
| `POSITION(<expr> IN <expr>)`             | YES | YES | v4 `ast/mod.rs:465-468` |
| `SUBSTRING(<expr> [FROM …] [FOR …])`     | YES | YES | v4 `ast/mod.rs:472-476` |
| `TRIM([BOTH/LEADING/TRAILING] [<chars> FROM] expr)` | YES | YES | v4 `ast/mod.rs:481-486` |
| `OVERLAY(<expr> PLACING … FROM … [FOR …])` | YES | YES | v4 `ast/mod.rs:490-495` |
| `INTERVAL` literals                      | YES | YES | v4 `ast/mod.rs:566-576` |
| `AT TIME ZONE 'tz'`                      | YES | YES | v4 `ast/mod.rs:437-440` |
| `ANY/EVERY/ANY AND EVERY var IN/WITHIN expr SATISFIES cond END` (`ArraySearch`) | **NO** | YES | grep for `SATISFIES` returns 0 in v4 (`ast/`, `parser.rs`); v5 `parser.rs:3268`, `ast/mod.rs:552`. Feature is v5.0+. |
| `ARRAY expr FOR [i:]var IN src [WHEN cond] END` (`ArrayObjectTransform`) | **NO** | YES | grep for `ArrayObjectTransform`/`Quantified` returns 0 in v4; v5 `ast/mod.rs:567-583`. v5.0+. |
| `OBJECT k:v FOR [i:]var IN src [WHEN cond] END` | **NO** | YES | Same `ArrayObjectTransform` variant as above; v5.0+. |
| `XOR` as binary operator (`BinaryOperator::Xor`) | YES | **NO operator variant** (keyword tokenized, precedence assigned, but no AST op) | v4 `ast/operator.rs:80,116-118,155`; v4 keywords list includes `XOR`. v5 `keywords.rs:197` defines the keyword and `parser.rs:1391` assigns `XOR_PREC`, but `ditto-dql-shared/src/ast/operator.rs:77-97` has no `Xor` variant. **In practice XOR is unusable as an operator in v5.0.0**; plan lock saying "XOR — v5.1.0-only" is therefore accurate semantically. **In v4 it IS usable.** Annotate as `v4 only` until v5.1. |
| Bitwise `&` / `|` / `^` as `BinaryOperator` | YES (`And`/`Or` variants) | **NO** | v4 `ast/operator.rs:83-84` defines `BitwiseOr`/`BitwiseAnd`; v5 has no bitwise variants. Excluded from cross-version reference docs. |
| `RETURNING` on UPDATE / DELETE / EVICT / TOMBSTONE | YES | YES | v4 `ast/modification.rs:55-56,75-76`; `ast/remove.rs:51-52,82-83` |
| `USE IDS (…)` on `SELECT`                | YES | YES | v4 `parser.rs:3087,3316` |
| `USE IDS (…)` on `UPDATE`                | NO (parser TODO) | NO (parser TODO) | v4 `parser.rs:3778` `// TODO add USE IDS`; v5 has same TODO. |
| `USE IDS (…)` on `EVICT/DELETE/TOMBSTONE`| NO (parser TODO) | NO (parser TODO) | v4 `parser.rs:440` `// TODO add USE IDS` |
| Planner directives (`SELECT ... USE …` with JSON / context directives) | YES | YES | v4 `parser.rs:223,250,2052,2073-2121` (`Whitespace::Directive(_, json)`, `parse_directives`, `parse_collection_directives`) |
| `#profile` context-keyword directive     | **NO** | YES | grep for `PROFILE`/`profile` in v4 parser returns 0; v5 plan lock confirms `#profile` at v5 `parser.rs:378`. Annotate `v5.0+`. |
| `EXPLAIN <stmt>`                         | YES | YES | v4 `parser.rs:379-381` |
| Strict mode flag `DQL_STRICT_MODE`       | YES | YES | v4 `core/query/src/engine/mod.rs:406`; v5 `crates/hydra-subscription/src/remote_query/http.rs:90`, `crates/hydra-subscription/src/rpc/execute/mod.rs:145` |
| `DQL_RESTRICT_TO_ORIGINAL_SYNTAX` flag   | YES | YES | v4 `engine/mod.rs:371-372`; v5 `crates/hydra-common/src/query.rs:996` |
| `ARRAY_AGG` / `LISTAGG` aggregates       | YES (AST present) | YES (AST present) | v4 `ast/mod.rs:543-545`; both present in AST but treat as advanced — verify in functions task |
| `GROUPING SETS` / `CUBE` / `ROLLUP`      | YES (AST) | YES (AST) | v4 `ast/mod.rs:547-551` |
| `MATCH … AGAINST` (full-text)            | YES (AST) | YES (AST) | v4 `ast/mod.rs:589-595` |
| `OVER … PARTITION BY … ORDER BY …` (window functions) | YES (keywords + AST) | YES (keywords) | v4 `ast/mod.rs:1069-1108`; keywords list includes `OVER`, `PARTITION`, `WINDOW` bounds |

---

## 4. CRDT types (registers, counters, attachments)

Both versions define the same `CrdtType` enum (`v4 ast/crdt.rs:14-21`; v5 has same set).

| CRDT          | v4.14.x | v5.0.0 | Existing plugin annotation |
| ------------- | ------- | ------ | -------------------------- |
| `REGISTER`    | YES     | YES    | (always available) |
| `MAP`         | YES     | YES    | (always available) |
| `ATTACHMENT`  | YES     | YES    | |
| `COUNTER` (state-based, `StCounter`) | YES (v4.13+) | YES | Existing plugin: "SDK 4.13+" — keep that floor |
| `PN_COUNTER`  | YES     | YES    | Existing plugin: "SDK 4.11+" |
| `INCREMENT` / `PN_INCREMENT` mutators | YES (keyword) | YES (context-keyword) | v4 keyword list includes `INCREMENT` and `PN_INCREMENT` |

---

## 5. Function inventory (scalar functions)

Source of truth: `core/query/src/functions/mod.rs:156-251` (v4) vs `crates/ditto-dql/src/functions/mod.rs` (v5.0.0, sampled above).

**Each name was grep-confirmed in v4's `SCALAR_FUNCTIONS` table** (`functions/mod.rs:156-251`).

| Function (lowercase identifier) | v4.14.x | v5.0.0 | Notes |
| ------------------------------- | ------- | ------ | ----- |
| `abs`                           | YES (`mod.rs:193`) | YES | math |
| `ceil`                          | YES (`mod.rs:194`) | YES | math; also `Expr::Ceil` form in AST |
| `floor`                         | YES (`mod.rs:195`) | YES | math; also `Expr::Floor` form |
| `coalesce`                      | YES (`mod.rs:165`) | YES | conditionals |
| `decode`                        | YES (`mod.rs:166`) | YES | conditionals |
| `nvl`                           | YES (`mod.rs:175`) | YES | conditionals |
| `isnull`                        | YES (`mod.rs:172`) | YES | conditionals |
| `ismissing`                     | YES (`mod.rs:170`) | YES | conditionals |
| `ismissingornull`               | YES (`mod.rs:171`) | YES | conditionals |
| `ifnull`                        | YES (`mod.rs:169`) | YES | conditionals |
| `ifmissing`                     | YES (`mod.rs:167`) | YES | conditionals |
| `ifmissingornull`               | YES (`mod.rs:168`) | YES | aliased to `Coalesce` in v4; same in v5 |
| `nullif`                        | YES (`mod.rs:174`) | YES | conditionals |
| `missingif`                     | YES (`mod.rs:173`) | YES | conditionals |
| `cast`                          | YES (`mod.rs:229`) | YES | types |
| `deserialize_json`              | YES (`mod.rs:177`) | YES | conversion |
| `serialize_json`                | **NO** | **NO** | grep `serialize_json` in v4 `functions/` returns 0; absent in v5.0 (plan lock). v5.1.0-only. |
| `is_boolean`                    | YES (`mod.rs:230`) | YES | types |
| `is_number`                     | YES (`mod.rs:231`) | YES | types |
| `is_string`                     | YES (`mod.rs:232`) | YES | types |
| `type`                          | YES (`mod.rs:234`) | YES | types |
| `json_type`                     | YES (`mod.rs:233`) | YES | types |
| `byte_length`                   | YES (`mod.rs:207`) | YES | string |
| `char_length`                   | YES (`mod.rs:208`) | YES | string |
| `character_length`              | YES (`mod.rs:209`) | YES | string; alias of `CharLength` |
| `length`                        | YES (`mod.rs:214`) | YES | string; alias of `ByteLength` |
| `concat`                        | YES (`mod.rs:210`) | YES | string; also bound to `BinaryOperator::StringConcat` (`||`) |
| `contains`                      | YES (`mod.rs:211`) | YES | string |
| `starts_with`                   | YES (`mod.rs:224`) | YES | string |
| `ends_with`                     | YES (`mod.rs:212`) | YES | string |
| `ltrim`                         | YES (`mod.rs:217`) | YES | string |
| `rtrim`                         | YES (`mod.rs:222`) | YES | string |
| `trim`                          | YES (`mod.rs:226`) | YES | string |
| `upper`                         | YES (`mod.rs:227`) | YES | string |
| `lower`                         | YES (`mod.rs:215`) | YES | string |
| `repeat`                        | YES (`mod.rs:220`) | YES | string |
| `split`                         | YES (`mod.rs:223`) | YES | string |
| `joinstr`                       | YES (`mod.rs:213`) | YES | string |
| `substr`                        | YES (`mod.rs:225`) | YES | string |
| `pos`                           | YES (`mod.rs:218`) | YES | string; also `Expr::Position` form |
| `lpad`                          | YES (`mod.rs:216`) | YES | string |
| `rpad`                          | YES (`mod.rs:221`) | YES | string |
| `regexp_like`                   | YES (`mod.rs:219`) | YES | string |
| `array_contains`                | YES (`mod.rs:161`) | YES | array |
| `array_contains_null`           | YES (`mod.rs:162`) | YES | array |
| `array_length`                  | YES (`mod.rs:163`) | YES | array |
| `object_length`                 | YES (`mod.rs:198`) | YES | object |
| `object_keys`                   | YES (`mod.rs:199`) | YES | object |
| `object_values`                 | YES (`mod.rs:200`) | YES | object |
| `object_set`                    | YES (`mod.rs:201`) | YES | object |
| `object_unset`                  | YES (`mod.rs:202`) | YES | object |
| `object_concat`                 | YES (`mod.rs:203`) | YES | object |
| `object_rename`                 | YES (`mod.rs:204`) | YES | object |
| `object_content`                | YES (`mod.rs:205`) | YES | object |
| `object_field`                  | YES (`mod.rs:197`) | YES | object (not in plan's check list, but present) |
| `object_size`                   | **NO** | **NO** | grep `ObjectSize`/`object_size` returns 0 in both. v5.1.0-only. |
| `date_cast`                     | YES (`mod.rs:181`) | YES | date |
| `tz_offset`                     | YES (`mod.rs:188`) | YES | date |
| `clock`                         | YES (`mod.rs:179`) | YES | date |
| `date_format`                   | YES (`mod.rs:183`) | YES | date |
| `date_add`                      | YES (`mod.rs:180`) | YES | date |
| `date_sub`                      | YES (`mod.rs:186`) | YES | date |
| `date_diff`                     | YES (`mod.rs:182`) | YES | date |
| `date_range`                    | YES (`mod.rs:185`) | YES | date |
| `date_part`                     | YES (`mod.rs:184`) | YES | date |
| `date_trunc`                    | YES (`mod.rs:187`) | YES | date |
| `duration_cast`                 | YES (`mod.rs:190`) | YES | duration |
| `duration_format`               | YES (`mod.rs:191`) | YES | duration |
| `request_info`                  | YES (`mod.rs:159`) | YES | meta |

**Functions in BOTH versions:** every grep-confirmed name above (`abs … request_info`). The v4 `SCALAR_FUNCTIONS` table and the v5.0.0 `SCALAR_FUNCTIONS` table are line-for-line identical for the entries inspected.

**Functions in v5.0+ only (vs v4):** none observed in scalar table. Any apparent v5-only additions would be at the AST / statement level, not in the function dictionary.

**Functions in v4 only (removed in v5.0):** none observed in scalar table.

**v5.1.0-only (excluded from this audit; do not annotate):** `serialize_json`, `object_size`.

---

## 6. Aggregate functions

Source: `core/query/src/execution/aggregate.rs` (v4) vs `crates/ditto-dql/src/execution/aggregate.rs` (v5).

| Aggregate | v4.14.x | v5.0.0 | Notes |
| --------- | ------- | ------ | ----- |
| `count`   | YES (`aggregate.rs:584`) | YES (`aggregate.rs:584`) | |
| `sum`     | YES (`aggregate.rs:605`) | YES (`aggregate.rs:605`) | |
| `min`     | YES (`aggregate.rs:625`) | YES (`aggregate.rs:625`) | |
| `max`     | YES (`aggregate.rs:645`) | YES (`aggregate.rs:645`) | |
| `avg`     | YES (`aggregate.rs:665`) | YES (`aggregate.rs:665`) | |
| `mid`     | YES (`aggregate.rs:685`) | YES (`aggregate.rs:685`) | midpoint aggregate |
| `median`  | YES (`aggregate.rs:705`) | YES (`aggregate.rs:705`) | |

All seven aggregates present in both versions at the same line numbers — file is essentially unchanged.

---

## 7. Mutators / DML keywords

| Mutator clause | v4.14.x | v5.0.0 | Notes |
| -------------- | ------- | ------ | ----- |
| `UPDATE … SET …`         | YES (`parser.rs:3761`) | YES | |
| `UPDATE … UNSET …`       | YES (`parser.rs:3766`) | YES | |
| `UPDATE … APPLY <counter mutator>` | YES (`parser.rs:3756-3760`) | YES | counter increment mutators |
| `INSERT … INITIAL DOCUMENTS (…)` | YES (`parser.rs:3700`) | YES | INITIAL flag in `parse_insert` |
| `INSERT … INTO … DOCUMENTS (…)`  | YES | YES | standard form |
| `ON ID CONFLICT DO {NOTHING|UPDATE|UPDATE_LOCAL_DIFF|MERGE} / FAIL` | YES (`parser.rs:3705-3722`) | YES (lock; minus MERGE per plan note — see §2) | |
| `EVICT FROM` / `DELETE FROM` / `TOMBSTONE FROM` | YES | YES | see §1 |
| `RETURNING <projection>` (on UPDATE/DELETE/EVICT/TOMBSTONE) | YES | YES | see §3 |

---

## 8. Indexing

| Feature                             | v4.14.x | v5.0.0 | Notes |
| ----------------------------------- | ------- | ------ | ----- |
| `CREATE INDEX [IF NOT EXISTS] coll.name(key1 [ASC|DESC], …)` | YES | YES | v4 `parser.rs:4233,4257,4265` |
| `DROP INDEX [IF EXISTS] coll.name`  | YES | YES | v4 `parser.rs:4312-4334` |
| `SHOW INDEXES` (introspection)      | **NO** | **NO** | grep `SHOW INDEXES`/`ShowIndexes` returns 0 in both. (v4 `SHOW` is `Show(Option<Ident>)` — parameter name only, `ast/system.rs:46`.) v5.1.0-only if added at all. |
| `USE INDEX` / `IGNORE INDEX` planner hints (via `Whitespace::Directive` JSON) | YES (general directives) | YES (general directives) | both flow through `parse_directives` |

---

## 9. Engine / parser flags

| Flag                                | v4.14.x | v5.0.0 | Notes |
| ----------------------------------- | ------- | ------ | ----- |
| `DQL_STRICT_MODE`                   | YES     | YES    | v4 `core/query/src/engine/mod.rs:406` |
| `DQL_RESTRICT_TO_ORIGINAL_SYNTAX`   | YES     | YES    | v4 `engine/mod.rs:371-372` |

---

## 10. Excluded — v5.1.0 only

Per plan lock and grep evidence, the following are **not in v5.0.0 (and not in v4.14.x)** and must not be annotated in the v2.0.0 plugin update:

- `ADVISE` statement (no keyword in either v4 or v5.0 grep)
- `XOR` as a usable binary operator (v5.0 tokenizes the keyword and assigns precedence but does not emit a `BinaryOperator::Xor` AST node, so it cannot actually compile to an operation; v4 DOES support it as `BinaryOperator::Xor`, but documenting that as cross-version is misleading — annotate as **v4 only / removed in v5.0** OR omit entirely; see §3 caveat)
- `DO MERGE` as a documented `ON ID CONFLICT` action (parser-wise, v4 accepts `Keyword::MERGE` and folds it into `DoUpdate`, so the syntax actually parses in v4; document as "v4-only alias for `DO UPDATE`, removed in v5.0" if it needs to be mentioned, otherwise treat as v5.1.0-only canonical syntax per plan lock)
- `serialize_json` function
- `object_size` function
- `SHOW INDEXES` statement
- `#profile` directive on UPDATE / DELETE / EVICT (v5.0 accepts `#profile` on SELECT only — plan lock at v5 `parser.rs:378`)

---

## 11. Notes / cells where v4 evidence diverges from the plan's v5 lock

These are flagged for the maintainer to resolve when writing each reference file. None are blockers for Task 0 itself.

1. **`XOR`** — v4 has full `BinaryOperator::Xor` (operator.rs:80,118,155). v5.0 has the keyword and precedence but no operator variant. Practical effect: `XOR` works in v4, raises a parse / lowering error in v5.0. When the operators reference is written (Task 4), choose between (a) annotating `XOR — v4 only, replaced by `(a AND NOT b) OR (NOT a AND b)` in v5.0+ until v5.1.0`, or (b) omitting from cross-version docs entirely.

2. **`DO MERGE`** — v4 parser accepts `MERGE` as an alias of `UPDATE` in `ON ID CONFLICT DO …` (parser.rs:3717). Plan lock says "DO MERGE — NOT in v5.0.0; treat as v5.1.0-only." Both can be true: v4 supports it (folded to `DoUpdate`), v5.0 dropped support, v5.1 reintroduces it as a first-class action. When writing the statements reference (Task 7), recommend documenting the canonical name as `DO UPDATE` (works on v4 and v5.0), with a footnote that `DO MERGE` is a v4 alias that was removed in v5.0 and reintroduced in v5.1.

3. **`PROFILE` directive** — v4 has no `PROFILE`/`profile` token anywhere in the parser. v5.0 accepts `#profile` as a context-keyword. Annotate as `v5.0+`.

4. **`ANY/EVERY … SATISFIES`** and **`ARRAY/OBJECT … FOR … IN … END`** — v4 has neither keyword (`SATISFIES`, `EVERY`) nor AST variants (`ArraySearch`, `ArrayObjectTransform`). Annotate as `v5.0+`.

---

## 12. Source-of-truth file references (for future tasks)

When a downstream reference task needs to double-check anything, the canonical grep target is:

- **v4 keywords:** `/Users/labeaaa/Developer/ditto-v4/core/query/sqlparser/src/keywords.rs`
- **v4 AST root:** `/Users/labeaaa/Developer/ditto-v4/core/query/sqlparser/src/ast/mod.rs`
- **v4 parser dispatch:** `/Users/labeaaa/Developer/ditto-v4/core/query/sqlparser/src/parser.rs` (line 376 onwards for top-level dispatch)
- **v4 scalar function table:** `/Users/labeaaa/Developer/ditto-v4/core/query/src/functions/mod.rs:156-251`
- **v4 aggregates:** `/Users/labeaaa/Developer/ditto-v4/core/query/src/execution/aggregate.rs:584-705`
- **v4 lang-ref docs (human-authored):** `/Users/labeaaa/Developer/ditto-v4/core/query/docs/lang-ref/`
- **v5.0 keywords:** `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-parser/src/keywords.rs`
- **v5.0 AST root:** `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql-shared/src/ast/mod.rs`
- **v5.0 scalar function table:** `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql/src/functions/mod.rs`
- **v5.0 aggregates:** `/Users/labeaaa/Developer/ditto-v5/crates/ditto-dql/src/execution/aggregate.rs:584-705`

All path/line references in §§1–10 above were grep-verified on 2026-05-26 against these trees.
