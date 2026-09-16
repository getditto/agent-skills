# Ditto TODO_LANGUAGE SDK Skill

<!--
  Human-facing docs for this skill. Not loaded by agents.
  Delete every TODO and every HTML comment before opening a PR.

  The ../../ links below are relative to skills/<lang>-sdk/ and resolve once this
  directory has been copied there. They are intentionally broken in the template
  location -- do not "fix" them.
-->

Agent skill for writing and reviewing Ditto **TODO_LANGUAGE** SDK code.

## Scope

Covers `TODO_PACKAGE_COORDINATE` — connecting, authentication, transports,
subscriptions, DQL execution, observers, attachments, presence, observability, error
handling, testing, and v4 → v5 migration. Structured against the twenty capability IDs
defined in [`docs/SDK-SKILL-TEMPLATE.md`](../../docs/SDK-SKILL-TEMPLATE.md).

Deliberately **out of scope** — these have their own skills:

- DQL syntax and semantics → `dql`
- CRDT type selection and document structure → `data-modeling`
- Subscription semantics and mesh propagation → `sync-subscriptions`
- Transport strategy and mesh formation → `ditto-mesh-networking`

## Supported versions

| Ditto SDK | Package version | Status |
|---|---|---|
| 5.1.x | TODO | TODO |
| 5.0.x | TODO | TODO |
| 4.14.x | TODO | LTS |

## Capability map

<!--
  THE canonical capability map. SKILL.md carries only the non-`yes` rows.
  Capability titles are VERBATIM from docs/SDK-SKILL-TEMPLATE.md §6 -- do not reword
  them; cross-skill diffing and the CI anchor check depend on exact match.

  Support:  yes | partial | preview | no          (what the SDK ships)
  Evidence: executed | docs-sample | api-dump | source | inference
  Targets:  declare this SDK's vocabulary on the line below and use it in every row.

  Every non-`yes` Support and every api-dump/source/inference Evidence needs the extra
  information required by spec §7 -- put it in the reference file and note it here.
-->

**Targets vocabulary for this SDK:** TODO (e.g. Kotlin `android | jvm | both`;
JS `web | node | rn | all`; single-target SDKs use `all`).

| ID | Capability | Support | Evidence | Targets |
|----|-----------|---------|----------|---------|
| CAP-01 | Prerequisites, toolchain, package install | TODO | TODO | TODO |
| CAP-02 | Platform permissions, entitlements, build config | TODO | TODO | TODO |
| CAP-03 | Connecting: config, opening, persistence directory | TODO | TODO | TODO |
| CAP-04 | Authentication and identity | TODO | TODO | TODO |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | TODO | TODO | TODO |
| CAP-06 | Customizing transports | TODO | TODO | TODO |
| CAP-07 | Sync subscriptions and sync scopes | TODO | TODO | TODO |
| CAP-08 | Querying the store: executing DQL | TODO | TODO | TODO |
| CAP-09 | Transactions | TODO | TODO | TODO |
| CAP-10 | Indexing | TODO | TODO | TODO |
| CAP-11 | Observers, diffing and back-pressure | TODO | TODO | TODO |
| CAP-12 | Attachments | TODO | TODO | TODO |
| CAP-13 | Presence graph and connection requests | TODO | TODO | TODO |
| CAP-14 | Sync status and local commit tracking | TODO | TODO | TODO |
| CAP-15 | Logging, diagnostics and stats | TODO | TODO | TODO |
| CAP-16 | Error handling | TODO | TODO | TODO |
| CAP-17 | Device storage management and eviction | TODO | TODO | TODO |
| CAP-18 | Testing | TODO | TODO | TODO |
| CAP-19 | v4 to v5 migration, API and on-disk store | TODO | TODO | TODO |
| CAP-20 | Preview and platform-specific APIs | TODO | TODO | TODO |

## Verification

<!--
  Required. CONTRIBUTING.md §3 -- pick the honest option and be specific.
  An undeclared gap is the failure mode this section exists to prevent.
-->

**Executed against:** TODO — exact patch versions, and what was run.

**Verified from source:** TODO — repo paths at a named ref, for anything the docs do
not cover.

**Not verified:** TODO — state it plainly. This list being non-empty is normal.

**Last verified:** TODO — YYYY-MM-DD.

## Installation

```bash
# Claude Code
/plugin marketplace add getditto/agent-skills
/plugin install ditto-TODO_LANG@ditto-plugins
```

For other agent tools, see the repository [README](../../README.md).

## Maintenance

When the SDK ships a new minor version:

1. Re-read `sdk/latest/release-notes/<lang>.mdx` for API changes.
2. Update `references/versions.md` first — it is the source of truth for version claims.
3. Re-run `examples/minimal-app.md` against the new version and update **Verification**.
4. Re-check the capability map: a `not-available` row may have become `supported`.
