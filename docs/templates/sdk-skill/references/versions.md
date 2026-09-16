# Versions and migration — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/migration-guides/<lang>-v4.mdx` and
> `sdk/latest/migration-guides/<lang>-dql.mdx` (both — the API migration and the query
> migration are separate), `sdk/latest/v5-whats-new.mdx`,
> `sdk/latest/release-notes/<lang>.mdx`, `sdk/latest/compatibility/<lang>.mdx`.
>
> This file is the **single source of truth** for version claims in this skill. Any
> inline tag elsewhere must agree with it. See `CONTRIBUTING.md` §2.

## Supported versions

| Ditto SDK | Package version | Verified on | Status |
|---|---|---|---|
| 5.1.x | TODO | TODO exact patch | TODO |
| 5.0.x | TODO | TODO exact patch | TODO |
| 4.14.x | TODO | TODO exact patch | LTS |

## Capability availability matrix

<!--
  One row per capability whose availability or shape differs across version lines.
  Use exact patch versions. A checkmark means "works", not "parses" --
  see CONTRIBUTING.md §2.
-->

| Capability | 4.14.x | 5.0.x | 5.1.x | Failure mode on older versions |
|---|---|---|---|---|
| TODO | TODO | TODO | TODO | TODO exact error string |

## CAP-19 v4 to v5 migration

### Package and namespace

TODO

### Initialization and identity

<!-- v4 identity model -> v5 config model. Show both forms. -->

TODO

### Authentication

TODO

### Sync

TODO

### Query model

<!-- Legacy collection API -> DQL. Link to sdk/latest/migration-guides/<lang>-dql.mdx. -->

TODO

### Observers

TODO

### Removed APIs

<!-- A table of removed symbol -> replacement, or "no replacement". -->

| Removed in v5 | Replacement |
|---|---|
| TODO | TODO |

### New in v5

TODO

### Migration checklist

- [ ] TODO
