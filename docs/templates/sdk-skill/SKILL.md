---
name: TODO-lang-sdk
description: >
  Use ONLY for the Ditto TODO_LANGUAGE SDK (not TODO_OTHER_EIGHT — each has its own
  skill). Triggers on TODO_FILE_EXTENSIONS, TODO_BUILD_FILE_NAMES,
  TODO_PACKAGE_COORDINATE, TODO_API_NAME_1, TODO_API_NAME_2, TODO_OBSERVED_ERROR_STRING.
  Ditto SDK 4.14.x, 5.0.x, 5.1.x.
allowed-tools: Read, Grep, Glob, Edit, Write
---

<!--
  SKELETON — copy this directory to skills/<lang>-sdk/ and fill it in.
  The structure below is normative: see docs/SDK-SKILL-TEMPLATE.md.
  Do not add, remove, rename or reorder the ## headings.

  The description above is a DRAFT until you have written references/errors.md.
  Workflow step 9 requires you to rewrite it with error strings you actually observed.

  Delete every TODO and every HTML comment before opening a PR.
-->

# Ditto TODO_LANGUAGE SDK

<!-- A substantive lead paragraph here is permitted and encouraged. -->

TODO

## What this skill does

<!-- 2-3 sentences. Language, package coordinate, versions covered. -->

TODO

## When to use this skill

Use this skill for **TODO_LANGUAGE** Ditto code: API shape, initialization, object
lifetimes, threading, error types, and build configuration.

Hand off rather than restating. Each row names a public docs URL because the concept
skill ships as a separate plugin and may not be installed:

| Question | Skill, if installed | Otherwise |
|---|---|---|
| DQL syntax, operators, statement semantics | `dql` | <https://docs.ditto.com/dql/dql> |
| Which CRDT type, embed vs split, document size | `data-modeling` | <https://docs.ditto.com/key-concepts> |
| What a subscription is, mesh propagation | `sync-subscriptions` | <https://docs.ditto.com/sdk/latest/sync/syncing-data> |
| Transport selection strategy, platform radios | `ditto-mesh-networking` | <https://docs.ditto.com/sdk/latest/sync/customizing-transport-configurations> |

See `docs/SDK-SKILL-TEMPLATE.md` §1 for who owns contested topics such as platform
permissions and transport-condition values.

Do **not** use this skill for TODO_OTHER_LANGUAGES — each SDK has its own skill.

## Supported versions and packages

Package: `TODO_PACKAGE_COORDINATE`. Published API reference: TODO_URL.

**[`references/versions.md`](references/versions.md) owns every fact that differs across
version lines**, including package coordinates per version and the minimum toolchain.
This section is a pointer, not a claim.

**When the user's version is unknown, emit 5.1.x code and say which version you
assumed.** v4 and v5 are different APIs, not two versions of one.

## Capability exceptions

<!--
  ONLY the rows whose Support is not `yes`. The full twenty-row map with
  Support / Evidence / Targets lives in README.md.
  If there are no exceptions, write exactly: "None — all twenty capabilities are
  `Support: yes`. See README.md for the full map."
-->

| ID | Capability | Support | Detail |
|----|-----------|---------|--------|
| TODO | TODO | TODO | TODO — §7 requires a reason for every non-`yes` row |

Full capability map: [`README.md`](README.md).

## Minimum viable app

<!--
  The SHORTEST form that actually runs: open -> subscribe -> observe -> write.
  Target ~25 lines. It must agree with examples/minimal-app.md, which is the
  normative, compiled-and-run program. Do not duplicate the whole thing here.
-->

```TODO_LANG
TODO
```

Complete program, with dependency declaration and a real run transcript:
[`examples/minimal-app.md`](examples/minimal-app.md).

## Concurrency and threading model

<!--
  The single most common source of language-specific bugs. Be concrete, and note
  where two APIs differ (e.g. a callback registration vs the reactive form):
  - Which thread / executor / dispatcher / isolate does each callback arrive on?
  - Which calls block and must not run on the UI thread?
  - Which are suspend / async / return a future, and what awaits them?
  - How is a callback cancelled; is cancellation synchronous; can one still fire after?
  - What is safe to call from inside a callback, and what deadlocks?
-->

TODO

## Object lifetimes and retention

<!--
  The second most common source of bugs. For each of: the Ditto instance, sync
  subscriptions, store observers, attachment fetchers, the presence observer --
  say what must hold a strong reference, for how long, and the OBSERVABLE SYMPTOM
  when it is dropped early. Then how each is closed, and whether closing is idempotent.
-->

TODO

## Anti-patterns

<!--
  Anything that changes the code an agent emits BY DEFAULT and has a nameable symptom:
  a compiler error, an exception name, a profiler symbol, or a measured factor.
  Performance footguns belong HERE, not in best-practices.md -- this file is always
  loaded; best-practices.md is only loaded if the agent follows a link.

  Mine sdk/latest/migration-guides/<lang>-v4.mdx for real ones -- its "FORBIDDEN
  patterns" blocks name constructs that genuinely fail. Check it exists for your
  language first; the named blocks are unevenly distributed (spec Appendix B).
-->

### TODO_ANTIPATTERN_NAME

```TODO_LANG
// WRONG
TODO
```

**Symptom:** TODO — the exact compiler error, exception name, profiler symbol, or
measured factor. Never the word "slow".

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
| On-disk store | TODO | TODO |

Full delta, including on-disk store migration:
[`references/versions.md`](references/versions.md).

## References

| If you need to know… | Read |
|---|---|
| How do I install it and what are the platform minimums? | [references/setup.md](references/setup.md) |
| How do I open Ditto, authenticate, and start syncing? | [references/connect.md](references/connect.md) |
| How do I change which transports are used? | [references/transports.md](references/transports.md) |
| How do I subscribe and check sync status? | [references/sync.md](references/sync.md) |
| How do I run DQL, transact, index, or evict? | [references/store.md](references/store.md) |
| How do I react to data changes without polling? | [references/observers.md](references/observers.md) |
| How do I store and fetch a file? | [references/attachments.md](references/attachments.md) |
| Who else is on the mesh right now? | [references/presence.md](references/presence.md) |
| How do I turn on logs and see disk usage? | [references/observability.md](references/observability.md) |
| What error is this and how do I recover? | [references/errors.md](references/errors.md) |
| How do I test code that uses Ditto? | [references/testing.md](references/testing.md) |
| What changed between 4.14.x and 5.x, on disk and in the API? | [references/versions.md](references/versions.md) |
| What is preview or platform-specific here? | [references/preview.md](references/preview.md) |
| Where should the instance live; which observer shape? | [best-practices.md](best-practices.md) |
