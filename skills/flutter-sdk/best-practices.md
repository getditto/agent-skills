# Best practices — Ditto TODO_LANGUAGE SDK

<!--
  Idiom and judgement, not API reference. If a claim is about the API surface it
  belongs in references/; if it is about which of two working approaches to choose,
  it belongs here. Delete every TODO and HTML comment before opening a PR.
-->

## Instance ownership

<!-- Where the Ditto instance should live in an idiomatic app of this language. -->

TODO

## Structuring async work

<!-- The idiomatic concurrency primitive, and how Ditto's API composes with it. -->

TODO

## Retaining handles

<!-- The idiomatic place to keep subscriptions, observers and fetchers alive. -->

TODO

## Writes

<!-- Batching, argument binding over concatenation, when a transaction earns its cost. -->

TODO

## Reads and observers

<!-- One broad observer vs many narrow ones; when to diff; when to use back-pressure. -->

TODO

## Error handling

<!-- What to retry, what to surface, what is fatal. -->

TODO

## Sync handling

<!-- Source: best-practices/sync-handling.mdx. When to start/stop sync, and why. -->

TODO

## Performance

<!--
  Architectural performance choices only -- how to shape a query set, how many observers.
  A specific hot-path footgun with a named symbol goes in SKILL.md §8 instead.
  Include measured numbers or say the claim is unmeasured.
-->

TODO

## Common mistakes

<!--
  The boundary with SKILL.md §8 is LOAD ORDER, not "wrong vs slow" (spec §5):
  §8 holds anything that changes the code an agent emits BY DEFAULT and has a nameable
  symptom -- performance footguns included. This file holds architectural judgement
  with no single right answer. If it has a named symbol or a measured factor, it
  belongs in §8, where it is always loaded.
-->

TODO
