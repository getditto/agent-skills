---
name: TODO-lang-sdk
description: >
  Use when writing, reviewing or debugging Ditto TODO_LANGUAGE SDK code —
  TODO_API_NAME_1, TODO_API_NAME_2, TODO_ERROR_STRING_1, TODO_ERROR_STRING_2.
  Covers TODO_PACKAGE_COORDINATE on Ditto SDK 4.14.x, 5.0.x and 5.1.x: connecting,
  authentication, transports, subscriptions, DQL execution, observers, attachments,
  presence, logging and v4 to v5 migration. Use ONLY for TODO_LANGUAGE; see the dql
  skill for query syntax and data-modeling for CRDT structure.
---

<!--
  SKELETON — copy this directory to skills/<lang>-sdk/ and fill it in.
  The structure below is normative: see docs/SDK-SKILL-TEMPLATE.md.
  Do not add, remove, rename or reorder the ## headings.
  Delete every TODO and every HTML comment before opening a PR.
-->

# Ditto TODO_LANGUAGE SDK

## What this skill does

<!-- 2-3 sentences. Language, package coordinate, versions covered. -->

TODO

## When to use this skill

Use this skill for **TODO_LANGUAGE** Ditto code: API shape, initialization, object
lifetimes, threading, error types, and build configuration.

Hand off to the concept skills rather than restating them:

| Question | Skill |
|---|---|
| DQL syntax, operators, functions, statement semantics | `dql` |
| Which CRDT type to use, embed vs split, document size | `data-modeling` |
| What a subscription is, query limitations, mesh propagation | `sync-subscriptions` |
| Transport selection strategy, mesh formation, platform radios | `ditto-mesh-networking` |

Do **not** use this skill for TODO_OTHER_LANGUAGES — each SDK has its own skill.

## Supported versions and packages

<!-- One row per supported version line. Full matrix in references/versions.md. -->

| Ditto SDK | Package coordinate | Minimum toolchain | Minimum platform |
|---|---|---|---|
| 5.1.x | TODO | TODO | TODO |
| 5.0.x | TODO | TODO | TODO |
| 4.14.x (LTS) | TODO | TODO | TODO |

Published API reference: TODO_URL

**When the user's version is unknown, emit 5.1.x code and say so.** v4 and v5 are
different APIs, not different versions of one API — see
[`references/versions.md`](references/versions.md).

## Capability map

<!--
  All twenty rows are REQUIRED. Never delete a row.
  Status is one of: supported | preview | partial | not-available | undocumented
  See docs/SDK-SKILL-TEMPLATE.md §7 for what each status obliges you to add.
-->

| ID | Capability | Status | Where |
|----|-----------|--------|-------|
| CAP-01 | Prerequisites, toolchain, package install | TODO | [setup.md](references/setup.md#cap-01-prerequisites-and-install) |
| CAP-02 | Platform permissions, entitlements, build config | TODO | [setup.md](references/setup.md#cap-02-permissions-and-platform-configuration) |
| CAP-03 | Connecting: config, opening, persistence directory | TODO | [connect.md](references/connect.md#cap-03-connecting) |
| CAP-04 | Authentication and identity | TODO | [connect.md](references/connect.md#cap-04-authentication-and-identity) |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | TODO | [connect.md](references/connect.md#cap-05-lifecycle) |
| CAP-06 | Customizing transports | TODO | [transports.md](references/transports.md#cap-06-customizing-transports) |
| CAP-07 | Sync subscriptions and sync scopes | TODO | [sync.md](references/sync.md#cap-07-sync-subscriptions) |
| CAP-08 | Querying the store: executing DQL | TODO | [store.md](references/store.md#cap-08-executing-dql) |
| CAP-09 | Transactions | TODO | [store.md](references/store.md#cap-09-transactions) |
| CAP-10 | Indexing | TODO | [store.md](references/store.md#cap-10-indexing) |
| CAP-11 | Observers, diffing and back-pressure | TODO | [observers.md](references/observers.md#cap-11-observers-and-live-queries) |
| CAP-12 | Attachments | TODO | [attachments.md](references/attachments.md#cap-12-attachments) |
| CAP-13 | Presence graph and connection requests | TODO | [presence.md](references/presence.md#cap-13-presence-and-connection-requests) |
| CAP-14 | Sync status and local commit tracking | TODO | [sync.md](references/sync.md#cap-14-sync-status) |
| CAP-15 | Logging, diagnostics and stats | TODO | [observability.md](references/observability.md#cap-15-logging-diagnostics-and-stats) |
| CAP-16 | Error handling | TODO | [errors.md](references/errors.md#cap-16-error-handling) |
| CAP-17 | Device storage management and eviction | TODO | [sync.md](references/sync.md#cap-17-device-storage-management) |
| CAP-18 | Testing | TODO | [testing.md](references/testing.md#cap-18-testing) |
| CAP-19 | v4 to v5 migration delta | TODO | [versions.md](references/versions.md#cap-19-v4-to-v5-migration) |
| CAP-20 | Preview and platform-specific APIs | TODO | [preview.md](references/preview.md#cap-20-preview-apis) |

## Minimum viable app

<!--
  ONE complete, copy-pasteable program that compiles as written.
  Must cover: configure -> authenticate -> start sync -> subscribe -> observe -> write.
  Include imports and the enclosing async/suspend/main context. Elide nothing.
  Longer worked version: examples/minimal-app.md
-->

```TODO_LANG
TODO
```

Full walkthrough: [`examples/minimal-app.md`](examples/minimal-app.md).

## Concurrency and threading model

<!--
  The single most common source of language-specific bugs. Be concrete:
  - Which thread / executor / dispatcher / isolate do observer callbacks arrive on?
  - Which calls are blocking and must not run on the UI thread?
  - Which calls are suspend / async / return a future, and what awaits them?
  - How is a callback cancelled, and is cancellation synchronous?
  - What is safe to call from inside a callback, and what deadlocks?
-->

TODO

## Object lifetimes and retention

<!--
  The second most common source of bugs. For each of the following, say what must
  hold a strong reference, for how long, and what the observable symptom is when it
  is dropped early:
  - the Ditto instance
  - sync subscriptions
  - store observers
  - attachment fetchers
  - the presence observer
  Then say how each is explicitly closed and whether closing is idempotent.
-->

TODO

## Anti-patterns

<!--
  Code that compiles but is wrong. Each entry needs three parts.
  Mine sdk/latest/migration-guides/<lang>-v4.mdx for the real ones -- its
  "FORBIDDEN patterns" blocks name constructs that genuinely fail.
-->

### TODO_ANTIPATTERN_NAME

```TODO_LANG
// WRONG
TODO
```

**Symptom:** TODO — the exact compiler error, exception name, or wrong runtime behaviour.

```TODO_LANG
// CORRECT
TODO
```

## Version differences

<!-- Short form only. The full table lives in references/versions.md. -->

| Concern | 4.14.x | 5.0.x / 5.1.x |
|---|---|---|
| Package / namespace | TODO | TODO |
| Initialization | TODO | TODO |
| Start sync | TODO | TODO |
| Query model | TODO | TODO |

Full delta and migration steps: [`references/versions.md`](references/versions.md).

## References

<!-- Map a QUESTION an agent would have to the file that answers it. Not a file list. -->

| If you need to know… | Read |
|---|---|
| How do I install it and what are the platform minimums? | [references/setup.md](references/setup.md) |
| How do I open Ditto, authenticate, and start syncing? | [references/connect.md](references/connect.md) |
| How do I change which transports are used? | [references/transports.md](references/transports.md) |
| How do I subscribe, scope sync, and check sync status? | [references/sync.md](references/sync.md) |
| How do I run a DQL statement and read the results? | [references/store.md](references/store.md) |
| How do I react to data changes without polling? | [references/observers.md](references/observers.md) |
| How do I store and fetch a file? | [references/attachments.md](references/attachments.md) |
| Who else is on the mesh right now? | [references/presence.md](references/presence.md) |
| How do I turn on logs and see disk usage? | [references/observability.md](references/observability.md) |
| What error is this and how do I recover? | [references/errors.md](references/errors.md) |
| How do I test code that uses Ditto? | [references/testing.md](references/testing.md) |
| What changed between 4.14.x and 5.x? | [references/versions.md](references/versions.md) |
| What is preview or platform-specific here? | [references/preview.md](references/preview.md) |
| What are the idiomatic patterns and pitfalls? | [best-practices.md](best-practices.md) |
