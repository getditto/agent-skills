# data-modeling (Ditto)

Agent skill for designing, reviewing, and migrating data models for
[Ditto](https://ditto.com) — the CRDT-based peer-to-peer database. Given raw
JSON and deployment context, the skill produces CRDT-aware collection designs:
REGISTER vs MAP vs COUNTER vs ATTACHMENT per field, embed-vs-split decisions,
document size budgets, and version-tagged guidance.

## Supported versions

| Ditto SDK | Status | Covered |
|---|---|---|
| 4.14.x | LTS | ✓ (strict-mode `true` factory default — guidance assumes migration to `false`; no JOINs) |
| 5.0.x | Supported | ✓ |
| 5.2.0 | Latest known baseline | ✓ (including document-size enforcement during replication) |
| 5.1.x | Historical baseline | ✓ (JOINs, composite indexes — headlining target) |

Every version-gated claim inside the skill is tagged inline (`4.14+`, `5.0+`,
`5.1+`) and ladders up to
[`references/versions.md`](references/versions.md).

Last verified against docs.ditto.live and Ditto source: 2026-08-25.

## Contents

| File | What's in it |
|---|---|
| [`SKILL.md`](SKILL.md) | Entry point: routing, intake discipline, the five flags, output contract |
| [`references/crdt-types.md`](references/crdt-types.md) | REGISTER / MAP / COUNTER / PN_COUNTER / ATTACHMENT merge semantics + decision matrix |
| [`references/workflow.md`](references/workflow.md) | Intake questions, JSON review rubric (stable finding IDs), output format |
| [`references/versions.md`](references/versions.md) | 4.14.x / 5.0.x / 5.1.x feature matrix for modeling |
| [`references/performance.md`](references/performance.md) | Size limits, merge cost, BLE/LAN budget, hardware tiers, observers |
| [`best-practices.md`](best-practices.md) | Default embed pattern, split triggers, audit logs, soft delete, anti-patterns |
| [`examples/`](examples) | Cookbook: POS order, chat+media, IoT telemetry, MongoDB/SQL migration |

## Tests

The agent-skills repository's `tests/data-modeling/` contains review cases:
raw JSON inputs with expected findings (keyed to the rubric IDs), plus a runner
that feeds them to live AI models and scores the recommendations
deterministically.

## Related

- [`../write-dql/`](../write-dql) (`write-dql`) — the DQL syntax skill this one cites for
  statement grammar, mutators, indexing, and the DQL-side version matrix.
- Official docs: <https://docs.ditto.live/best-practices/data-modeling>,
  <https://docs.ditto.live/dql/types-and-definitions>,
  <https://docs.ditto.live/dql/strict-mode>,
  <https://docs.ditto.live/best-practices/document-size-limits>.
