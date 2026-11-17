# Observers and live queries — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/crud/observing-data-changes.mdx`,
> `dql/replacing-live-queries.mdx`, and the `OBSERVERS` block in
> `sdk/latest/migration-guides/<lang>-v4.mdx` (present in 8 of 10 — not `java-v4`,
> `rust-v4`).
>
> **Back-pressure has almost no prose coverage:** the `BACK-PRESSURE` heading exists in
> `kotlin-v4.mdx` only, and the literal `signalNext` appears in 7 of 10 guides. Source
> it from the API reference or SDK source for most languages.
> **Slugs are not uniform.** Resolve `<lang>` per directory using the table in
> `docs/SDK-SKILL-TEMPLATE.md` §8.1 — JS, Java, C# and Go do not follow the
> obvious pattern, and Go has no migration guides at all.


## CAP-11 Observers and live queries

<!--
  - Registering an observer: signature, argument binding, return type.
  - The idiomatic reactive form if the language has one (Flow, AsyncSequence,
    Observable, Stream, channel) and how it relates to the callback form.
  - WHICH THREAD the callback arrives on. State it explicitly.
  - Whether the first emission is immediate, and whether it fires before sync starts.
  - Retention: what must hold the handle. This is the #1 observer bug -- include the
    symptom (callbacks stop silently, no error).
  - Cancellation: how to stop it, whether it is synchronous, and whether an in-flight
    callback can still fire afterwards.
  - Diffing: how to get inserts/updates/deletes/moves rather than the whole result set.
  - Back-pressure / signal-next: the variant that waits for the consumer, when to use
    it, and what happens without it on a fast-changing query.
  - What is unsafe to do inside the callback (blocking, re-entrant writes, UI work).
-->

TODO
