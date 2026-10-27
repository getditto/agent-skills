# Concurrency and threading — TODO_LANGUAGE

> **Sources for this file.** The API reference for every callback-registering method, the
> `THREADING` / `CONCURRENCY` blocks in `sdk/latest/migration-guides/<lang>-v4.mdx` where
> present, and SDK source where the docs are silent — which is common. State which.

<!--
  This file holds the per-API TABLE and the reasoning. SKILL.md § Concurrency and
  threading model holds the numbered rules that follow from it, and links here. Spec §5.

  Add a `## Contents` list once this file passes 8,000 characters or 200 lines — CI enforces it (spec §3).
-->

Which thread or executor every SDK callback arrives on, and what that forces the calling
code to do. The load-bearing rules are in
[`SKILL.md` § Concurrency and threading model](../SKILL.md#concurrency-and-threading-model);
this file is the detail.

## Where each callback runs

<!--
  One row per API that takes a callback or returns asynchronously. Name the ACTUAL
  thread/executor/dispatcher/isolate — "a background thread" is not an answer. Where the
  answer differs across version lines, say so in the row; references/versions.md owns the
  full cross-version delta.
-->

| API | Where its callback runs |
|---|---|
| TODO | TODO |

## The rules

<!-- The full text of each rule summarised in SKILL.md, with the reasoning. -->

TODO

## Getting from a callback to the UI

<!--
  The idiomatic hand-off for this language, and the ordering hazard if there is one.
  Include the retain/leak shape if the hand-off can create a cycle.
-->

TODO
