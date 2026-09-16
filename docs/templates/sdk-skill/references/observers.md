# Observers and live queries — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/crud/observing-data-changes.mdx`,
> `dql/replacing-live-queries.mdx`, and the OBSERVERS / BACK-PRESSURE blocks in
> `sdk/latest/migration-guides/<lang>-v4.mdx`.

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
