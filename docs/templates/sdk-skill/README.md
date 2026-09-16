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

## Capability coverage

<!--
  Copy the status column from SKILL.md's capability map. This is what a reviewer and a
  future maintainer read first. Every non-`supported` row needs one line of reason.
-->

| Status | Capabilities |
|---|---|
| `supported` | TODO |
| `preview` | TODO |
| `partial` | TODO |
| `not-available` | TODO |
| `undocumented` | TODO |

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
