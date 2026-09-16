# SDK Skill Template

The normative structure for a **per-language Ditto SDK skill** — `skills/swift-sdk/`,
`skills/kotlin-sdk/`, `skills/js-sdk/`, and so on.

This is a **specialization** of [`SKILLS-TEMPLATE.md`](SKILLS-TEMPLATE.md), not a
replacement for it. `SKILLS-TEMPLATE.md` defines what *any* skill in this repo looks
like. This file defines the additional structure an *SDK-language* skill must have so
that all nine language skills are structurally identical and can be diffed against one
another section by section.

Authoring workflow, PR requirements, version-tagging rules and the evidence hierarchy
live in [`../CONTRIBUTING.md`](../CONTRIBUTING.md) and are **not** repeated here. This
file only adds what is specific to SDK skills.

A fillable skeleton lives at [`templates/sdk-skill/`](templates/sdk-skill). Copy it;
do not hand-roll the tree.

**Status:** normative. Every skill authored under SDKS-3603, SDKS-3604, SDKS-3605,
SDKS-3606, SDKS-3607 and SDKS-3608 must conform, and a reviewer should reject a PR
that does not.

---

## Contents

1. [Why SDK skills are split from concept skills](#1-why-sdk-skills-are-split-from-concept-skills)
2. [Naming, packaging and scope](#2-naming-packaging-and-scope)
3. [Directory layout](#3-directory-layout)
4. [Frontmatter](#4-frontmatter)
5. [Required SKILL.md sections](#5-required-skillmd-sections)
6. [The capability contract](#6-the-capability-contract)
7. [Capability status vocabulary](#7-capability-status-vocabulary)
8. [Where to source each capability](#8-where-to-source-each-capability)
9. [Code sample rules](#9-code-sample-rules)
10. [Version coverage](#10-version-coverage)
11. [Token budget](#11-token-budget)
12. [Tests](#12-tests)
13. [Authoring workflow](#13-authoring-workflow)
14. [Reviewer checklist](#14-reviewer-checklist)
15. [Appendix A — the nine SDKs](#appendix-a--the-nine-sdks)
16. [Appendix B — known documentation gaps](#appendix-b--known-documentation-gaps)

---

## 1. Why SDK skills are split from concept skills

This repo already has **concept skills** that explain how Ditto works, once,
language-agnostically:

| Concept skill | Owns |
|---|---|
| `dql` | DQL grammar, statements, operators, functions, indexing semantics |
| `data-modeling` | CRDT type selection, embed-vs-split, document size budgets |
| `sync-subscriptions` | What a subscription is, query limitations, mesh propagation |
| `ditto-mesh-networking` | Transports, mesh formation, platform requirements |

An **SDK skill owns exactly one thing: how to express those concepts in one language.**
API shape, idiom, object lifetimes, threading model, retention rules, error types,
build configuration, and the failure modes specific to that language.

### The routing contract

An SDK skill **must not**:

- re-teach DQL grammar — link to the `dql` skill,
- re-teach CRDT semantics or modeling trade-offs — link to `data-modeling`,
- re-explain what a subscription is or how flooding works — link to `sync-subscriptions`,
- re-explain transport selection strategy or mesh formation — link to
  `ditto-mesh-networking`.

An SDK skill **must**:

- show the exact call that runs a DQL statement in this language, with argument binding,
- show how a result is iterated and deserialized into this language's types,
- state what must be retained, and for how long, to keep a subscription or observer alive,
- state which thread or executor callbacks arrive on,
- name the exact error type raised and how it is caught.

Duplicating concept material is a defect, not redundancy: the copy drifts, and
`CONTRIBUTING.md` §4 forbids citing one file in this repo as the source for another.

---

## 2. Naming, packaging and scope

- Directory: `skills/<lang>-sdk/` — lowercase, hyphenated, matching the frontmatter
  `name`. Unprefixed, consistent with the existing `dql`, `data-modeling` and
  `sync-subscriptions` skills. Use the short language name, not the package name:
  `swift-sdk`, `kotlin-sdk`, `js-sdk`, `csharp-sdk`, `flutter-sdk`, `rust-sdk`,
  `cpp-sdk`, `java-sdk`, `go-sdk`.
- **One plugin per language skill**, per the scoping rule in
  [`../AGENTS.md`](../AGENTS.md): `plugins/ditto-<lang>/` with a real `skills/`
  directory holding a single symlink. A developer writing Swift must not be forced to
  load the Kotlin skill.
- One skill covers one **SDK package**, not one platform. `js-sdk` covers
  `@dittolive/ditto` across Web, Node.js and React Native, with per-runtime differences
  called out inside the relevant capability. Do not create `react-native-sdk`.

---

## 3. Directory layout

```
skills/<lang>-sdk/
├── SKILL.md                     # Required. Frontmatter + lean routing body
├── README.md                    # Human-facing: scope, versions verified, status
├── best-practices.md            # Idiom, retention, threading, performance
├── references/                  # One file per capability group, one level deep
│   ├── setup.md                 # CAP-01, CAP-02
│   ├── connect.md               # CAP-03, CAP-04, CAP-05
│   ├── transports.md            # CAP-06
│   ├── sync.md                  # CAP-07, CAP-14, CAP-17
│   ├── store.md                 # CAP-08, CAP-09, CAP-10
│   ├── observers.md             # CAP-11
│   ├── attachments.md           # CAP-12
│   ├── presence.md              # CAP-13
│   ├── observability.md         # CAP-15
│   ├── errors.md                # CAP-16
│   ├── testing.md               # CAP-18
│   ├── versions.md              # CAP-19 + the compatibility matrix
│   └── preview.md               # CAP-20. Omit only if the SDK has no preview APIs
└── examples/
    └── minimal-app.md           # Required: one complete, compiling app
```

Every file above is **required** except `references/preview.md`, which is omitted only
when the capability map records CAP-20 as `not-available`.

References stay **one level deep** from `SKILL.md`. Agents frequently only partially
read files reached through a chain of links, so a reference must never be the only path
to another reference.

---

## 4. Frontmatter

Only the keys permitted by `CONTRIBUTING.md` — `name`, `description`, `license`,
`compatibility`, `allowed-tools`, `metadata`. Any other key is a hard error in stricter
loaders.

`description` is the activation mechanism and is the only part of the skill injected
into every session. Use this formula:

```yaml
---
name: <lang>-sdk
description: >
  Use when writing, reviewing or debugging Ditto <Language> SDK code —
  <2-4 literal API names a user would type>, <2-3 literal error strings>.
  Covers <package coordinate> on Ditto SDK 4.14.x, 5.0.x and 5.1.x: connecting,
  authentication, transports, subscriptions, DQL execution, observers, attachments,
  presence, logging and v4 to v5 migration. Use ONLY for <Language>; see the dql skill
  for query syntax and data-modeling for CRDT structure.
---
```

Rules:

- Front-load **literal strings a user would type**: `DittoFactory.create`,
  `ExpirationHandlerMissing`, `registerObserverWithSignalNext`, `@dittolive/ditto`.
  A description made of category nouns never triggers.
- Include the `Use ONLY for <Language>` gate. Nine sibling skills with overlapping
  vocabulary will otherwise all fire at once and crowd out the conversation.
- Third person. Under 1024 characters.

---

## 5. Required SKILL.md sections

Exactly these H2 headings, in exactly this order, with exactly these anchors. A
reviewer diffing two language skills must be able to line them up.

| # | Heading | Contains |
|---|---|---|
| 1 | `## What this skill does` | 2–3 sentences. Language, package, versions. |
| 2 | `## When to use this skill` | The routing contract from §1, including the explicit hand-offs to `dql`, `data-modeling`, `sync-subscriptions` and `ditto-mesh-networking`. |
| 3 | `## Supported versions and packages` | Package coordinate per version line, minimum toolchain and platform, links to the published API reference. Details live in `references/versions.md`. |
| 4 | `## Capability map` | The table from §6, verbatim IDs, one row per capability, each with a status from §7 and a link to the owning reference file. **This is the section that makes the nine skills comparable.** |
| 5 | `## Minimum viable app` | One complete, copy-pasteable program: configure → authenticate → start sync → register a subscription → register an observer → execute a write. Must compile as shown. Nothing elided. |
| 6 | `## Concurrency and threading model` | Which thread or executor callbacks arrive on; what is safe to call from where; what must not block; cancellation and cleanup. The single most common source of language-specific bugs, which is why it is a top-level section and not a reference. |
| 7 | `## Object lifetimes and retention` | What must be held to stay alive — `Ditto`, subscriptions, observers, attachment fetchers — and what happens when it is dropped. Second most common source of bugs. |
| 8 | `## Anti-patterns` | Code that compiles but is wrong. Each entry: the wrong code, the symptom the developer will actually see, the corrected code. |
| 9 | `## Version differences` | The short form of the v4.14.x → 5.x delta. Full table in `references/versions.md`. |
| 10 | `## References` | A table mapping *a question an agent would have* to the file that answers it. Not a directory listing. |

Sections 6 and 7 are promoted out of the reference tree deliberately. They are where
correct-looking code fails at runtime, and an agent that has to follow a link to find
them usually does not.

---

## 6. The capability contract

Twenty capability IDs. **Every language skill must address every ID.** The IDs are
stable and must not be renumbered, renamed or reordered — downstream tooling, reviews
and cross-language comparison depend on them.

The capability map in `SKILL.md` §4 is this table with two columns filled in by the
author: **Status** (from §7) and **Where** (the reference file and anchor).

| ID | Capability | Reference file |
|----|-----------|----------------|
| CAP-01 | Prerequisites, toolchain versions, package install | `setup.md` |
| CAP-02 | Platform permissions, entitlements, manifest and build config | `setup.md` |
| CAP-03 | Connecting: `DittoConfig`, opening an instance, persistence directory | `connect.md` |
| CAP-04 | Authentication and identity: expiration handler, login/logout, providers, offline-only license | `connect.md` |
| CAP-05 | Lifecycle: starting and stopping sync, shutdown, instance ownership | `connect.md` |
| CAP-06 | Customizing transports: peer-to-peer, connect, listen, global; runtime updates; transport conditions | `transports.md` |
| CAP-07 | Sync subscriptions: registering, retaining, closing; sync scopes | `sync.md` |
| CAP-08 | Querying the store: executing DQL, argument binding, result iteration and deserialization | `store.md` |
| CAP-09 | Transactions | `store.md` |
| CAP-10 | Indexing: creating indexes, composite indexes, `EXPLAIN` / `ADVISE` | `store.md` |
| CAP-11 | Observers and live queries: registration, diffing, back-pressure, cancellation | `observers.md` |
| CAP-12 | Attachments: creating, referencing, fetching, fetcher lifetime | `attachments.md` |
| CAP-13 | Presence graph, peer metadata, connection-request authorization | `presence.md` |
| CAP-14 | Sync status: local commit tracking, cloud sync status, per-peer status | `sync.md` |
| CAP-15 | Logging, diagnostics and stats: levels, export, disk usage, small peer info, Ditto Tools | `observability.md` |
| CAP-16 | Error handling: the exception or result taxonomy and how to recover | `errors.md` |
| CAP-17 | Device storage management: eviction strategy and `EVICT` | `sync.md` |
| CAP-18 | Testing: isolation, offline instances, CI | `testing.md` |
| CAP-19 | v4 → v5 migration delta | `versions.md` |
| CAP-20 | Preview and platform-specific APIs | `preview.md` |

### Why these twenty

The list is derived from the Ditto documentation navigation, not invented. The
"Build with the SDK" tab in `mintlify-docs/docs.json` has the same six groups in both
the v4 and v5 versions — Overview & Setup, Accessing Data, Syncing Data, Authentication
and Authorization, Managing the Mesh, Deploying your App. CAP-01 through CAP-20 cover
every page in those groups, plus the API surface enumerated in the public API dump at
`sdks/kotlin/api/ditto-kotlin/api/jvm/ditto-kotlin.api` on `releases/release-5.1.0`.

Capabilities that do not appear in the docs navigation but do appear in the shipped API
surface — disk usage, small peer info, transport conditions, back-pressure — are folded
into CAP-11 and CAP-15 rather than dropped. See [Appendix B](#appendix-b--known-documentation-gaps).

---

## 7. Capability status vocabulary

Every row in the capability map carries exactly one status. **A capability is never
omitted**; parity across the nine SDKs is genuinely incomplete, and an unstated gap is
indistinguishable from an oversight.

| Status | Meaning | Required alongside |
|---|---|---|
| `supported` | Shipped, documented, and the skill shows working code. | A code sample in the reference file. |
| `preview` | Shipped but explicitly preview or unstable. | The opt-in mechanism, the exact version it appeared in, and the stability warning. |
| `partial` | Some of the capability exists in this SDK, some does not. | A sentence naming precisely which part is missing. |
| `not-available` | The SDK does not expose this at all. | The reason, and the nearest workaround if one exists. |
| `undocumented` | The API exists and the skill documents it, but the public docs do not. | The source path and ref the claim was verified against, per `CONTRIBUTING.md` §4 tier 2. |

`undocumented` is a normal, expected status — several capabilities below are real
shipped APIs with no public code sample in any language. Marking one `undocumented`
with a source citation is correct and useful. Silently presenting it as documented is
not.

---

## 8. Where to source each capability

Follow the evidence hierarchy in `CONTRIBUTING.md` §4: executed code beats SDK source,
which beats documentation, which beats inference. Below is the starting point for each
capability, in the order to try them.

Paths under `mintlify-docs/` are relative to the docs checkout; `<lang>` is that SDK's
slug in the docs (`kotlin`, `swift`, `js`, `c-sharp`, `flutter`, `rust`, `cpp`, `java`,
`go`). Paths under `ditto/` are relative to the SDK source checkout.

| ID | Primary sources |
|----|-----------------|
| CAP-01 | `sdk/latest/install-guides/<lang>.mdx`; `sdk/latest/compatibility/<lang>.mdx`; `sdk/v4/install-guides/<lang>.mdx` |
| CAP-02 | `sdk/latest/install-guides/<lang>.mdx` (Android manifest, iOS entitlements, MAUI permissions); `sdk/latest/deployment/network-deployment.mdx`; `sdk/latest/deployment/bluetooth-on-linux.mdx` |
| CAP-03 | `snippets/connect-examples-v5/playground/<lang>-playground.mdx`; `snippets/connect-examples-v5/development/`; `sdk/latest/quickstarts/`; `sdk/latest/install-guides/<lang>.mdx` |
| CAP-04 | `sdk/latest/auth-and-authorization/cloud-authentication.mdx`; `.../data-authorization.mdx`; `.../certificate-based-security.mdx`; the AUTHENTICATION block in `sdk/latest/migration-guides/<lang>-v4.mdx` |
| CAP-05 | `sdk/latest/sync/syncing-data.mdx`; `best-practices/sync-handling` |
| CAP-06 | `sdk/latest/sync/customizing-transport-configurations.mdx`; `sdk/latest/sync/managing-redundant-bluetooth-le-connections.mdx`; `sdk/latest/deployment/wifi-aware-chipset-considerations.mdx`; `sdk/latest/deployment/setting-routing-hints.mdx` |
| CAP-07 | `sdk/latest/sync/syncing-data.mdx`; `sdk/latest/sync/sync-scopes.mdx`; `dql/alter-system.mdx` |
| CAP-08 | `sdk/latest/crud/create.mdx`, `read.mdx`, `update.mdx`, `delete.mdx`; `sdk/latest/crud/working-with-ejson.mdx`; `sdk/latest/migration-guides/<lang>-dql.mdx` |
| CAP-09 | `sdk/latest/crud/transactions.mdx` |
| CAP-10 | `dql/indexing.mdx`; `dql/explain.mdx`; `dql/advise.mdx`; `dql/access-paths.mdx`; `dql/profile.mdx` |
| CAP-11 | `sdk/latest/crud/observing-data-changes.mdx`; `dql/replacing-live-queries.mdx`; the OBSERVERS and BACK-PRESSURE blocks in `sdk/latest/migration-guides/<lang>-v4.mdx` |
| CAP-12 | `sdk/latest/crud/working-with-attachments.mdx` |
| CAP-13 | `sdk/latest/sync/using-mesh-presence.mdx`; `sdk/latest/sync/handling-connection-requests.mdx` |
| CAP-14 | `sdk/latest/sync/monitoring-sync-status.mdx`; `sdk/latest/sync/tracking-local-commits.mdx`; `sdk/latest/sync/cloud-sync-status.mdx` |
| CAP-15 | `sdk/latest/deployment/logging.mdx`; `.../device-observability-and-ditto-logs.mdx`; `.../getting-system-information.mdx`; `.../integrate-ditto-tools-for-kotlin-swift-and-c-net-in-15-minutes.mdx`; the LOGGING and DISK USAGE blocks in `sdk/latest/migration-guides/<lang>-v4.mdx` |
| CAP-16 | The ERROR HANDLING block and "Exception Hierarchy Changes" in `sdk/latest/migration-guides/<lang>-v4.mdx`; `sdk/latest/deployment/troubleshooting.mdx`; the SDK's published API reference |
| CAP-17 | `sdk/latest/sync/device-storage-management.mdx`; `dql/evict.mdx` |
| CAP-18 | `sdk/latest/deployment/testing.mdx` |
| CAP-19 | `sdk/latest/migration-guides/<lang>-v4.mdx` **and** `sdk/latest/migration-guides/<lang>-dql.mdx`; `sdk/latest/v5-whats-new.mdx`; `sdk/latest/release-notes/<lang>.mdx` |
| CAP-20 | `sdk/latest/sync/data-streams.mdx`; `sdk/latest/deployment/vsc-es.mdx`; `sdk/v4/ditto-config.mdx`; that SDK's release notes |

### When the docs do not answer it

Fall back in this order, and record which tier you actually used in the skill's
`README.md`:

1. **Run it.** A one-file program against the real SDK at a named patch version.
   Tier 1 — the strongest evidence available and always worth the time for CAP-03,
   CAP-08 and CAP-11.
2. **Read the public API surface.** The binary-compatibility dumps are the
   authoritative enumeration of what actually shipped — for Kotlin and Java,
   `ditto/sdks/kotlin/api/*/api/**/*.api` at a named ref. For other languages, the
   published API reference listed in Appendix A.
3. **Read the SDK source.** `ditto/sdks/<lang>/` at a named ref. Cite path and ref.
4. **Infer, and label it as inference.**

The docs' per-language migration guides each contain an "AI Agent Prompt" block that
already enumerates the v4 → v5 delta capability by capability. It is the single densest
source for CAP-19 and for the anti-patterns in `SKILL.md` §8 — it names the exact
constructs that fail to compile and the exact errors they produce.

---

## 9. Code sample rules

1. **One language per fence, tagged.** ` ```kotlin `, ` ```swift `, ` ```csharp `,
   ` ```dart `, ` ```rust `, ` ```typescript `, ` ```cpp `, ` ```java `, ` ```go `.
   DQL goes in a ` ```sql ` fence so the DQL harness can find it.
2. **Compiling, not illustrative.** Include imports and the enclosing
   function/suspend/async context. A snippet that assumes an ambient `ditto` teaches an
   agent to emit code that does not build. `SKILL.md` §5 in particular must be complete.
3. **Show the failure, not just the fix.** Every anti-pattern needs the symptom a
   developer will actually see — the compiler error, the exception name, or the wrong
   runtime behaviour. "Do not do this" without the symptom is unactionable.
4. **Real identifiers.** Use the actual API names at the version you are documenting.
   Never paraphrase a method name.
5. **No pseudo-code, ever.** If you cannot write the real call, mark the capability
   `undocumented` or `not-available` and say so.
6. **Placeholders are uppercase and obvious**: `REPLACE_ME_WITH_YOUR_DATABASE_ID`,
   matching the docs' own convention. Never commit a real token, database ID or URL.

---

## 10. Version coverage

Every SDK skill documents **4.14.x (LTS), 5.0.x and 5.1.x**, matching the `dql` skill.

Follow `CONTRIBUTING.md` §2 in full — name exact patch versions, tag every version-gated
claim inline *and* in `references/versions.md`, include the failure mode on older
versions, and never mark something available when it parses but misbehaves.

Two rules specific to SDK skills:

- **v4 and v5 are different APIs, not different versions of one API.** The package
  coordinate, namespace, initialization model and query model all changed. Do not write
  a single sample with inline "in v4 this was…" asides. Show the v5 form in the body and
  keep the v4 form in `references/versions.md`.
- **The default is v5.** An agent that cannot determine the user's version should emit
  v5 and say which version it assumed. Say this explicitly in `SKILL.md` §3 so the
  behaviour is consistent across all nine skills.

---

## 11. Token budget

The name and description are injected into **every** session, and nine SDK skills will
eventually coexist. Budget accordingly:

| File | Target | Hard limit |
|---|---|---|
| `description` | 2–3 sentences | 1024 characters |
| `SKILL.md` body | ≤ 350 lines | 500 lines |
| Each `references/*.md` | ≤ 400 lines | — |
| `examples/minimal-app.md` | one program | — |

If `SKILL.md` exceeds the limit, move depth into the reference file that owns the
capability. Do not delete the capability row — the map must stay complete.

---

## 12. Tests

SDK skills document executable code, so they need verification, and
`CONTRIBUTING.md` §3 requires an honest statement of what was run.

- **DQL inside an SDK skill is not covered today.** The `tests/dql` harness extracts
  ` ```sql ` blocks, but `tests/dql/scripts/extract-queries.mjs` hard-codes its scan
  root to `skills/dql` — nothing outside that directory is picked up. Still tag DQL as
  ` ```sql `, so that extending the harness to a second root is a one-line change, but
  do not assume your DQL is verified because you tagged it.
- **Host-language samples** are the author's responsibility. The minimum bar for a
  skill to be considered done is that `examples/minimal-app.md` has been **compiled and
  run** against each supported version line, with the result recorded in the skill's
  `README.md`.
- A per-language harness under `tests/<lang>-sdk/` is encouraged but not required by
  this template. If you add one, follow `tests/dql/README.md` as the reference
  implementation and extend CI.
- State in `README.md` exactly which versions you executed against, and which claims
  you did not verify. An undeclared gap is the failure mode `CONTRIBUTING.md` §3 exists
  to prevent.

---

## 13. Authoring workflow

1. Branch from `main`, named for the Linear issue.
2. Copy the skeleton:
   ```bash
   cp -R docs/templates/sdk-skill skills/<lang>-sdk
   ```
3. Fill the frontmatter using the formula in §4.
4. Work the capability map top to bottom. For each ID: read the sources in §8, decide
   the status, write the reference section, and record the citation. Do not skip ahead
   to the interesting capabilities — an unfilled row is what a reviewer looks for first.
5. Write `examples/minimal-app.md`, then **compile and run it** on each supported
   version line.
6. Fill `references/versions.md` from the language's `-v4.mdx` and `-dql.mdx` migration
   guides.
7. Write `SKILL.md` §6, §7 and §8 last — by then you know where the real failure modes
   are.
8. Wire up packaging per `CONTRIBUTING.md` → "Adding a new skill": the plugin wrapper,
   the marketplace entry, and the README skills table.
9. Run the validations:
   ```bash
   python3 -m json.tool .claude-plugin/marketplace.json
   ```
   and confirm CI's plugin-scoping job passes locally by checking the wrapper contains
   exactly one symlink.
10. Open the PR and fill in every section of the template, including what you did not
    verify.

---

## 14. Reviewer checklist

Structural — a PR failing any of these should be sent back before the content is read:

- [ ] Directory is `skills/<lang>-sdk/`; frontmatter `name` matches it.
- [ ] Frontmatter contains only permitted keys; description front-loads literal API
      names and carries the `Use ONLY for <Language>` gate.
- [ ] All ten `SKILL.md` H2 sections are present, in order, with the specified anchors.
- [ ] The capability map has all twenty rows, CAP-01 to CAP-20, no row omitted.
- [ ] Every row has a status from §7 and a working link to the reference that owns it.
- [ ] Every `not-available`, `partial`, `preview` or `undocumented` row carries the
      extra information §7 requires for that status.
- [ ] All required files in §3 exist; `references/` is one level deep.
- [ ] A plugin wrapper and marketplace entry exist; the wrapper symlinks exactly one skill.

Content:

- [ ] `SKILL.md` §5 is a complete program, with imports, that compiles as written.
- [ ] No concept material duplicated from `dql`, `data-modeling`, `sync-subscriptions`
      or `ditto-mesh-networking` — those are linked, not restated.
- [ ] §6 names the actual thread or executor; §7 names what must be retained.
- [ ] Every anti-pattern in §8 includes the symptom, not just the correction.
- [ ] Version claims are tagged inline and in `references/versions.md`, and they agree.
- [ ] Citations name real paths at named refs; no file in this repo is cited as a source.
- [ ] `README.md` states which versions were executed against and what was not verified.

---

## Appendix A — the nine SDKs

Package coordinates and doc slugs, from `mintlify-docs/sdk/latest/install-guides/`
and `sdk/latest/api-reference/api-reference.mdx` (v5.1.0 links).

| Skill | Docs slug | Package / distribution | Notes |
|---|---|---|---|
| `swift-sdk` | `swift` | SPM: `https://github.com/getditto/DittoSwiftPackage` | v5 no longer re-exports `Foundation` |
| `kotlin-sdk` | `kotlin` | Gradle: `com.ditto:ditto-kotlin` | KMP root module; Gradle resolves the Android variant. `minSdk` 24, JDK 17 |
| `java-sdk` | `java` | Gradle: `com.ditto:ditto-java` + `com.ditto:ditto-binaries-<platform>` | Server-side only in v5; v4 also had an Android target |
| `js-sdk` | `js` | npm: `@dittolive/ditto` | One package covering Web, Node.js and React Native. Web requires `init()` |
| `csharp-sdk` | `c-sharp` | NuGet: `dotnet add package Ditto` | MAUI has its own permissions helper |
| `cpp-sdk` | `cpp` | Tarball: `ditto.h` + `ditto.a` | No package manager; no `-dql` migration parity assumptions |
| `rust-sdk` | `rust` | crates.io: `dittolive-ditto` | `DatabaseId` replaced `AppId` in v5 |
| `flutter-sdk` | `flutter` | pub.dev: `ditto_live` | Requires `Ditto.init()` before `Ditto.open()` |
| `go-sdk` | `go` | `github.com/getditto/ditto-go-sdk/v5` | **Preview.** CAP-20 must record its preview status |

The docs navigation lists React Native, JavaScript Web and JavaScript Node.js as three
separate entries. They are one npm package and therefore one skill; runtime differences
belong inside CAP-01 and CAP-02 of `js-sdk`.

---

## Appendix B — known documentation gaps

Verified by scanning code-fence languages across `mintlify-docs/sdk/latest/`. These are
the places where an author will find no sample to work from, and must escalate to the
API reference, the SDK source, or a program they run themselves. Each is a likely
`undocumented` or `partial` row.

| Capability | Gap |
|---|---|
| CAP-15 (logging) | `sdk/latest/deployment/logging.mdx` contains **no code samples in any language** — it documents rotation policy only. The logger API must be sourced from the API reference or SDK source. |
| CAP-15 (disk usage) | Disk usage has no standalone doc page. It appears only inside the "Disk Usage" sections of the per-language v4 → v5 migration guides. |
| CAP-15 (system info) | `sdk/latest/deployment/getting-system-information.mdx` has only JSON and SQL fences — no host-language calls. |
| CAP-17 | `sdk/latest/sync/device-storage-management.mdx` has samples for Java and JavaScript only. |
| CAP-20 | `sdk/latest/sync/data-streams.mdx` is Kotlin-only, requires 5.1.0, and is opt-in behind a preview annotation. Every other SDK records CAP-20 as `not-available` for Data Streams unless its own release notes say otherwise. |
| CAP-11 | Back-pressure (`signalNext`) is referenced in all nine `-v4.mdx` migration guides but has no standalone page. |
| CAP-06 | Transport conditions appear in `customizing-transport-configurations.mdx` and the Kotlin migration guide; other languages need source verification. |

Re-verify these before citing them. They were true on the docs checkout at the time this
template was written and the docs are actively maintained — a gap that has since been
filled should be sourced from the docs, not from here.
