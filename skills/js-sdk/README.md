# Ditto JavaScript / TypeScript skills

Install the **ditto-js** plugin for the generic SDK skill, four platform recipes,
and shared native configuration. Installation: `docs/install-js.md` in the agent-skills repository.

## Capability map

**Targets vocabulary for this SDK:** `all`, `native`, `node`, `web`.
Targets describe SDK availability, not proof of execution on every target. Exact
verification and remaining device checks are in the harness report, `tests/js-sdk/README.md` in the agent-skills repository.

| ID | Capability | Support | Evidence | Targets |
|---|---|---|---|---|
| CAP-01 | Prerequisites, toolchain, package install | yes | executed | all |
| CAP-02 | Platform permissions, entitlements, build config | yes | docs-sample | all |
| CAP-03 | Connecting: config, opening, persistence directory | yes | executed | all |
| CAP-04 | Authentication and identity | yes | executed | all |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | yes | executed | all |
| CAP-06 | Customizing transports | yes | executed | all |
| CAP-07 | Sync subscriptions and sync scopes | yes | executed | all |
| CAP-08 | Querying the store: executing DQL | yes | executed | all |
| CAP-09 | Transactions | yes | executed | all |
| CAP-10 | Indexing | yes | executed | all |
| CAP-11 | Observers, diffing and back-pressure | yes | executed | all |
| CAP-12 | Attachments | yes | executed | all |
| CAP-13 | Presence graph and connection requests | yes | api-dump | all |
| CAP-14 | Sync status and local commit tracking | partial | api-dump | all |
| CAP-15 | Logging, diagnostics and stats | yes | api-dump | all |
| CAP-16 | Error handling | yes | executed | all |
| CAP-17 | Device storage management and eviction | yes | executed | all |
| CAP-18 | Testing | yes | executed | all |
| CAP-19 | v4 to v5 migration, API and on-disk store | yes | docs-sample | all |
| CAP-20 | Preview and platform-specific APIs | partial | api-dump | all |

- **CAP-04**: Authentication handler and login result contracts; cloud execution is separate from local tests. Source: published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts`; [API](https://software.ditto.live/js/Ditto/5.2.0/api-reference/).
- **CAP-06**: Native transport configuration exists; browser transport support is restricted to WebSockets. Source: published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts`; [API](https://software.ditto.live/js/Ditto/5.2.0/api-reference/).
- **CAP-13**: Presence graph and request handler are exposed; physical connection policy requires two-peer device testing. Source: published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts`; [API](https://software.ditto.live/js/Ditto/5.2.0/api-reference/).
- **CAP-14**: Partial: local commit IDs and active state exist, but there is no per-query sync-status/remote acknowledgement API in this JS surface. Source: published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts`; [API](https://software.ditto.live/js/Ditto/5.2.0/api-reference/).
- **CAP-15**: Logger callback is available on Node/web and explicitly rejected on RN; native logs are the workaround. Source: published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts`; [API](https://software.ditto.live/js/Ditto/5.2.0/api-reference/).
- **CAP-20**: Partial: native platform operations exist but Data Streams is not exported in this release; do not borrow Swift/Kotlin syntax. Source: published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts`; [API](https://software.ditto.live/js/Ditto/5.2.0/api-reference/).

## Verification

Node and browser runtime evidence is recorded at exact patch versions in the harness.
Native types/bundles/prebuild do not imply radio verification. Sources are public SDK
distributions and official guides; no internal checkout is required by installed skills.
