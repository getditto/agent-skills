# Testing — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/deployment/testing.mdx`, plus the test
> harnesses in the SDK source tree for this language.

## CAP-18 Testing

<!--
  - Wrapping Ditto behind an interface so business logic can be unit-tested without it.
  - Creating a real instance for a test: offline identity, no sync, temporary
    persistence directory. Show the actual construction.
  - Isolating instances so parallel tests do not collide (unique directory, unique
    database ID, collection prefixing).
  - Tearing down cleanly, including whether the directory must be deleted between runs.
  - Two instances in one process for a sync test: whether it works in this SDK, and how.
  - Running in CI: headless constraints, which transports are unavailable, timeouts.
  - Awaiting convergence deterministically instead of sleeping.
-->

TODO
