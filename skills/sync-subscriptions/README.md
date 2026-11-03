# sync-subscriptions

Agent skill explaining how **Ditto sync subscriptions** work — conceptually,
for every SDK. It covers what subscription queries can express, how
subscriptions propagate documents across the peer-to-peer mesh, and the
multi-hop "document flooding" behavior behind most missing-data reports.

This skill is **language-agnostic**. It deliberately does not cover
per-language `registerSubscription` API syntax (planned as separate
per-language skills; see the
[Ditto docs](https://docs.ditto.live/sdk/latest/sync/syncing-data) in the
meantime).

## What's inside

| File | Contents |
|---|---|
| `SKILL.md` | Mental model, query rules summary, mesh/flooding essentials, anti-patterns, routing table |
| `references/how-subscriptions-work.md` | Lifecycle, delta sync, in-memory/dedup/cancel semantics, out-of-scope documents, attachments |
| `references/query-limitations.md` | Every rejected query feature with exact error strings and version differences |
| `references/mesh-and-flooding.md` | Pairwise sessions, the two send/receive rules, transitive sync, the A→B→C subset problem |
| `examples/mesh-scenarios.md` | Six worked multi-peer scenarios |
| `best-practices.md` | Scoping, stability, flood-fill design, stateful subscriptions, operational pitfalls |

## Supported versions

Ditto SDK **4.14.x (LTS)**, **5.0.x**, **5.1.x**, **5.2.0**. Version differences — the
headline one being rejection of `LIMIT`/`ORDER BY` in subscription queries on
5.0+ — are
tagged inline wherever they appear.

Content verified against the Ditto source tree (main and the 4.14/5.0/5.1
stable branches) and cross-checked with docs.ditto.live; where the docs are
silent (e.g. exact error strings, persistence semantics), claims rest on
source verification. Last verified: 2026-08.

## Status

Conceptual skill: no executable statements, so no test harness (see
`tests/dql/` for how executable skills are verified). Accuracy is enforced by
adversarial review against the Ditto source tree before release.
