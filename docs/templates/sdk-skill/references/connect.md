# Connecting, authenticating and lifecycle — TODO_LANGUAGE

> **Sources for this file.** `snippets/connect-examples-v5/playground/<lang>-playground.mdx`
> — note this directory uses `csharp`, not `c-sharp`. Also `sdk/latest/quickstarts/`,
> and `snippets/connect-examples-v5/development/`, which holds only `go` and `java`,
> `sdk/latest/auth-and-authorization/*.mdx`, `sdk/latest/sync/syncing-data.mdx`,
> and the INITIALIZATION / AUTHENTICATION blocks in
> `sdk/latest/migration-guides/<lang>-v4.mdx`.

## CAP-03 Connecting

<!--
  - Building the config object: every field, its type, and which are optional.
  - Each connect mode the SDK offers, including the offline/small-peers-only mode.
  - Where the URL and database ID come from, and which portal field maps to which.
  - Opening the instance: is it a constructor, a factory, or async? Does it throw?
  - The persistence directory: default location per platform, how to override it,
    and what happens if two instances share one.
  - Any process-wide init that must happen first.
-->

TODO

## CAP-04 Authentication and identity

<!--
  - The expiration handler: exact type, how it is assigned (property vs method --
    getting this wrong is a top v5 migration failure), and when it fires.
  - Whether the handler must be set BEFORE sync starts, and the exact error if not.
  - login(): signature, providers available, sync vs async, how failure surfaces.
  - logout() and what it cleans up.
  - Observing authentication status.
  - Whether the auth object is nullable/absent in offline modes, and how to guard.
  - Offline-only license tokens for no-cloud deployments.
  - Link to the data-authorization concept docs rather than restating permission rules.
-->

TODO

## CAP-05 Lifecycle

<!--
  - Starting and stopping sync; whether either throws; whether they are idempotent.
  - Checking whether sync is currently active.
  - Shutting down: the close/dispose call, whether it is required, and what leaks
    without it.
  - Instance ownership: where the instance should live so it is not collected
    (application object, DI container, static, actor). Include the real symptom of
    getting this wrong.
  - Behaviour across app lifecycle events: background/foreground, suspend/resume,
    process death, hot reload.
-->

TODO
