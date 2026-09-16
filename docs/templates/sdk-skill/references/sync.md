# Subscriptions and sync status — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/sync/syncing-data.mdx`,
> `sdk/latest/sync/sync-scopes.mdx`, `sdk/latest/sync/monitoring-sync-status.mdx`,
> `sdk/latest/sync/tracking-local-commits.mdx`, `sdk/latest/sync/cloud-sync-status.mdx`,
> `sdk/latest/sync/using-alter-system.mdx` (the only page with host-language
> `ALTER SYSTEM` samples — Java and Swift), `dql/alter-system.mdx`.
>
> **Do not restate what a subscription is or how flooding works** — that is the
> `sync-subscriptions` skill.

## CAP-07 Sync subscriptions

<!--
  - Registering a subscription: signature, argument binding, return type.
  - What must retain the returned handle, and the symptom when it is dropped.
  - Closing a subscription, and whether closing is idempotent.
  - Enumerating currently-registered subscriptions.
  - Whether subscriptions may be registered before sync starts.
  - Sync scopes: the ALTER SYSTEM call in this language, when it must run relative to
    sync start, and the argument shape.
-->

TODO

## CAP-14 Sync status

<!--
  - Local commit tracking: the API, what a commit ID means, and how to await one.
  - Cloud sync status: how to tell whether the cloud has the local writes.
  - Per-peer sync status, if the SDK exposes it.
  - What each of these is NOT: none of them is a delivery receipt for the whole mesh.
    State that explicitly -- it is a common misreading.
-->

TODO
