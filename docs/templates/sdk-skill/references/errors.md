# Error handling — TODO_LANGUAGE

> **Sources for this file.** The **published API reference and SDK source are primary
> here**: the `ERROR HANDLING` and "Exception Hierarchy Changes" blocks exist in
> `kotlin-v4.mdx` **only** (1 of 10 migration guides), so every other language must
> enumerate its taxonomy from the API surface. Also
> `sdk/latest/deployment/troubleshooting.mdx`.
> Expect `Evidence: api-dump` or `source` here, with the path and ref inline.

## CAP-16 Error handling

<!--
  - The error model: exceptions, Result types, error codes, or a mix.
  - The top-level error type and its variants/subtypes -- enumerate them, do not
    summarize. The reason/detail payload is what an agent needs to branch on.
  - Which calls throw vs return an error vs fail silently.
  - How errors surface from async work and from callbacks, which is often different
    from the synchronous path and is where errors get swallowed.
-->

TODO

### Error catalogue

<!--
  One row per error a developer will realistically hit. The "Seen as" column is the
  literal string in the terminal -- that is what makes this table useful to an agent.
-->

| Error | Seen as | Cause | Fix |
|---|---|---|---|
| TODO | TODO | TODO | TODO |
