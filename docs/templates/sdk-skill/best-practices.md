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

## Performance

<!--
  Language-specific costs -- serialization boundaries, FFI crossings, allocation in hot
  callbacks, main-thread work. Include measured numbers or say the claim is unmeasured.
-->

TODO

## Common mistakes

<!--
  Distinct from SKILL.md's anti-patterns: those are code that compiles but is wrong;
  these are choices that work but scale badly or hurt later.
-->

TODO
