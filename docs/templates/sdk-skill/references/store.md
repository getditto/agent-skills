# Executing DQL — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/crud/{create,read,update,delete}.mdx`,
> `sdk/latest/crud/transactions.mdx`, `sdk/latest/crud/working-with-ejson.mdx`,
> `dql/indexing.mdx`, `dql/explain.mdx`, `dql/advise.mdx`, `dql/profile.mdx`,
> `sdk/latest/migration-guides/<lang>-dql.mdx`.
>
> **Do not restate DQL grammar** — that is the `dql` skill. This file is about the
> host-language call, argument binding, and result handling.

## CAP-08 Executing DQL

<!--
  - The execute call: signature, sync vs async, what it returns on each version line.
    (In v5 the return shape changed for several SDKs -- get this exactly right.)
  - Argument binding: the placeholder syntax, the argument container type, and what
    happens on a type mismatch.
  - NEVER string-concatenate values into a query. Show the correct binding instead.
  - Iterating results; whether the result set is lazy or materialized.
  - Deserializing an item into a native type: the idiomatic path and the raw path.
  - The raw/bytes variant, if present, and when it is worth using.
  - Mapping between DQL types and this language's types, including null handling.
-->

TODO

## CAP-09 Transactions

<!--
  - Opening a transaction: signature, read-only vs read-write.
  - Committing and rolling back, and how the outcome is expressed.
  - What may and may not be called inside the transaction scope.
  - Whether the transaction block is async, and what awaiting inside it does.
  - Isolation and failure behaviour; what an aborted transaction leaves behind.
-->

TODO

## CAP-10 Indexing

<!--
  - Creating an index from this language (it is a DQL statement via execute).
  - Composite / multi-column indexes and the version they require.
  - Listing and dropping indexes.
  - Running EXPLAIN / ADVISE from this language and reading the output.
  - When index creation should run relative to sync start and subscriptions.
  - Link to the dql skill for which queries an index actually helps.
-->

TODO
