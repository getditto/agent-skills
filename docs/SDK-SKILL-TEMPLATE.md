# SDK Skill Template

The normative structure for a **per-language Ditto SDK skill** — `skills/swift-sdk/`,
`skills/kotlin-sdk/`, `skills/js-sdk/`, and so on.

**Scope.** This spec governs `skills/<lang>-sdk/` only. The concept skills (`dql`,
`data-modeling`, `sync-subscriptions`, `ditto-mesh-networking`) follow
[`SKILLS-TEMPLATE.md`](SKILLS-TEMPLATE.md) and are **not** retrofitted to this one. The
capability contract below exists to make nine near-identical skills diffable against
each other; that problem does not apply to the concept skills. Where a number here
differs from `SKILLS-TEMPLATE.md` (description length, body length, which files are
required), **this document wins for SDK skills**.

Authoring workflow, PR requirements, version-tagging rules and the evidence hierarchy
live in [`../CONTRIBUTING.md`](../CONTRIBUTING.md) and are **not** repeated here.

A fillable skeleton lives at [`templates/sdk-skill/`](templates/sdk-skill). Copy it;
do not hand-roll the tree.

**Status:** normative. Every per-language SDK skill must conform, and a reviewer should
reject a PR that does not.

> **Internal paths.** §8 and the appendices cite `mintlify-docs/` and `ditto/`, which
> are Ditto-internal checkouts. External contributors should substitute the published
> documentation at <https://docs.ditto.com> and the public API references in
> [Appendix A](#appendix-a--the-nine-sdks). Path structure is the same.

---

## Contents

1. [Why SDK skills are split from concept skills](#1-why-sdk-skills-are-split-from-concept-skills)
2. [Naming, packaging and scope](#2-naming-packaging-and-scope)
3. [Directory layout](#3-directory-layout)
4. [Frontmatter](#4-frontmatter)
5. [Required SKILL.md sections](#5-required-skillmd-sections)
6. [The capability contract](#6-the-capability-contract)
7. [Support and Evidence](#7-support-and-evidence)
8. [Where to source each capability](#8-where-to-source-each-capability)
9. [Code sample rules](#9-code-sample-rules)
10. [Version coverage](#10-version-coverage)
11. [Token budget](#11-token-budget)
12. [Tests and structural CI](#12-tests-and-structural-ci)
13. [Authoring workflow](#13-authoring-workflow)
14. [Reviewer checklist](#14-reviewer-checklist)
15. [Appendix A — the nine SDKs](#appendix-a--the-nine-sdks)
16. [Appendix B — measured documentation gaps](#appendix-b--measured-documentation-gaps)

---

## 1. Why SDK skills are split from concept skills

This repo already has **concept skills** that explain how Ditto works, once,
language-agnostically:

| Concept skill | Owns |
|---|---|
| `dql` (frontmatter `name: write-dql`) | DQL grammar, statements, operators, functions, indexing semantics |
| `data-modeling` | CRDT type selection, embed-vs-split, document size budgets |
| `sync-subscriptions` | What a subscription is, query limitations, mesh propagation |
| `ditto-mesh-networking` | Transport selection strategy, mesh formation, platform capability matrix |

An **SDK skill owns exactly one thing: how to express those concepts in one language.**
API shape, idiom, object lifetimes, threading model, retention rules, error types,
build configuration, and the failure modes specific to that language.

### Ownership of contested topics

Prose rules do not partition. This table does. It is normative, and it exists because
the first review of this template found `ditto-mesh-networking` already owns material
that CAP-02 and CAP-06 appear to ask an SDK author to write.

| Topic | Owner | The other may |
|---|---|---|
| Manifest / entitlement / plist **declarations**, and the symptom of omitting one | **SDK skill** (build configuration) | mesh: keeps its cross-platform matrix; SDK links to it for *why* |
| *Why* a radio needs a given permission; per-platform capability matrix | **`ditto-mesh-networking`** | SDK: link only |
| Transport config **field names, types, builder shape** in this language | **SDK skill** | mesh: describes the config model generically |
| Transport **selection strategy**, defaults, cost of a runtime change | **`ditto-mesh-networking`** | SDK: link only |
| Transport-condition **enum values** (incl. cross-language renames) | **`ditto-mesh-networking`** | SDK: names its own type and observation API, links the values |
| A DQL statement **embedded in a host-language sample** | **SDK skill** | — |
| That statement's **grammar or semantics** | **`dql`** | SDK: link only |
| A host-language construct that produces **wrong CRDT behaviour** | **SDK skill** — state the observable outcome | `data-modeling`: owns *why* the merge behaves that way |

`skills/ditto-mesh-networking/references/platform-requirements.md` §2–§3 already contain
the iOS and Android permission tables with symptoms. Under the table above an SDK skill
still writes its own declarations block — that is build configuration — but must not
restate the capability matrix around it.

### The worked boundary

Two adjacent sentences, one each side of the line, for CAP-08:

> **Yours:** `ditto.store.execute(query, arguments)` returns `DittoQueryResult`; items
> deserialize via `item.value` into `Map<String, Any?>`, and numbers arrive as `Double`.
>
> **`dql`'s:** why `UPDATE ... APPLY counter INCREMENT BY 1` merges where
> `SET counter = 1` overwrites.

Embedding the DQL statement in your sample is not a restatement. Explaining what the
statement *means* is.

### When the concept skill is not installed

Each SDK skill ships as its own plugin (§2), so a user with `ditto-kotlin` installed may
have **no `dql` skill at all**. That is the default case, not an edge case. Every
hand-off must therefore name a public documentation URL alongside the skill name, the
way `ditto-mesh-networking` already does:

> For DQL syntax see the `dql` skill if installed, otherwise
> <https://docs.ditto.com/dql/dql>.

---

## 2. Naming, packaging and scope

- Directory: `skills/<lang>-sdk/` — lowercase, hyphenated, matching the frontmatter
  `name`. Use the short language name, not the package name: `swift-sdk`, `kotlin-sdk`,
  `js-sdk`, `csharp-sdk`, `flutter-sdk`, `rust-sdk`, `cpp-sdk`, `java-sdk`, `go-sdk`.
- **The frontmatter `name` must equal the directory name.** This is not currently true
  everywhere in the repo — `skills/dql/SKILL.md` ships `name: write-dql` — and CI does
  not catch it. §12 requires that check to be added.
- **One plugin per language skill**, per the scoping rule in
  [`../AGENTS.md`](../AGENTS.md): `plugins/ditto-<lang>/` with a real `skills/`
  directory holding a single symlink. A developer writing Swift must not be forced to
  load the Kotlin skill.
- One skill covers one **SDK package**, not one platform. `js-sdk` covers
  `@dittolive/ditto` across Web, Node.js and React Native. Do not create
  `react-native-sdk`. Per-runtime variance goes in the `Targets` column (§6), not in a
  separate skill.

---

## 3. Directory layout

```
skills/<lang>-sdk/
├── SKILL.md                     # Required. Frontmatter + lean routing body
├── README.md                    # Human-facing: scope, versions, FULL capability map
├── best-practices.md            # Architectural judgement
├── references/                  # One file per capability group, one level deep
│   ├── setup.md                 # CAP-01, CAP-02
│   ├── connect.md               # CAP-03, CAP-04, CAP-05
│   ├── transports.md            # CAP-06
│   ├── sync.md                  # CAP-07, CAP-14
│   ├── store.md                 # CAP-08, CAP-09, CAP-10, CAP-17
│   ├── observers.md             # CAP-11
│   ├── attachments.md           # CAP-12
│   ├── presence.md              # CAP-13
│   ├── observability.md         # CAP-15
│   ├── errors.md                # CAP-16
│   ├── testing.md               # CAP-18
│   ├── versions.md              # CAP-19 + the compatibility matrix
│   └── preview.md               # CAP-20
└── examples/
    └── minimal-app.md           # Required. THE normative program for this skill
```

`CAP-17` (device storage / `EVICT`) lives in `store.md`, not `sync.md`: it is a DQL
statement issued through the same execute call as CAP-08.

**The mapping above is a minimum, not a cap.** A reference may be split when it exceeds
400 lines, and extra `references/` and `examples/` files are permitted, provided every
capability-map link still resolves and `references/` stays one level deep. A reference
whose capabilities all have `Support: no` may be omitted, with the reason carried in the
capability map row.

References stay **one level deep** from `SKILL.md`. A reference must never be the only
path to another reference — agents frequently only partially read chained links.

---

## 4. Frontmatter

Only the keys permitted by `CONTRIBUTING.md` — `name`, `description`, `license`,
`compatibility`, `allowed-tools`, `metadata`.

**`allowed-tools`:** set it to `Read, Grep, Glob, Edit, Write`, matching `skills/dql` and
`skills/data-modeling`. It is in the skeleton; do not silently drop it.

`description` is the activation mechanism and the only part of the skill injected into
every session. Nine sibling skills will compete, so:

```yaml
---
name: <lang>-sdk
description: >
  Use ONLY for the Ditto <Language> SDK (not <the other eight> — each has its own
  skill). Triggers on <file extensions>, <build file names>, <package coordinate>,
  <2-4 literal API names>, <2-3 literal error strings you actually observed>.
  Ditto SDK 4.14.x, 5.0.x, 5.1.x.
---
```

Rules:

- **Front-load what the agent can observe in the repository** — file extensions
  (`.kt`, `build.gradle.kts`), the package coordinate (`com.ditto:ditto-kotlin`) —
  before API names. A user asking "how do I register an observer in Ditto?" names no
  language; the only disambiguator is the project on disk.
- **Lead with the exclusion gate**, mirroring `ditto-mesh-networking`, whose description
  opens `Use ONLY for Ditto's peer-to-peer mesh (not Zigbee, Thread, BLE Mesh, …)`.
  A trailing gate does not fire.
- **Do not repeat the long capability list** ("connecting, authentication, transports,
  subscriptions, …") in all nine descriptions. Nine copies is pure context crowding.
- Where the slug cannot express the language, the description must: `csharp-sdk` has to
  front-load `C#`, `.NET`, `MAUI`; `cpp-sdk` has to front-load `C++`.
- Third person. Under 1024 characters; aim for 400.

---

## 5. Required SKILL.md sections

Exactly these H2 headings, in exactly this order, spelled exactly this way. Anchors are
derived from the headings by the usual GitHub slug rules; do not hand-write anchors.

| # | Heading | Contains |
|---|---|---|
| 1 | `## What this skill does` | 2–3 sentences. Language, package, versions. A lead paragraph under the H1, before this section, is permitted and encouraged — both mature skills in this repo have one. |
| 2 | `## When to use this skill` | The routing contract and ownership table hand-offs from §1, each naming a public docs URL as fallback. |
| 3 | `## Supported versions and packages` | Pointer, not a claim: name the package and link `references/versions.md`, which owns every cross-version fact. |
| 4 | `## Capability exceptions` | **Only** the capability rows whose `Support` is not `yes`. The full twenty-row map lives in `README.md`. An agent's behaviour should change on the exceptions; the complete grid is a reviewer artifact. If there are no exceptions, say so in one line. |
| 5 | `## Minimum viable app` | The **shortest form that actually runs**: open → subscribe → observe → write, around 25 lines. The complete program is `examples/minimal-app.md`, which is normative; this is the excerpt. Link it. |
| 6 | `## Concurrency and threading model` | Which thread or executor callbacks arrive on, per API — if `registerObserver` and the reactive form differ, document both. What is safe to call from where; what must not block; cancellation. |
| 7 | `## Object lifetimes and retention` | What must be held to stay alive — instance, subscriptions, observers, attachment fetchers — and the observable symptom when it is dropped. |
| 8 | `## Anti-patterns` | See the boundary rule below. |
| 9 | `## Version differences` | Short form of the 4.14.x → 5.x delta. Full table in `references/versions.md`. |
| 10 | `## References` | A table mapping *a question an agent would have* to the file that answers it. |

Sections 6 and 7 are promoted out of the reference tree deliberately. They are where
correct-looking code fails at runtime, and an agent that has to follow a link to find
them usually does not.

### §8 Anti-patterns vs best-practices.md

The boundary is **load order**, not "wrong vs slow". `SKILL.md` is loaded whenever the
skill triggers; `best-practices.md` is loaded only if the agent follows a link.

> **`SKILL.md` §8** holds anything that changes the code an agent emits **by default** —
> including performance footguns — provided it has a nameable symptom: a compiler error,
> an exception name, a profiler symbol, or a measured factor.
>
> **`best-practices.md`** holds architectural judgement with no single right answer:
> where the instance lives, one broad observer vs many narrow, when a transaction earns
> its cost.

A hot-path serialization cost with a named symbol belongs in §8, not in
`best-practices.md`. If you cannot name the symptom, you have not finished
investigating it.

---

## 6. The capability contract

Twenty capability IDs. **Every language skill must address every ID.** The IDs and the
capability titles below are **verbatim strings** — do not renumber, rename, reorder or
reword them. Cross-skill diffing and the CI anchor check depend on exact match.

The full map lives in `README.md` with four columns: **ID**, **Capability**,
**Support**, **Evidence**, **Targets**. `SKILL.md` §4 carries only the exceptions.

| ID | Capability (verbatim) | Reference file |
|----|-----------|----------------|
| CAP-01 | Prerequisites, toolchain, package install | `setup.md` |
| CAP-02 | Platform permissions, entitlements, build config | `setup.md` |
| CAP-03 | Connecting: config, opening, persistence directory | `connect.md` |
| CAP-04 | Authentication and identity | `connect.md` |
| CAP-05 | Lifecycle: start/stop sync, shutdown, ownership | `connect.md` |
| CAP-06 | Customizing transports | `transports.md` |
| CAP-07 | Sync subscriptions and sync scopes | `sync.md` |
| CAP-08 | Querying the store: executing DQL | `store.md` |
| CAP-09 | Transactions | `store.md` |
| CAP-10 | Indexing | `store.md` |
| CAP-11 | Observers, diffing and back-pressure | `observers.md` |
| CAP-12 | Attachments | `attachments.md` |
| CAP-13 | Presence graph and connection requests | `presence.md` |
| CAP-14 | Sync status and local commit tracking | `sync.md` |
| CAP-15 | Logging, diagnostics and stats | `observability.md` |
| CAP-16 | Error handling | `errors.md` |
| CAP-17 | Device storage management and eviction | `store.md` |
| CAP-18 | Testing | `testing.md` |
| CAP-19 | v4 to v5 migration, API and on-disk store | `versions.md` |
| CAP-20 | Preview and platform-specific APIs | `preview.md` |

### Why these twenty

Derived from the Ditto documentation navigation, not invented. The "Build with the SDK"
tab in `mintlify-docs/docs.json` carries **six content groups common to both v4 and
v5** — Overview & Setup, Accessing Data, Syncing Data, Authentication and Authorization,
Managing the Mesh, Deploying your App — and CAP-01…CAP-20 cover the substantive pages in
those six.

Each version also has groups the other does not: v5 adds `SDKs` (per-language install /
compatibility / release-notes / migration pages, which are **sources** for the CAPs
rather than capabilities in their own right); v4 adds `Reference` (API reference,
release notes, compatibility) and `Preview Features` (`sdk/v4/ditto-config`, a CAP-20
source). Index and landing pages map to no CAP by design.

**Known uncovered:** `sdk/latest/quickstarts/mongodb-migrationguide` — migration from
MongoDB Atlas Device Sync — maps to no CAP. CAP-19 is explicitly v4 → v5. This is a
deliberate scope exclusion, not an oversight: Atlas migration is a one-time
data-platform concern, not an SDK API surface. If an SDK skill needs it, link the page.

Capabilities that do not appear in the docs navigation but do appear in the shipped API
surface — disk usage, small peer info, transport conditions, back-pressure — are folded
into CAP-11 and CAP-15. See [Appendix B](#appendix-b--measured-documentation-gaps).

---

## 7. Support and Evidence

Two independent columns. The first review of this template found that a single status
column conflated three axes — what the SDK ships, what the docs cover, and what the
skill demonstrates — leaving four of twenty rows undecidable on the flagship language.
Splitting them fixes that and makes both columns mechanically checkable.

### Support — what the **SDK** ships. Nothing else.

| Value | Meaning | Also required |
|---|---|---|
| `yes` | Fully available in this SDK. | — |
| `partial` | Some of the capability exists, some does not. | One sentence naming precisely which part is missing. |
| `preview` | Shipped but explicitly preview or unstable. | The opt-in mechanism verbatim, the exact version it appeared in, and the stability warning. |
| `no` | Not exposed by this SDK at all. | The reason, and the nearest workaround if one exists. |

`partial` describes **feature** partiality. **Target** partiality — a capability present
on Android but not JVM, or on Node but not Web — goes in the `Targets` column, never in
`Support`.

### Evidence — the strongest `CONTRIBUTING.md` §4 tier you actually used

| Value | Meaning |
|---|---|
| `executed` | You ran it against a real SDK at a named patch version. |
| `docs-sample` | A published doc page has a working sample in this language. |
| `api-dump` | Taken from the public API surface (`.api` dump, published API reference). |
| `source` | Read from SDK source. |
| `inference` | Reasoned, not verified. |

`api-dump`, `source` and `inference` each require the path and ref inline, per
`CONTRIBUTING.md` §4.

This pair removes the old incentive problem: there is no longer a status that is both
the easy answer and the obligation-free one. Logging on Kotlin is unambiguously
`Support: yes` / `Evidence: api-dump`, and the documentation gap is visible as data.

### Targets

A short closed vocabulary declared once in `README.md` and used in every row —
Kotlin: `android | jvm | both`; JS: `web | node | rn | all`; Swift: `ios | macos | all`.
Single-target SDKs use `all` throughout.

**A capability row is never omitted.** Parity across the nine SDKs is genuinely
incomplete, and an unstated gap is indistinguishable from an oversight.

---

## 8. Where to source each capability

Follow the evidence hierarchy in `CONTRIBUTING.md` §4: executed code beats SDK source,
which beats documentation, which beats inference.

### 8.1 Doc slugs are not uniform — use this table

There is no single `<lang>` token. Four different naming schemes are in use, and
assuming one breaks JS, Java, C# and Go. Substitute from this table, which was
enumerated from the docs checkout:

| Skill | `install-guides/` | `compatibility/` | `release-notes/` | `migration-guides/` | `snippets/…/playground/` | `api-reference/` |
|---|---|---|---|---|---|---|
| `swift-sdk` | `swift` | `swift` | `swift` | `swift-v4`, `swift-dql` | `swift` | `swift` |
| `kotlin-sdk` | `kotlin` | `kotlin` | `kotlin` | `kotlin-v4`, `kotlin-dql` | `kotlin` | `kotlin` |
| `java-sdk` | **`java/server`** | `java` | `java` | `java-v4`, `java-dql` | `java` | `java` |
| `js-sdk` | `js`, `react-native` | **`js-web`, `nodejs`, `react-native`** | **`javascript-web`, `javascript-nodejs`, `react-native`** | **`web-js-*`, `node-js-*`, `react-native-*`** | `js` | `js` |
| `csharp-sdk` | `c-sharp` | `c-sharp` | `c-sharp` | `c-sharp-v4`, `c-sharp-dql` | **`csharp`** | `c-sharp` |
| `cpp-sdk` | `cpp` | `cpp` | `cpp` | `cpp-v4`, `cpp-dql` | `cpp` | `cpp` |
| `rust-sdk` | `rust` | `rust` | `rust` | `rust-v4`, `rust-dql` | `rust` | `rust` |
| `flutter-sdk` | `flutter` | `flutter` | `flutter` | `flutter-v4`, `flutter-dql` | `flutter` | `flutter` |
| `go-sdk` | `go` | `go` | `go` | **none exist** | `go` | `go` |

Bold cells are where the obvious guess is wrong. Two consequences worth stating up front:

- **`js-sdk` uses three different slug schemes across four directories.** It is the one
  skill spanning three runtimes, and it is the one where the slug breaks.
- **Go has no migration guides at all.** CAP-19 for `go-sdk` is `Support: no` — Go is
  Preview and has no v4 to migrate from. Do not send its author hunting.

v4 pages live under `sdk/v4/` with the same slugs, except `install-guides/java/` which
has both `server` and `android` (the Java Android target existed in v4 and does not in
v5 — worth a CAP-02 note in `java-sdk`).

### 8.2 Sources per capability

`<lang>` below means "the right slug from §8.1 for that directory".

| ID | Primary sources |
|----|-----------------|
| CAP-01 | `sdk/latest/install-guides/<lang>.mdx`; `sdk/latest/compatibility/<lang>.mdx`; `sdk/v4/install-guides/<lang>.mdx` |
| CAP-02 | `sdk/latest/install-guides/<lang>.mdx` (Android manifest, iOS entitlements, MAUI permissions); `sdk/latest/deployment/network-deployment.mdx`; `sdk/latest/deployment/bluetooth-on-linux.mdx`; `best-practices/optimizing-bundle-sizes-for-android.mdx` |
| CAP-03 | `snippets/connect-examples-v5/playground/<lang>-playground.mdx`; `sdk/latest/quickstarts/`; `sdk/latest/install-guides/<lang>.mdx`. *(`snippets/connect-examples-v5/development/` holds only `go` and `java`.)* |
| CAP-04 | `sdk/latest/auth-and-authorization/{cloud-authentication,data-authorization,certificate-based-security}.mdx`; the AUTHENTICATION block in `<lang>-v4.mdx` |
| CAP-05 | `sdk/latest/sync/syncing-data.mdx`; `best-practices/sync-handling.mdx` |
| CAP-06 | `sdk/latest/sync/customizing-transport-configurations.mdx`; `sdk/latest/sync/managing-redundant-bluetooth-le-connections.mdx`; `sdk/latest/deployment/wifi-aware-chipset-considerations.mdx`; `sdk/latest/deployment/setting-routing-hints.mdx` |
| CAP-07 | `sdk/latest/sync/syncing-data.mdx`; `sdk/latest/sync/sync-scopes.mdx`; `sdk/latest/sync/using-alter-system.mdx` (the only page with host-language `ALTER SYSTEM` samples — Java and Swift); `dql/alter-system.mdx` |
| CAP-08 | `sdk/latest/crud/{create,read,update,delete}.mdx`; `sdk/latest/crud/working-with-ejson.mdx`; `sdk/latest/migration-guides/<lang>-dql.mdx` |
| CAP-09 | `sdk/latest/crud/transactions.mdx` |
| CAP-10 | `dql/indexing.mdx`; `dql/explain.mdx`; `dql/advise.mdx`; `dql/access-paths.mdx`; `dql/profile.mdx` |
| CAP-11 | `sdk/latest/crud/observing-data-changes.mdx`; `dql/replacing-live-queries.mdx`; the OBSERVERS block in `<lang>-v4.mdx` (present in 8 of 10) |
| CAP-12 | `sdk/latest/crud/working-with-attachments.mdx` |
| CAP-13 | `sdk/latest/sync/using-mesh-presence.mdx`; `sdk/latest/sync/handling-connection-requests.mdx` |
| CAP-14 | `sdk/latest/sync/{monitoring-sync-status,tracking-local-commits,cloud-sync-status}.mdx` |
| CAP-15 | `sdk/latest/deployment/{logging,device-observability-and-ditto-logs,getting-system-information,integrate-ditto-tools-for-kotlin-swift-and-c-net-in-15-minutes,vsc-es}.mdx`; the LOGGING and DISK USAGE blocks in `<lang>-v4.mdx` (**only `c-sharp`, `cpp`, `kotlin`, `swift`**) |
| CAP-16 | The published API reference (Appendix A) and SDK source — **primary**, because the ERROR HANDLING block exists in `kotlin-v4.mdx` only; `sdk/latest/deployment/troubleshooting.mdx` |
| CAP-17 | `sdk/latest/sync/device-storage-management.mdx`; `dql/evict.mdx` |
| CAP-18 | `sdk/latest/deployment/testing.mdx` |
| CAP-19 | `sdk/latest/migration-guides/<lang>-v4.mdx` **and** `<lang>-dql.mdx`; `sdk/latest/v5-whats-new.mdx`; `sdk/latest/release-notes/<lang>.mdx`; `snippets/common-release-notes/` |
| CAP-20 | `sdk/latest/sync/data-streams.mdx`; `sdk/v4/ditto-config.mdx`; that SDK's release notes and `snippets/common-release-notes/` |

### 8.3 When the docs do not answer it

Fall back in this order, and record the tier in the `Evidence` column:

1. **Run it** — a one-file program against the real SDK at a named patch version.
   Always worth it for CAP-03, CAP-08 and CAP-11.
2. **Read the public API surface** — for Kotlin and Java, the binary-compatibility dumps
   at `ditto/sdks/kotlin/api/*/api/**/*.api` at a named ref; otherwise the published API
   reference in Appendix A.
3. **Read the SDK source** — `ditto/sdks/<lang>/` at a named ref. Cite path and ref.
4. **Infer**, and mark `Evidence: inference`.

The per-language `-v4.mdx` guides each open with an "AI Agent Prompt" block enumerating
the v4 → v5 delta. Where it exists it is the densest source for CAP-19 and for §8
anti-patterns — it names constructs that genuinely fail to compile and the errors they
produce. **Check it exists for your language first**: the named blocks are unevenly
distributed (Appendix B).

---

## 9. Code sample rules

1. **One language per fence, tagged, lowercase.** ` ```kotlin `, ` ```swift `,
   ` ```csharp `, ` ```dart `, ` ```rust `, ` ```typescript `, ` ```cpp `, ` ```java `,
   ` ```go `. DQL goes in ` ```sql `. *(Some doc pages use mixed casing —
   ` ```C# `, ` ```JS `. Do not copy that.)*
2. **Build files use their own fence**, so extraction tooling can tell them from
   host-language samples:

   | Build system | File | Fence |
   |---|---|---|
   | Gradle | `build.gradle.kts` (canonical form) | ` ```kotlin ` |
   | SwiftPM | `Package.swift` | ` ```swift ` |
   | npm | `package.json` | ` ```json ` |
   | NuGet | `.csproj` / `dotnet add` | ` ```xml ` / ` ```bash ` |
   | Cargo | `Cargo.toml` | ` ```toml ` |
   | pub | `pubspec.yaml` | ` ```yaml ` |
   | Go | `go get` | ` ```bash ` |
   | CMake / tarball | — | ` ```bash ` |

   Show **one canonical form** per build system. For Gradle that is the Kotlin DSL;
   the version-catalog form, if shown at all, goes in `setup.md` only.
3. **Compiling, not illustrative.** Include imports and the enclosing
   function/suspend/async context. `examples/minimal-app.md` in particular must be
   complete.
4. **Show the failure, not just the fix.** Every anti-pattern needs the symptom a
   developer will actually see. For a performance anti-pattern the symptom is a
   **measured number or a named symbol**, never the word "slow".
5. **Real identifiers.** Never paraphrase a method, type or artifact name.
6. **No pseudo-code.** If you cannot write the real call, set `Support` or `Evidence`
   accordingly and say so.
7. **Placeholders are uppercase and obvious**: `REPLACE_ME_WITH_YOUR_DATABASE_ID`.
   Never commit a real token, database ID or URL.

---

## 10. Version coverage

Every SDK skill documents **4.14.x (LTS), 5.0.x and 5.1.x**, matching the `dql` skill.

Follow `CONTRIBUTING.md` §2 in full — exact patch versions, every version-gated claim
tagged inline *and* in `references/versions.md`, the failure mode on older versions, and
never a ✓ on something that parses but misbehaves.

Three rules specific to SDK skills:

- **`references/versions.md` owns every fact that differs across version lines**,
  including package coordinates. `setup.md` shows the v5 form only and links.
  `SKILL.md` §3 is a pointer, not a claim. One fact, one home.
- **v4 and v5 are different APIs, not two versions of one.** Show the v5 form in the
  body; keep the v4 form in `references/versions.md`. No inline "in v4 this was…" asides.
- **The default is v5.** An agent that cannot determine the user's version emits 5.1.x
  and says which version it assumed. State this in `SKILL.md` §3 so all nine behave
  identically.

---

## 11. Token budget

The name and description are injected into **every** session, and nine SDK skills will
eventually coexist. For calibration: `skills/dql/SKILL.md` is 84 lines and
`skills/ditto-mesh-networking/SKILL.md` is 246.

| File | Target | Hard limit |
|---|---|---|
| `description` | ~400 characters | 1024 |
| `SKILL.md` body | ≤ 300 lines | 400 lines |
| Each `references/*.md` | ≤ 400 lines | split instead (§3) |

The budget is achievable because §4 carries exceptions rather than the full map, and §5
carries a short excerpt rather than the whole program. If you are over, those are the
two places to look first — do not delete a capability from the `README.md` map.

---

## 12. Tests and structural CI

### 12.1 Structural checks — must be automated

Two-thirds of the §14 checklist is mechanical, and leaving it to human diff across nine
PRs is how it rots. The repo already demonstrates the failure: `skills/dql/SKILL.md`
ships `name: write-dql` in `skills/dql/`, and CI passes.

`.github/workflows/ci.yml` **must be extended with these checks in the same PR as the
first SDK skill**:

1. Frontmatter `name` == directory name (for **all** skills; fix or grandfather `dql`).
2. Frontmatter contains only permitted keys.
3. `Use ONLY for` present in an SDK skill's description.
4. The ten `SKILL.md` H2 headings present, in order, spelled exactly.
5. `README.md` capability map has twenty rows, CAP-01…CAP-20, in order, titles verbatim.
6. Every `Support` / `Evidence` / `Targets` value is in its enum.
7. Every capability-map link resolves, **including the anchor**.
8. All §3 required files present; `references/` exactly one level deep.
9. No file in `skills/` cited as a source (grep for `skills/` or `../..` in a citation).
10. `SKILL.md` body within the §11 hard limit.

Items needing human judgement and *not* automatable: "front-loads literal API names",
"no concept material duplicated", "§6 names the actual thread", "version claims agree
with `versions.md`", "citations name real paths at named refs".

### 12.2 Executable verification

- **DQL inside an SDK skill is not covered today.** `tests/dql/scripts/extract-queries.mjs:7`
  hard-codes its scan root to `skills/dql`. Still tag DQL as ` ```sql ` so extending the
  harness to a second root stays a one-line change, but do not assume your DQL is
  verified because you tagged it.
- **`examples/minimal-app.md` is the normative program** and must be **compiled and
  run** against each supported version line. Its *Expected output* section must contain
  a **pasted real build-and-run transcript** naming the patch version — that is the one
  part of "it compiles" a reviewer can actually check without nine toolchains.
- Keep the program as a **real source file** under `tests/<lang>-sdk/` and have
  `examples/minimal-app.md` reference it, rather than restating it.
- **Before the third SDK skill merges**, CI must compile that file for the languages
  merged so far. "Encouraged" is not sufficient for the one property this template
  exists to guarantee.

---

## 13. Authoring workflow

1. Branch from `main`, named for the Linear issue.
2. Copy the skeleton:
   ```bash
   cp -R docs/templates/sdk-skill skills/<lang>-sdk
   ```
3. **Wire up packaging immediately** — plugin wrapper, marketplace entry, README row,
   per `CONTRIBUTING.md` → "Adding a new skill". CI's orphan-skill check fails on any
   push where `skills/<lang>-sdk/` exists with no plugin, so deferring this means a red
   branch for the entire authoring period.
4. Draft the frontmatter using §4. The error strings are a placeholder for now — you
   cannot know them until CAP-16.
5. Work the capability map top to bottom. For each ID: resolve the slug via §8.1, read
   the sources, set `Support` / `Evidence` / `Targets`, write the reference section,
   record the citation. Do not skip to the interesting capabilities — an unfilled row is
   what a reviewer looks for first.
6. Write `examples/minimal-app.md`, then **compile and run it** on each supported
   version line and paste the transcript.
7. Fill `references/versions.md`, including the on-disk store migration subsection.
8. Write `SKILL.md` §6, §7 and §8 last — by then you know where the real failure modes
   are.
9. **Rewrite the description** from `errors.md` and §8. The error strings in it must be
   ones you actually observed, not ones you guessed in step 4.
10. Run the validations and open the PR, filling in every section of the template,
    including what you did not verify.

---

## 14. Reviewer checklist

Items marked **[CI]** should be machine-checked once §12.1 lands; until then check them
by hand.

Structural — a PR failing any of these goes back before the content is read:

- [ ] **[CI]** Directory is `skills/<lang>-sdk/`; frontmatter `name` matches it.
- [ ] **[CI]** Only permitted frontmatter keys; `allowed-tools` present.
- [ ] Description leads with the exclusion gate and front-loads file extensions and
      build-file names, not only API names.
- [ ] **[CI]** All ten `SKILL.md` H2 sections present, in order, spelled exactly.
- [ ] **[CI]** `README.md` map has all twenty rows, titles verbatim, no row omitted.
- [ ] **[CI]** Every `Support` / `Evidence` / `Targets` value is in its enum; every
      non-`yes` `Support` and every `api-dump`/`source`/`inference` `Evidence` carries
      the extra information §7 requires.
- [ ] `SKILL.md` §4 lists exactly the non-`yes` rows — no more, no fewer.
- [ ] **[CI]** All §3 files present; `references/` one level deep; all map links and
      anchors resolve.

Content:

- [ ] `examples/minimal-app.md` contains a pasted real build-and-run transcript naming
      the patch version.
- [ ] `SKILL.md` §5 is a runnable excerpt that agrees with `examples/minimal-app.md`.
- [ ] Contested topics follow §1's ownership table; concept material is linked with a
      public docs URL fallback, not restated.
- [ ] §6 names the actual thread per API; §7 names what must be retained and the symptom.
- [ ] Every §8 anti-pattern includes the symptom; performance ones name a number or symbol.
- [ ] Version claims are tagged inline and in `references/versions.md`, and agree.
- [ ] Citations name real paths at named refs; no file in this repo cited as a source.
- [ ] `README.md` states which versions were executed against and what was not verified.

---

## Appendix A — the nine SDKs

From `mintlify-docs/sdk/latest/install-guides/` and
`sdk/latest/api-reference/api-reference.mdx` (5.1.0). Verify before relying on a
coordinate — these move.

| Skill | Package / distribution | Notes |
|---|---|---|
| `swift-sdk` | SPM: `https://github.com/getditto/DittoSwiftPackage` | v5 no longer re-exports `Foundation` |
| `kotlin-sdk` | Gradle: `com.ditto:ditto-kotlin` | KMP root module; Gradle resolves the Android variant. `minSdk` 24, JDK 17. `Targets: android \| jvm` |
| `java-sdk` | Gradle: `com.ditto:ditto-java` + `com.ditto:ditto-binaries` | Platform selection is a Gradle **capability** — `requireCapability('com.ditto:ditto-binaries-linux-x64')` — not a separate coordinate. Server-side only in v5; v4 also had an Android target |
| `js-sdk` | npm: `@dittolive/ditto` | One package across Web, Node.js and React Native. Web requires `init()`. `Targets: web \| node \| rn` |
| `csharp-sdk` | NuGet: `dotnet add package Ditto` | `DittoSyncPermissions` is MAUI-only (`#if IOS \|\| ANDROID \|\| MACCATALYST`) |
| `cpp-sdk` | Tarball `Ditto.tar.gz` → `libditto.a` + `Ditto` header | No package manager |
| `rust-sdk` | crates.io: `dittolive-ditto` | `DatabaseId` replaced `AppId` in v5 |
| `flutter-sdk` | pub.dev: `ditto_live` | `Ditto.init()` **required in 5.0.x; optional from 5.1.0** — `Ditto.open()` initializes automatically. Version-tag this |
| `go-sdk` | `github.com/getditto/ditto-go-sdk/v5` | **Public Preview.** No v4 exists → CAP-19 is `Support: no`. No migration guides |

The docs navigation lists React Native, JavaScript Web and JavaScript Node.js as three
separate entries. They are one npm package and therefore one skill; runtime differences
go in the `Targets` column.

---

## Appendix B — measured documentation gaps

Measured by counting code fences across `mintlify-docs/sdk/latest/`, excluding pages that
`import` per-language snippets. These are where an author will find no sample and must
escalate to the API reference, the SDK source, or a program they run.

**There are ten `-v4.mdx` migration guides** (Swift, Kotlin, Java, C#, C++, Rust,
Flutter, web-js, node-js, react-native) — not nine. The named "AI Agent Prompt" blocks
inside them are unevenly distributed:

| Block | Present in |
|---|---|
| `OBSERVERS` | 8 of 10 (not `java-v4`, `rust-v4`) |
| `LOGGING`, `DISK USAGE` | **4 of 10** — `c-sharp`, `cpp`, `kotlin`, `swift` only |
| `signalNext` (literal) | 7 of 10 (not `cpp-v4`, `java-v4`, `rust-v4`) |
| `BACK-PRESSURE` (heading) | **1 of 10** — `kotlin-v4` only |
| `ERROR HANDLING`, `Exception Hierarchy Changes` | **1 of 10** — `kotlin-v4` only |

Page-level gaps:

| Capability | Gap |
|---|---|
| CAP-15 | `deployment/logging.mdx` documents rotation policy with **no code samples in any language**. `deployment/device-observability-and-ditto-logs.mdx` and `deployment/integrate-ditto-tools-…-15-minutes.mdx` have **zero code fences**. `getting-system-information.mdx` has only JSON and SQL. Disk usage has no standalone page — it appears in `logging.mdx`, `vsc-es.mdx`, and 4 of 10 migration guides. |
| CAP-16 | The exception taxonomy is documented in prose for Kotlin only. Every other language sources this from the API reference or SDK source. |
| CAP-08 | `crud/working-with-ejson.mdx` has ` ```sql ` fences only — no host language, no snippet imports. |
| CAP-17 | `sync/device-storage-management.mdx` has samples for Java and JavaScript only. |
| CAP-18 | `deployment/testing.mdx` covers C#, Go, Java, JS, Kotlin, Rust, Swift, C++ — **no Dart/Flutter**. |
| CAP-20 | `sync/data-streams.mdx` is Kotlin-only, requires 5.1.0, and is opt-in behind a preview annotation. Other SDKs record Data Streams as `Support: no` unless their own release notes say otherwise. |
| CAP-06 | Transport conditions: documented for Kotlin (`kotlin-v4.mdx`), JS (5.0 release notes) and Flutter (`Ditto.observeTransportConditions()`, new in 5.1). C++, Java, Rust and Go need source verification. |

Re-verify before citing. These were measured on the docs checkout at the time of
writing and the docs are actively maintained — a gap since filled should be sourced from
the docs, not from here.
