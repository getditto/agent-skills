# Minimal JavaScript application

The normative program is [minimal-app.mjs](../assets/minimal-app.mjs). It is executed
unchanged by the harness; the source is shipped with the skill, not copied into prose.

Copy it into an empty Node project, install `@dittolive/ditto@5.2.0`, set
`DITTO_OFFLINE_LICENSE` (and optionally `DITTO_DATABASE_ID`), then run
`node minimal-app.mjs`. Its temporary store is deliberately removed after completion;
applications use a stable writable path instead.

Expected successful output: `SDK: 5.2.0; observed: Learn Ditto`.
A missing license or observer timeout exits nonzero. Actual execution results are in
[the harness report](../../../tests/js-sdk/README.md).
