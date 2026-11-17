# Versions and migration — TODO_LANGUAGE

> **Slugs are not uniform.** Resolve `<lang>` per directory using the table in
> `docs/SDK-SKILL-TEMPLATE.md` §8.1 — JS, Java, C# and Go do not follow the
> obvious pattern, and Go has no migration guides at all.
>
> **Sources for this file.** `sdk/latest/migration-guides/<lang>-v4.mdx` and
> `<lang>-dql.mdx` (both — API migration and query migration are separate).
> **Go has neither**: it is Preview with no v4, so CAP-19 is `Support: no` for `go-sdk`.
> Also `snippets/common-release-notes/`, which carries per-version per-language
> changelog snippets the release-notes pages import.
>
> This file also owns **package coordinates per version line** — `setup.md` shows only
> the v5 form and links here. One fact, one home. Other sources: `sdk/latest/v5-whats-new.mdx`,
> `sdk/latest/release-notes/<lang>.mdx`, `sdk/latest/compatibility/<lang>.mdx`.
>
> This file is the **single source of truth** for version claims in this skill. Any
> inline tag elsewhere must agree with it. See `CONTRIBUTING.md` §2.

## Supported versions

| Ditto SDK | Package version | Verified on | Status |
|---|---|---|---|
| 5.2.0 | TODO | TODO exact patch | Latest known baseline; resolve latest for new apps |
| 5.1.x | TODO | TODO exact patch | TODO |
| 5.0.x | TODO | TODO exact patch | TODO |
| 4.14.x | TODO | TODO exact patch | LTS |

## Capability availability matrix

<!--
  One row per capability whose availability or shape differs across version lines.
  Use exact patch versions. A checkmark means "works", not "parses" --
  see CONTRIBUTING.md §2.
-->

| Capability | 4.14.x | 5.0.x | 5.1.x / 5.2.0 | Failure mode on older versions |
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

### On-disk store migration

<!--
  REQUIRED, and not covered by the migration guides' API focus. For a shipped app
  upgrading 4.14.x -> 5.x in place, over an EXISTING persistence directory:
  - Is the on-disk store format migrated automatically on first open?
  - Is it one-way? Can a user roll back to the v4 build afterwards?
  - How long does it take with a large local store, and does it block?
  - What happens on failure or on interruption mid-migration?
  - Is there a supported wipe-and-resync path, and what does it cost the user?
  This is the highest-risk production question in a fleet upgrade. If you cannot
  verify it, say so explicitly rather than leaving it blank.
-->

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
