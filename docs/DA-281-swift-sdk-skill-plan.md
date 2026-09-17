# DA-281 — Swift SDK skill implementation plan

**Status:** proposed for review. This is a temporary planning file; remove it when
the implementation begins. No skill, plugin, CI, or Linear changes are included in
this planning work.

## Outcome

Add a customer-facing `swift-sdk` skill that makes Ditto feel native to modern Swift
developers building iOS, iPadOS, macOS/AppKit, and Mac Catalyst applications with
SwiftUI, UIKit, or AppKit. The skill will follow the SDK-skill template created in
SDKS-4880, cover all twenty capabilities, and make version-specific guidance
unambiguous for Ditto SDK 4.14.x, 5.0.x, and 5.1.x.

The default code emitted when a project's SDK version cannot be determined will be
5.1.x code, with the assumed version stated. The 4.14.x form will live in the
version/migration reference rather than being mixed into every v5 sample.

## Proposed support boundary

| Version line | Planned verification target | How the skill treats it |
|---|---:|---|
| 4.14.x (LTS) | 4.14.6 | Fully documented supported line. **Emit the `Ditto.open`/`openSync` + DQL path, not the identity/collection path** — see the deprecation-polarity note below. Do not recommend 4.14.5, which the release notes identify as regressed (`mintlify-docs/sdk/v4/release-notes/swift.mdx:35`). |
| 5.0.x | 5.0.3 | Fully documented supported line. Use the v5 configuration, DQL, `sync`, and async APIs. |
| 5.1.x | 5.1.0 | Fully documented default line. Include its observer delivery and Swift-concurrency changes, and its two platform removals (Intel `x86_64` Mac and tvOS). |

**Only 4.14.x is LTS.** The sole long-term-support statement in the documentation is
`mintlify-docs/sdk/latest/v5-whats-new.mdx:266` — v4 receives 18 months of LTS,
extending to Dec 2027. No 5.x line is designated LTS anywhere, and this repo's own
convention agrees (`AGENTS.md`, `README.md`, `CONTRIBUTING.md` all write
"4.14.x (LTS), 5.0.x and 5.1.x"). Since this repo becomes public, an unfounded LTS
label is a support commitment made on Ditto's behalf and must not appear in
`versions.md` or `SKILL.md`.

### The 4.14.x deprecation polarity is the opposite of "legacy is safer"

At `sdk-release-4.14.6:cocoa/DittoSwift/Ditto.swift`, `Ditto.open(config:)` and
`openSync(config:)` are documented at L31 and L75 as *"the recommended initialization
path and will be the only supported path in SDK 5.0"*. It is the **identity path that
is deprecated**: `init(identity:persistenceDirectory:)` at L683, `DittoIdentity` at
L187, `startSync()`/`stopSync()` at L440/L448, and the entire collection API at
`cocoa/DittoSwift/Store/DittoStore.swift:65-126` (*"Use DQL … instead"*).

**The config path is marked preview on 4.14.x, and the skill recommends it anyway.** A
complete grep for `preview` across `sdk-release-4.14.6:cocoa/DittoSwift/**.swift` returns
**five** hits: `DittoConfig.swift:14`, `DittoAuthenticationProvider.swift:9`,
`DittoAuthenticator.swift:11` and `:56`, and `Ditto.swift:142`. The v4 release notes agree
— `sdk/v4/release-notes/swift.mdx:419,421` label both `DittoConfig` and
`Ditto.open(config:)` **(Preview)**. So 4.14.x offers no un-caveated initialization route:
the identity path is deprecated, the config path is preview.

**Governing principle, refined by Swift SDK engineering review: never emit a deprecated
API; be version-aware; among the remaining options prefer the one that also exists in
v5.** Three rules in priority order, not one:

1. **Never recommend a deprecated API.** This is the primary rule and it outranks the
   others. The 4.14.4 deprecations were added *to the LTS line on purpose* — Ditto
   deprecated the identity initializers, `startSync`/`stopSync`, the collection APIs and
   the rest specifically to move people off them **before** v5 removed them. Honouring
   those annotations is honouring that intent, and emitting a deprecated call is working
   against a deliberate migration runway.
2. **Be version-aware and emit the best path for the project's actual version.** The
   skill establishes the version first — from `Package.resolved`, the Xcode package pin,
   or by asking — and then recommends the best non-deprecated form *for that line*,
   rather than assuming one answer fits all three. Where the version cannot be
   determined it emits 5.1.x and says so.
3. **Among non-deprecated options, prefer the form that also exists in v5**, so code
   written on 4.14.x today is not rewritten at upgrade and 4.14→5 becomes a dependency
   bump.

In practice these three converge on the same answer across the core surface, because the
deprecations point at the v5 shapes by design. Where they could diverge, rule 1 wins.

This resolves the preview-vs-deprecated question, and applies to every capability rather
than just initialization. Read `DittoConfig`'s own doc comment in that light: *"This API is in **preview** and will
become the standard way to initialize Ditto instances in v5, replacing the legacy
`DittoIdentity`-based initialization."* The preview label here means *"this is what v5
standardizes on"*, not *"this is unstable and may vanish"* — and v5 shipped it as GA
exactly as promised. Choosing the deprecated identity path to avoid a preview label would
trade a disclosure for a guaranteed rewrite.

**Verified forward-compatible surface** — each of these exists on 4.14.6 *and* v5, so the
skill uses one form across all three lines with no version branch:

| Capability | Form used on every line | 4.14.6 evidence |
|---|---|---|
| Initialization | `DittoConfig` + `Ditto.open(config:)` / `openSync(config:)` | `Ditto.swift:56`, `DittoConfig.swift` (preview-labelled) |
| Sync control | `ditto.sync.start()` / `.stop()` / `.isActive` | `DittoSync.swift:25,35,44` |
| Subscriptions | `ditto.sync.registerSubscription(...)` | `DittoSync.swift:82` |
| Queries | `ditto.store.execute(query:)` + DQL | `Store/DittoStore.swift:46,628` |
| Observation | `ditto.store.registerObserver(...)` | `Store/DittoStore.swift:155,200` |
| Presence | `ditto.presence` / `presence.observe()` | `Ditto.swift`, and 4.14.6 deprecates `observePeers` in its favour |
| Auth | `ditto.auth?.expirationHandler` | `Ditto.swift:319` (`public internal(set) var auth`) |

**The exceptions, where no both-versions form exists.** These are pure renames with no
forward-compatible spelling, so the skill shows the v5 form in the body and gates the
4.14 form in `versions.md`:

- `ditto.activated` (4.14.x) → `ditto.isActivated` (v5) — `isActivated` does not exist on
  4.14.6.
- `peerKeyString` (4.14.x) → `peerKey` (v5), and the other `DittoPeer` /
  `DittoConnection` renames in the migration guide's tables.

**Consequences for the capability map.** `Support` reports what the SDK ships, so
CAP-01/CAP-03/CAP-04/CAP-05 carry `preview` for 4.14.x with the stability note template §7
(`SDK-SKILL-TEMPLATE.md:322`) requires — the opt-in mechanism verbatim, the version it
appeared in, and the warning. The *recommendation* is unchanged: `versions.md` states that
the 4.14.x config path is preview-labelled, that it is the v5 GA API, and that the skill
recommends it precisely because it is the form that survives the upgrade.

### Version quality is not monotonic — and on lifetime, both v5 lines are worse than 4.14.6

Three separate Swift-specific defects cut against a "newer is safer" reading, and
`versions.md` must carry all three rather than implying a monotonic 4 → 5.0 → 5.1
improvement:

1. **`deliverOn`** is honoured in 4.14.6, ignored in 5.0.x (crashing under Swift
   concurrency), fixed in 5.1.0 (#SDKS-3856).
2. **The callback-exception/`SIGABRT` fix** (#SDKS-3483) ships in 4.14.6 and 5.1.0,
   skipping 5.0.x entirely.
3. **Use-after-deallocation is a hard crash on both v5 lines, and only 4.14.6
   recovers** — see below. On this axis 5.1.0 is *not* an improvement over 4.14.6.

### Use-after-deallocation: 4.14.6 throws, v5 calls `fatalError`

This is the single most important correction to an earlier draft of this plan, which
had the polarity backwards and cited the wrong lines.

`sdk/v4/release-notes/swift.mdx:20` (#SPO-960, 4.14.6): *"Registering a store observer
or executing a query after `Ditto` has been deallocated now throws a recoverable error
instead of crashing."* Confirmed at
`sdk-release-4.14.6:cocoa/DittoSwift/Store/DittoStore.swift:206-209`:
`throw DittoError.useAfterCloseError(message: "Can't register store observer, the
corresponding Ditto has been deallocated.")`.

**That fix was not carried into v5.** At
`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStore.swift:230-231` the same guard body
is `fatalError("Can't register store observer, the corresponding \`Ditto\` is \`nil\`,
which means it's out of scope. …")`, repeated at `:285`, `:537`, `:626`, and for
`execute` at `:732`. Identical at
`sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoStore.swift:231,285,537,626,722`. The
lines an earlier draft named as "the surviving `fatalError` path" (`:652-653`) are the
opposite — a comment plus a safe `guard let ditto = ditto else { return }`.

**Why this matters more than the version table.** It raises the stakes on the lifetime
rules from "you may get an error" to "you will crash the app": on v5, dropping the last
strong `Ditto` reference and then touching `registerObserver`, `execute`, or
`fetchAttachment` is an unrecoverable `fatalError`, not a `throws` an app can catch.
`SKILL.md`'s lifetime section states that outright, with the version split, and must not
describe v5 behaviour as recoverable.

4.12.x and 4.13.x will be **audited, not claimed as supported lines** — and that audit
must be **redone**. An earlier draft closed it by reading only the shared
`4-12-capabilities.mdx` / `4-13-capabilities.mdx` snippets, concluded "no Swift-specific
API changes", and was wrong: `sdk/v4/release-notes/swift.mdx` carries five
`## 4.1x.y Swift Specific Changes` sections in that range (`:143` 4.13.4, `:315` 4.12.4,
`:329` 4.12.3, `:363` 4.12.2, `:409` 4.12.0). At least three matter to this skill:
`:413` adds `StoreErrorReason.persistenceDirectoryLocked`, *"now thrown by `Ditto.open()`
or `Ditto.openSync()` instead of crashing"* — still live in v5
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoError.swift`) and the named error for this
plan's own "one opened instance per persistence directory" test, as well as a candidate
for the frontmatter's required literal error strings; and `:331-335` (4.12.3) fixes a race
condition and a memory leak in store observers. Re-run the audit against the **release
notes**, not the capability snippets, before concluding what `versions.md` inherits. A user on either unsupported line will be told
that the skill's verified code targets 4.14.6, 5.0.3 or 5.1.0, rather than being given
an unqualified compatibility claim.

The platform table will be stated per version line, not inferred from the language.
Platform support is **not constant across the three supported lines**, so a single
table would be wrong:

- v5 verification will cover iOS and iPadOS (one `ios` target), macOS/AppKit, and
  Mac Catalyst, using the published 5.1 minimums of iOS/Catalyst 15 and macOS 12
  (`sdk/latest/compatibility/swift.mdx`).
- The implementation will reconcile the v4 install guide's AppKit statement
  (Mac Catalyst 14+, macOS/AppKit 11+) with its compatibility page, which lists only
  iOS/iPadOS/Simulator at iOS 14+, before asserting the 4.14 macOS target/minimum.
- **tvOS is a four-way source conflict and must be resolved in the ledger before any
  wording is written.** The sources do not agree:
  1. `sdk/latest/migration-guides/swift-v4.mdx:401-410` — a `<Warning>`: *"tvOS — No
     longer supported in **v5.0**"*, and instructs the reader to STOP and contact
     support if the app targets it.
  2. `snippets/common-release-notes/5-1-capabilities/swift-specific-changelog.mdx` —
     *"Removed: tvOS platform support. (#SDKS-3944)"*, i.e. **5.1**.
  3. `DittoSwiftPackage.template/Package.swift` declares `.tvOS(.v14)` at 4.14.6 and
     `.tvOS(.v15)` at 5.0.3 — the manifest still lists it on the 5.0 line.
  4. Neither compatibility page lists tvOS at all (`sdk/latest/compatibility/swift.mdx`
     marks "Apple TV | --"; `sdk/v4/compatibility/swift.mdx` lists only
     iOS/iPadOS/Simulator).

  The likely reconciliation — a declared-but-unsupported platform on 5.0.x, formally
  removed from the manifest in 5.1 — must be **confirmed, not assumed**. The
  customer-facing outcome is the same either way and is the safe one: the skill claims
  **no tvOS support on any v5 line** and points a tvOS customer at v4 or at Ditto
  support, matching the migration guide's own instruction. A declared SPM platform is
  not a tested one.
- **visionOS was a supported v4 beta platform** — `swift-v4.mdx:401-410` lists
  *"visionOS (beta) — No longer supported in v5.0"* alongside tvOS. An earlier draft of
  this plan treated visionOS as excluded on every line; that is wrong for v4, and a
  visionOS customer needs the same "cannot upgrade to v5" blocker the guide gives for
  tvOS. Only **watchOS** is excluded across all lines.
- **`DittoPeerOS.tvOS` outlives tvOS support.** It is deprecated in 5.1 but retained so
  peers running older tvOS SDKs remain identifiable in the presence graph (#SDKS-3944),
  so a `switch` over `DittoPeerOS` must still handle it even though no v5 peer can be a
  tvOS device.
- **Intel (`x86_64`) Mac support is removed in 5.1.** This is breaking for customers
  on Intel hardware and will be called out in `versions.md` and the 5.1 migration
  notes, not left implicit in an Apple-silicon-only build transcript.
- watchOS is an explicit exclusion on every line; visionOS is excluded on v5 but was a
  v4 beta platform (see above). No sample implies support for either. `DittoSwiftTools` carries its own floor of iOS 15 /
  Catalyst 15 / macOS 12 as of 5.1.
- The Xcode/Swift toolchain floor is version-gated too: v5 requires Xcode 16+ and
  Swift 6.0+. This belongs in `versions.md` alongside the platform rows.

## Files and packaging to add or change

1. Copy `docs/templates/sdk-skill/` to `skills/swift-sdk/` and replace every TODO.
   This produces the required lean `SKILL.md`, human `README.md`,
   `best-practices.md`, `examples/minimal-app.md`, and the thirteen required reference
   files. **No migration reference is added** — per the migration-skill split, CAP-19 is
   a delegation pointer to the `ditto-v4-to-v5-migration` skill, and `versions.md` keeps
   only the compatibility matrix and version-gated facts. The skill authors no migration
   procedure of its own.
2. Add a scoped `plugins/ditto-swift/` wrapper with
   `.claude-plugin/plugin.json` and exactly one `skills/swift-sdk` directory symlink.
   Add the corresponding `ditto-swift` marketplace entry and one Swift row to the root
   `README.md`. Do not add Swift to an existing plugin and do not copy the skill into
   the wrapper.
3. Add `tests/swift-sdk/` with the real minimal-app source, version-selection/build
   configuration, and a runner or documented commands. `examples/minimal-app.md` will
   link to that source and paste real output rather than duplicating an untested
   program.
   **The fixture needs an offline license token before it can run at all.** An
   offline-only (`.smallPeersOnly`) instance must be activated:
   `sdk-release-5.1.0:sdks/swift/DittoSwift/Ditto.swift:390-399`
   (`setOfflineOnlyLicenseToken(_:)`, throwing
   `DittoError.activationError(.licenseTokenVerificationFailed/.licenseTokenExpired)`),
   and the SDK's own suite calls it in every offline test
   (`sdks/swift/DittoSwiftTests/Helpers.swift:233`, `DittoTests.swift:23`). The repo
   already has the plumbing and the precedent — `DITTO_OFFLINE_LICENSE` in the
   gitignored root `.env` loaded by `tests/lib/load-env.mjs` (`AGENTS.md`), passed in
   CI as `secrets.DITTO_OFFLINE_LICENSE` by `.github/workflows/dql-skill-tests.yml`.
   `tests/swift-sdk/` must define how the Xcode/XCTest fixture reads that value
   (environment variable, not a committed file — template §9 forbids committing a real
   token), `.env-sample` must document it, and the macOS workflow must pass the secret.
4. Extend `.github/workflows/ci.yml` with the SDK-skill structural validator required
   by the template's first-SDK rule: directory/frontmatter-name agreement, permitted
   frontmatter keys, `Use ONLY for` routing gate, exact ordered H2 headings, the
   twenty ordered capability rows and enum values, resolving links and anchors,
   required file shape/reference depth, no in-repository skill citations as evidence,
   and the `SKILL.md` size limit. The validator will run against every SDK skill so
   the remaining eight language skills inherit the contract.
5. **CI is split by runner.** `ci.yml` is `ubuntu-latest`; the structural validator is
   pure text checking and belongs there. Every Swift compile/run step needs macOS, so
   the build matrix goes in a new `.github/workflows/swift-skill-tests.yml` on
   `macos-latest`, modelled on `dql-skill-tests.yml` and triggered by changes to
   `skills/swift-sdk/**` or `tests/swift-sdk/**`. Do not attempt to add Swift builds
   to `ci.yml`.

## Content and architecture decisions

### The skill's audience is new clients building on v5

This is the organizing assumption behind several decisions below, so it is stated once
here rather than re-argued per reference.

**`DQL_STRICT_MODE=false` in v5 was a deliberate product decision**: it makes Ditto
behave the way ordinary JSON data behaves and matches how other platforms work, so that
a developer starting today never has to learn the knob exists. The skill honours that
intent. A new client's mental model should be "documents behave like JSON" — introducing
a strict/non-strict axis to explain a default they will never change makes the product
harder to learn for no benefit.

Consequences, applied throughout:

- **The Swift skill's own prose never mentions strict mode, and no v5 sample sets it.**
  An agent must not emit `ALTER SYSTEM SET DQL_STRICT_MODE = …` in v5 Swift code.

  **Scope this honestly: the skill cannot make strict mode invisible, only absent from
  its own voice.** Template §5 requires `SKILL.md` to hand off to the `dql` skill, and
  `dql` teaches the knob in its always-loaded body — `skills/dql/SKILL.md:25`
  (*"this skill assumes `dql_strict_mode = false` … the 5.x default and the migration
  target for 4.14.x meshes"*), `:23` (`SHOW dql_strict_mode`), and
  `skills/dql/best-practices.md:703,736`. Stating "a developer starting today never has
  to learn the knob exists" as an achieved outcome would be false the moment both
  skills load. The deliverable is narrower and still worth having: the Swift skill adds
  no strict-mode surface of its own.

  **One open question for the issue owner** (flagged by all three reviewers, not
  resolved here): `mintlify-docs/dql/strict-mode.mdx:20-25` documents that peers with
  *different* strict-mode settings sync but change merge behaviour — and a brand-new v5
  app joining an existing 4.14.x fleet is a rollout, not a migration, so the
  migration-only routing would leave that case unaddressed. Options are (a) accept the
  gap and rely on `dql` to cover it, (b) add one always-loaded sentence in `SKILL.md`
  pointing cross-version-mesh readers at `dql`, or (c) treat it as `dql`'s problem
  entirely and file against that skill. This is a product-voice decision, not a
  technical one.
- **v4 is migration context, not a co-equal target.** The skill still documents 4.14.x
  (the template requires all three lines) and still defaults to 5.1.x when the version
  is unknown, but the *primary reader* is building something new. v4 material exists to
  serve someone moving off it.
- **Migration is an opt-in path**, reached deliberately, not material that bleeds into
  greenfield answers.

### Migration belongs in its own skill, not in `swift-sdk`

**Decision from Swift SDK engineering review:** the published migration guide should
become a **separate skill**, not a reference inside `swift-sdk`. Adopted, with the
consequences below.

The reasoning holds up. Migration is a different task mode with a different audience and
a different lifetime: it is a one-time project for an existing v4 app, not something a
developer building on v5 ever loads. It is also not Swift-specific in structure — the
docs carry a `<lang>-v4.mdx` and `<lang>-dql.mdx` pair for every language, so putting
the procedure inside each SDK skill would duplicate the same shape nine times. And it
keeps `swift-sdk` inside its token budget instead of spending it on material most
readers never reach.

**Recommended shape:** one cross-language `ditto-v4-to-v5-migration` skill, sibling to
the existing concept skills, owning the migration procedure with per-language
references. Same pattern as `dql` owning DQL semantics while SDK skills own the
host-language call. This is a proposal for the issue owner — the alternative is a
per-language `swift-migration` skill, which is more skills to maintain but matches the
docs' file layout more literally.

**Non-negotiable constraint, and the reviewer's actual concern: the two skills must not
contradict each other.** If the migration guide says to initialize a certain way, the
SDK skill recommends that same way. A developer who lands on both — and many will, since
the migration path ends in writing v5 code — must not be given two different answers.
Concretely:

- `swift-sdk` and the migration skill use the **same** initialization form
  (`DittoConfig` + `Ditto.open`/`openSync`), the same sync API (`ditto.sync.*`), the same
  observation API, and the same ownership patterns.
- Where the published guide and this skill would diverge, **the divergence is resolved
  before either ships** — by fixing the guide with the docs owners, not by quietly
  differing. One already known: the guide's `/cocoa/` DocC host instruction is wrong for
  5.1.0.
- `SDK-SKILL-TEMPLATE.md` §1's ownership table gains a row for this boundary, so the
  partition is normative rather than a convention that erodes: **v4→v5 migration
  procedure → migration skill; the v5 API form this language uses → SDK skill.**

**Template amendments this requires** — worth flagging because they affect all nine SDK
skills, not just Swift:

- §6 currently maps **CAP-19 ("v4 to v5 migration, API and on-disk store") to
  `versions.md`**. With a migration skill, CAP-19 in an SDK skill becomes a *delegation
  pointer* to that skill plus the on-disk/store facts that remain version data. The
  capability row is still never omitted.
- §8.2's CAP-19 sources move with it.
- `versions.md` keeps the compatibility matrix and version-gated facts; it stops owning
  migration procedure.

**Scope effect on this issue:** `swift-sdk` no longer authors `references/migration.md`.
That work becomes a **follow-up issue** for the migration skill, and DA-281 shrinks
accordingly. The earlier plan to vendor the guides verbatim is superseded entirely — it
was already rejected on contract grounds, and this removes the need for it.

### Skill routing and organization

- The frontmatter will trigger only for Swift/Ditto artifacts: `.swift`, Xcode project
  files, `Package.swift`, `DittoSwiftPackage`, `import DittoSwift`, and verified
  symbols/errors. It will explicitly exclude the other eight SDK languages.
- `SKILL.md` will retain the template's ten required headings and target the template's
  **≤300-line goal** (§11), not the 400-line hard ceiling — especially since this plan
  promotes `deliverOn`, the v5 `fatalError` lifetime rule, and two Swift 6 traps into it.
  It will link to the DQL, data-modeling, subscriptions, and mesh skills plus their
  public documentation fallbacks instead of duplicating their semantics.
- `README.md` will contain the canonical CAP-01 through CAP-20 table. Each row will
  have `Support`, `Evidence`, and `Targets` values; `Targets` will use the prescribed
  `ios | macos | all` vocabulary, with iPadOS represented by `ios` and Catalyst called
  out in the relevant target notes.
- `references/versions.md` will be the sole home for package coordinates, platform
  support, version-gated facts, legacy-to-v5 migrations, and the on-disk store
  migration result. Every inline version claim elsewhere will point back to it.

### Ditto ownership per UI framework — the singleton question, answered properly

This is one of the first decisions a Swift developer makes and the skill must answer it
directly, per framework, rather than leaving it to inference. It is also where the most
expensive mistakes live: a second instance, a lost sync, or a UI update off the main
thread.

**Start from the constraint, not the style.** A Ditto instance is genuinely
app-scoped: it owns a persistence directory, a sync session, and a mesh presence, and
opening a second instance against the same directory is an error, not a performance
issue (`StoreErrorReason.persistenceDirectoryLocked`, added 4.12.0). It must live for
the whole app lifetime and be reachable from wherever data is read. **So the instinct
to reach for a singleton is correct** — the skill should say so plainly rather than
treating it as a smell. What differs per framework is the idiomatic mechanism for
expressing "one, app-lived, reachable everywhere".

| Framework | Idiomatic mechanism | Why this one |
|---|---|---|
| **SwiftUI** | A `@MainActor final class` app model holding the `Ditto` instance, created once with `@StateObject` on the `App`, injected with `.environmentObject(...)`. | **`@EnvironmentObject` gives the singleton experience without a global.** Any view reaches it with one property wrapper and no import of a shared static; `@StateObject` guarantees exactly one instance across re-renders; and because it is injected rather than looked up, previews and tests can substitute a different instance. This is the default the samples use. |
| **UIKit** | A shared app-scoped service owned by `AppDelegate`/`SceneDelegate`, injected into view controllers — **or a singleton**, which is a legitimate choice here. | UIKit has no environment-injection mechanism, so a `static let shared` façade is the pragmatic path and the skill should present it as such, not as a compromise. The requirement is that it stays a *thin* façade over an injectable service so tests can substitute one. |
| **AppKit** | Same as UIKit — app delegate or an injected service owns the instance; **window controllers own only window-scoped handles**. | The multi-window case is the real hazard: closing one window must not deallocate an app-wide instance, and must not leave that window's observers alive. |

**The equivalence to make explicit**, because it is the thing developers most often get
wrong when moving between frameworks: `@EnvironmentObject` in SwiftUI and a
`shared` singleton in UIKit/AppKit solve the *same* problem — app-wide reach to one
long-lived instance. They are not different architectures. A SwiftUI developer does not
need a singleton, and a UIKit developer is not doing something inferior by using one.
Say this once, clearly, so an agent does not port a SwiftUI environment object into a
UIKit app as a global, or bolt a singleton onto a SwiftUI app that already has a
composition root.

**What each sample must prove:** re-rendering or re-entering a screen does not open a
second instance; losing a screen or a window does not stop app-required sync; observers
are cancelled at their owning scope's boundary; and a test or preview can substitute an
instance without editing production code.

`@Observable` is an optional Observation-framework variant, not the baseline: the v5
minimum is iOS 15 / macOS 12, whereas `ObservableObject` / `@StateObject` /
`@EnvironmentObject` are available at that floor. Where `@Observable` is shown, it is
version-gated to iOS 17+.

### Threading: where callbacks land, and who may touch the UI

Threading is inseparable from the ownership question above — the ownership pattern
decides *who* holds state, and the threading rules decide *when it is safe to write to
it*. The skill treats them as one topic, and both `SKILL.md` §6 and
`best-practices.md` carry the following:

- **The app model is `@MainActor`.** Its published properties are written only on the
  main actor, so SwiftUI/UIKit/AppKit can read them directly with no dispatch of their
  own. That is the whole reason the composition-root pattern is worth the setup.
- **Observer callbacks do not arrive main-actor-isolated for free**, and the guarantee
  differs by version — see the `deliverOn` section below. On 5.0.x the parameter is
  ignored, so the handler must hop explicitly. A sample that passes `deliverOn: .main`
  and then assigns to an `@Published` property is correct on 4.14.6 and 5.1.0 and
  wrong on 5.0.3.
- **Convert before you cross.** Extract plain Swift values from the
  `DittoQueryResultItem`, call `dematerialize()`, and hand the resulting Sendable value
  across the actor boundary — do not carry SDK result objects into a `Task { @MainActor in … }`.
- **Do the expensive work off the main actor.** Decoding, diffing and sorting belong on
  a background queue or a detached task; only the final assignment is main-actor work.
  A large result set decoded inside a main-thread callback is the most common cause of
  a janky Ditto app.
- **Do not wrap `Ditto` in an actor.** `Ditto` and `DittoStore` are `Sendable` on v5;
  an actor wrapper adds hops without adding safety. Reserve actors for
  application-owned mutable async state such as token acquisition.
- **UIKit/AppKit callbacks** update views on the main actor/queue and are torn down in
  the controller's deinit or lifecycle boundary, with `[weak self]` in the handler to
  avoid the retain cycle that keeps a dead controller alive.

### Observers, back-pressure, and `DittoDiffer` — the highest-risk area of the skill

Observation is where most Ditto Swift apps actually live, and it is the easiest place to
write something that looks right, compiles, and then leaks, stalls, or janks. This gets
its own reference (`observers.md`) and the load-bearing rules are promoted into
`SKILL.md`.

**Observer basics the skill must state, from source
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStore.swift:190-230`):**

- `registerObserver` requires a **`SELECT`** query; anything else throws
  `storeError(.queryNotSupported)`. Invalid DQL throws `.queryInvalid`, bad arguments
  `.queryArgumentsInvalid`. These are real error strings the frontmatter can use.
- The returned `DittoStoreObserver` *"will remain active until the owning `Ditto` object
  goes out of scope or `cancel()` is called"* — so **not retaining it does not stop it**.
  It keeps firing. The retention rule is about being able to *cancel*, not about keeping
  it alive, and an earlier framing of this in the ownership section must agree.
- Use `arguments:` placeholders, never string interpolation into the query.

**Back-pressure — two modes, and one silent-failure trap.**

The default `handler:` form auto-signals after the handler returns: the SDK will deliver
the next result as soon as one is available. The `handlerWithSignalNext:` form hands the
handler a `DittoSignalNext` closure and delivers nothing further until it is called
(`DittoStoreObserver.swift:9-31`). While the handler is working, intervening changes are
**coalesced** — the next callback carries the latest state, not a queue of every
intermediate change.

- **Choose `handlerWithSignalNext` when the handler does real work** — decoding a large
  result set, writing to a database, driving an animation. It converts "fire as fast as
  changes arrive" into "fire as fast as this app can keep up", which is the difference
  between a responsive app and a backlog.
- **The trap: forget to call `signalNext()` and the observer silently stops forever.**
  No error, no log, no crash — updates just never arrive again. This is a named
  anti-pattern in `SKILL.md` §8, with the specific guidance that `signalNext()` must be
  called on **every** path out of the handler, including early returns and error paths,
  and exactly once.
- Coalescing is a **feature to state, not hide**: an app using `signalNext` must be
  correct against "latest state", never assume it sees every intermediate value, and
  must not treat callbacks as an event log.
- `DittoSignalNext` is `@Sendable` from 5.1.0 and plain in 5.0.3 — version-gate any
  example that hops actors before signalling.

**`DittoDiffer` — what it is, and when it is the wrong tool.**

From `sdk-release-5.1.0:sdks/swift/DittoSwift/DittoDiffer.swift` and `DittoDiff.swift`:

- It is **stateful**. `diff(_:)` compares the passed items against *the last array passed
  to that same differ*, so one differ belongs to exactly one observer and must never be
  shared between observers or reused across queries.
- **The first call always reports every item as an insertion**, because the differ starts
  empty. Initial load is a full population, not an animated insert of N rows.
- Identity is the **`_id` field**.
- It returns `DittoDiff` with `insertions`, `deletions`, `updates` (`IndexSet`s) and
  `moves` as `[(from: Int, to: Int)]` — deliberately the shape `UITableView` /
  `UICollectionView` / `NSTableView` batch updates consume.

| | Use `DittoDiffer` | Skip it |
|---|---|---|
| **UIKit / AppKit** | **Yes — this is what it is for.** Batch updates need exactly these index sets; without them you `reloadData()` on every change, losing scroll position, selection and animation. | Only for small, rarely-changing lists where a reload is genuinely cheap. |
| **SwiftUI** | Rarely. | **Usually skip.** `ForEach` over `Identifiable` data already diffs and animates. Running `DittoDiffer` and then handing SwiftUI an array makes the framework diff a second time — you pay twice and use neither result. Reach for it only when driving something SwiftUI does not diff for you. |

**Costs to state honestly, since the ask is explicitly about memory and CPU:**

- **Memory:** the differ retains the previous item set internally (FFI-side) for the
  comparison, so a diffed observer holds roughly two result sets' worth of identity
  state rather than one. On a large query that is a real, permanent increase for the
  observer's lifetime — not a transient spike.
- **Memory, the sharper constraint:** `diff(_:)` takes `[DittoQueryResultItem]`, so the
  items must still be **materialized** when diffing. That directly conflicts with the
  "extract values and `dematerialize()` promptly" rule elsewhere in the skill. The
  correct order is: diff first, then extract, then dematerialize — and the skill must
  show that ordering explicitly, because the natural reading of the two rules in
  isolation produces code that dematerializes too early.
- **CPU:** an extra comparison pass per callback, on top of the query. For a
  high-churn query delivering frequently, that cost recurs on every delivery — which is
  precisely when `handlerWithSignalNext` should be throttling deliveries anyway. The two
  features are complementary and the skill should show them together.
- **Robustness:** `diff(_:)` decodes its result with `try!`
  (`DittoDiffer.swift:43`) — a decode failure is a crash, not a throw. Worth knowing,
  not worth designing around.

**What the worked example must demonstrate:** a UIKit list driven by
`handlerWithSignalNext` + one `DittoDiffer`, applying `insertions`/`deletions`/`updates`/
`moves` as a batch update, extracting values and dematerializing *after* the diff,
signalling next on every exit path, and cancelling the observer at the controller's
lifecycle boundary. Plus the SwiftUI counterpart that does **none** of this and is
correct because `ForEach` handles it.

### Actors, async work, and UI isolation

- Keep UI-facing state in a `@MainActor` app model, and convert a query result into
  Sendable/value data before crossing a concurrency boundary. The samples will not
  assume that a `DispatchQueue.main` closure is automatically actor-isolated.
- **On 5.0.x, `deliverOn:` is ignored and observer callbacks + Swift concurrency
  crash.** This is the single highest-value version-gated fact in the skill and is
  promoted into `SKILL.md` §6/§8 with its symptom, not buried in the ledger. The
  release notes state the symptom outright —
  `snippets/common-release-notes/5-1-capabilities/swift-specific-changelog.mdx`:
  *"`DittoStore.registerObserver` now dispatches its callback on the queue specified by
  the `deliverOn` parameter, **resolving a crash when used with Swift concurrency**.
  (#SDKS-3856)"*. Source confirms the mechanism: at
  `sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoStore.swift:688-702` the private
  `registerObserver` accepts `deliverOn queue` and never references it — the handler
  goes straight to `dittoStoreObservationHandlerWithSignalNextToFFI`. At
  `sdk-release-5.1.0:sdks/swift/DittoSwift/DittoStore.swift:695-702` it wraps delivery
  in `queue.async { … }`. 4.14.6 honored it
  (`cocoa/DittoSwift/Store/DittoStore.swift`, `deliveryDispatchQueue:`).
  **State the failure mode as a crash, not merely as off-main execution.** On 5.0.x the
  handler must hop to the main actor itself rather than trusting the parameter; an
  observer that looks correct will fault at runtime under Swift concurrency.
- **The `@Sendable` change and the `deliverOn` fix are one change, `#SDKS-3856`**, and
  the skill should present them together rather than as two coincidental 5.1 notes.
- Do not require an actor merely to wrap `Ditto`. The `Sendable` story has **two
  distinct steps**, and conflating them mis-tags what compiles under Swift 6:
  - **5.0 added type conformances** — *"Marked most public types as `Sendable`
    (#17934)"* (`5-0-capabilities/swift-specific-changelog.mdx:26`). `Ditto` and
    `DittoStore` are `Sendable` on both v5 lines (`Ditto.swift:541`,
    `DittoStore.swift:719` at 5.1.0).
  - **5.1 added `@Sendable` to the closure type aliases** — `DittoStoreObservationHandler`,
    `DittoStoreObservationHandlerWithSignalNext`, **and `DittoSignalNext`** (#SDKS-3856).
    Verified at `DittoStoreObserver.swift:20,27`: plain closures at 5.0.3, `@Sendable`
    at 5.1.0.

  So the axis is 5.0-vs-5.1 for closures and v4-vs-v5 for type conformances — not one
  blanket "v5 is Sendable" claim. Note also that
  `5-0-capabilities/additional-improvements.mdx:37` advertises *"Full Swift 6 support
  with Sendable conformance"* for 5.0, which the 5.1 handler fix contradicts; the skill
  must not repeat that claim unqualified. The reference will show actors for
  application-owned mutable async state (token acquisition, serialized work), not as a
  `Ditto` wrapper.
- The auth expiration handler will have a dedicated Swift 6 section: it is async and
  `@Sendable`; it must not mutate UI/controller state directly. The implementation will
  include the compiler-checked actor hop/`await` pattern and the required handler setup
  before starting a server connection.
- Store observers will cover normal automatic signalling and the explicit
  `handlerWithSignalNext` back-pressure form, including cancellation and coalescing.
  Samples will extract data and release `DittoQueryResultItem` materialization before
  doing expensive UI work.

### Combine: a narrow surface, and NOT available for DQL observation

**There is no store-query or DQL-observation publisher in v5.** Enumerating every
public publisher at `sdk-release-5.1.0:sdks/swift/DittoSwift/*+Combine.swift` yields
exactly four: `DittoAuthenticator.StatusPublisher`, `DittoDiskUsage.DiskUsagePublisher`,
`DittoPresence.GraphPublisher`, and `DittoStore.FetchAttachmentPublisher` (with its
`progress()` and `completed()` operators). None observes a query.

This must be stated as a **negative fact** in `references/observers.md`, because the
plausible-looking `store.observePublisher(query:)` does not exist and an agent left to
infer a symmetry with the other three aggregates will hallucinate it. For DQL
observation, `registerObserver` is the only API on every supported line, and bridging
it into SwiftUI/Combine state by hand is the correct, intended pattern — not a
workaround.

The version history runs the opposite way from what a "Combine is cross-version"
reading would suggest: at `sdk-release-4.14.6` there *was* a query publisher,
`cocoa/DittoSwift/Combine/DittoPendingCursorOperation+Combine.swift` `LiveQueryPublisher`,
but it hung off the **deprecated collection API** and carried
`@available(*, deprecated, message: "Use DQL … instead")`. It and `RemotePeersPublisher`
are gone by 5.1.0. So query publishers were removed, never carried forward, and no
sample may use them.

What `observers.md` will therefore say:

- The four surviving publishers, each named, with the hand-rolled `registerObserver`
  bridge as the documented answer for query observation.
- The `@available` annotation is itself version-gated and must be tagged, not quoted
  once: `@available(iOS 13, macOS 10.15, macCatalyst 13, tvOS 13, watchOS 6, *)` at
  4.14.6 and 5.0.3, losing `tvOS 13` at 5.1.0.
- Cancellation differs between the two styles — a `Cancellable` retained by the owning
  scope, versus the observer handles covered in the lifetime rules.
- `attachments.md` keeps `fetchAttachmentPublisher().progress()` as the idiomatic
  progress-reporting path, since that publisher genuinely exists.

### Lifetime and retention rules to make prominent

`SKILL.md` will promote these from reference material into its required lifetime
section, with the exact per-version behaviour verified before wording is finalized:

- Hold one long-lived strong `Ditto` reference at the application composition root;
  do not retain only `store`, `sync`, `presence`, or `auth`, because those are
  aggregate children with weak parent relationships.
- Retain a subscription when it needs explicit cancellation; otherwise document that
  it remains active for the owning Ditto lifetime.
- **Retaining an observer is about being able to cancel it, not about keeping it
  alive** — a distinction the skill must get right because the natural assumption is
  the opposite. Source (`DittoStoreObserver.swift:33-37`): an observer *"will remain
  active until the owning `Ditto` object goes out of scope or `cancel()` is called."*
  Dropping the handle does **not** stop observation; it strands a live observer you can
  no longer cancel, which keeps firing and keeps its closure's captures alive for the
  whole `Ditto` lifetime. Retain store, presence, auth-status and disk-usage observers
  for the scope that consumes them *so that scope can cancel them*; retain an attachment
  fetcher until a fetch completes or is intentionally stopped.
- Cancel/stop at the owning scope's lifecycle boundary, avoid retain cycles in callback
  closures, and distinguish stopping network sync from keeping the local store usable.
- **Do not cache `ditto.sync.subscriptions` or `ditto.store.observers`.** Both are
  *computed* in v5, not stored Swift `Set`s (`swift-v4.mdx:934-938`), so a snapshot
  taken once and held goes stale. Query them fresh at the point of use. This is a
  natural mistake for code ported from v4 and produces no compile error.

### Capability/reference allocation

| Files | Planned coverage and Swift-specific emphasis |
|---|---|
| `setup.md` | SwiftPM/Xcode package product and the XCFramework distribution, toolchain/platform minima, iOS/iPadOS permission strings/background Bluetooth modes, macOS/Catalyst distinctions, and data-protection entitlement. **SwiftPM is the only installation path the skill documents, on every supported line — this is a settled decision, not an open question.** The skill presents one way to add Ditto to a Swift project: add the `getditto/DittoSwiftPackage` package in Xcode, pinned to the target version. Do not document, mention, or footnote alternative dependency managers on any line, and do not re-open this during implementation or review. **The package shape is itself version-gated** and `versions.md` must carry it: `DittoSwiftPackage.template/Package.swift` at `sdk-release-4.14.6` is `swift-tools-version:5.8.1` with **two** library products (`DittoSwift`, `DittoObjC`), where `DittoSwift` is a source target `DittoSwiftWrapper` over two binary targets; at 5.0.3/5.1.0 it is `swift-tools-version:6.0` with a single pure `binaryTarget`. So changing the version pin also changes the product set the Xcode target links. The v4 toolchain floor has no compatibility-page entry at all (`sdk/v4/compatibility/swift.mdx` has no Development Requirements section) and can only be sourced from that manifest. |
| `connect.md`, `transports.md`, `sync.md` | v4 identity versus v5 `DittoConfig`/`open`, persistence directory, authentication handler, `sync.start/stop`, Swift transport-config calls, subscriptions, sync status, and local commits. **CAP-07 is "Sync subscriptions and sync *scopes*" and the scopes half was missing from an earlier draft.** There is no `SyncScope` type in the Swift SDK; the mechanism is DQL `ALTER SYSTEM`, and Swift is one of only two languages with host-language samples on that page. Sources: `sdk/latest/sync/sync-scopes.mdx:68-78` (`ALTER SYSTEM SET USER_COLLECTION_SYNC_SCOPES = :syncScopes`, with a `<Warning>` at `:64` that it **must be called before `ditto.sync.start()`**) and `sdk/latest/sync/using-alter-system.mdx:52,99`. Note the published Swift sample at `sync-scopes.mdx:69-76` calls `await ditto.store.execute(...)` with no `try` on a `throws` method — it does not compile, so the skill must correct it rather than inherit it, and the fixture must compile the corrected form. One 4.14-line transport fact to carry: mDNS failed to advertise/browse with correct info before 4.14.3 (#NETW-883, `sdk/v4/release-notes/swift.mdx`), which is the LAN-discovery failure mode for anyone pinned below that patch. Four connect-time details the migration guide pins down and a sample must respect: `.server(url:)` takes a **`URL`, not a `String`** — a string literal will not compile; that URL is the portal's **`https://` Connect-via-SDK value copied as-is**, never constructed from the database ID and never a `wss://` value; `databaseID` is case-sensitive (uppercase `ID`); and `DittoHTTPListenConfig.webSocketSync` **flipped default from `true` to `false`** in v5, so anything relying on the v4 default must now enable it explicitly. Also carry the v5 `Codable` argument overloads for `registerObserver` and `registerSubscription`, and `DittoSyncSubscription.queryArgumentsCBORData` / `.queryArgumentsJSONData` / `.id` for introspection. |
| `store.md`, `observers.md`, `attachments.md`, `presence.md` | Async DQL with parameters, transactions/indexing/eviction, result decoding and dematerialization, `DittoDiffer` and back-pressure per the dedicated section above (statefulness, one differ per observer, diff-before-dematerialize ordering, the `signalNext` silent-stall trap, and the UIKit-yes/SwiftUI-usually-no split), the callback-versus-Combine routing rule and each form's cancellation, attachment fetcher lifetime and the fetch publisher's `progress()`, presence graph/connection requests. Two v5 additions to cover: `DittoStore.newAttachment(data:metadata:)` accepts in-memory `Data` (v4 was file-path only), and `item.dematerialize()` must be called after extracting from a `DittoQueryResultItem` to free native memory — with the item unusable afterwards, which is an ordering constraint a sample can get wrong silently. |
| `observability.md`, `errors.md`, `testing.md`, `preview.md` | `DittoLogger`, disk usage/stats, concrete `DittoError` recovery, and deterministic offline/temp-directory tests. **CAP-20 is "Preview and platform-specific APIs", not SwiftUI `#Preview`** — an easy misread that would leave the capability empty. The real Swift preview surface, all verified at `sdk-release-5.1.0:sdks/swift/DittoSwift/`: `DittoExperimental` (`DittoExperimental.swift`, self-documented *"Experimental functionality should not be used in production"*), `DittoConfigExperimental.passphrase` (`DittoConfigExperimental.swift`), and `DittoMulticastBetaConfig` / `DittoPeerToPeer.multicastBeta` (`DittoTransportConfig.swift:73`). The multicast beta is 5.1-only and carries three constraints the changelog states and a sample must respect (#SDKS-4471): it is **disabled by default**, supported on **iOS and macOS only**, and on iOS a change requested while sync is active does not take effect until sync is stopped and successfully restarted. **Two further gates the changelog omits and the source states** (`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoTransportConfig.swift:60-72`): on iOS the host app must include `NSLocalNetworkUsageDescription` and be signed with the **restricted `com.apple.developer.networking.multicast` entitlement** (Apple approves it per-app; without it the build cannot ship) — which is CAP-02 `setup.md` material too — and *"This feature is in **private beta** and should only be used in coordination with Ditto support."* No public sample may omit that caveat. Its `DittoConnectionType.multicast` enum case is new in 5.1, so any exhaustive `switch` over connection types is version-gated. Data Streams is Kotlin-only — `sdk/latest/sync/data-streams.mdx` carries only ```kotlin fences — so Swift's Data Streams row is `Support: no` per template Appendix B. Platform exclusions (watchOS/visionOS, and tvOS per the boundary section) belong here too. |
| Additional 5.1 facts from `5-1-capabilities/swift-specific-changelog.mdx` | Route to their owning reference rather than losing them: `DittoPeerOS.tvOS` is **deprecated but retained** so peers on older tvOS SDKs remain identifiable in the presence graph (#SDKS-3944) → `presence.md`, and it means a presence `switch` must still handle the case. The `CBOR` enum and `DittoError.StoreErrorReason.invalidDocumentStructure(cbor:)` / `.nonStringKeyInDocument(key:)` are deprecated and no longer produced (#SDKS-4009) → `errors.md`, which must not teach recovery from errors the SDK stopped emitting. Uncaught exceptions in SDK callbacks re-raise with the original call stack instead of a `SIGABRT` attributed to Ditto (#SDKS-3483) → `observability.md`, since it changes how a crash report reads. **This one is not 5.1-only: the identical ticket ships in 4.14.6** (`sdk/v4/release-notes/swift.mdx:18`) **and in 5.1.0, but not in any 5.0.x release** — a backport that skips the 5.0 line, so it is tagged `4.14.6+ and 5.1.0+`, never "v5". Custom `DITIdentityProvider` implementations no longer stall the SDK on first credential refresh (#SDKS-3623) → `connect.md`, as a 5.0.x failure mode. **DittoSwiftTools has its own version coupling and its own tvOS conflict**, both of which `versions.md` must carry: `swift-v4.mdx:391-397` says Tools **10.0.0** is the first major release supporting DittoSwiftPackage 5, requires **5.0.1 or later**, needs a Swift 6 toolchain, raises targets to iOS 15 / Catalyst 15 / macOS 12, and **removes tvOS support** along with `DittoTvOSTextFieldComponent`; direct `DittoPresenceViewerCore` dependencies must be dropped since Tools 10 bundles those assets. That directly contradicts the 5.1 changelog's *"The tvOS 15+ requirement is unchanged"* for Tools — a second tvOS conflict to resolve in the ledger, not to paper over. Do not infer Tools' platform set or its version floor from the SDK's. `DittoSwiftTools` is a **separate package** (`github.com/getditto/DittoSwiftTools`) with its own platform floor — it will be presented as an optional extra dependency, never as something the SDK dependency brings in, and its 5.1 changes (`DiskUsageInspectorView` added, bundled `DittoSwiftPresenceViewer` removed in favour of Tools' `DittoPresenceViewer`) will be version-tagged. |
| `versions.md`, `best-practices.md`, `examples/minimal-app.md` | Compatibility matrix and storage result; application architecture/lifetime judgement; a tested open → subscribe → observe → write flow. `versions.md` owns cross-version *facts*; it links to the vendored migration guides rather than restating migration *procedure*. |
| CAP-19 (delegated) | **Not authored here.** Per the migration-skill split above, `swift-sdk`'s CAP-19 row is a delegation pointer to the `ditto-v4-to-v5-migration` skill plus the on-disk/store version facts that stay in `versions.md`. Previously scoped as vendored references; that approach is superseded. Retained note for the follow-up issue: the migration skill owns Vendored verbatim from `sdk/latest/migration-guides/swift-v4.mdx` and `swift-dql.mdx` with provenance headers. These own the v4→v5 procedure, the rename/removal tables, both Swift 6 compile traps, the platform-removal blocker, and the entire `DQL_STRICT_MODE` transition including its contact-support instruction. **Loaded only on a migration task** — never on greenfield v5 work, per the routing guard. |

## Version reconciliation work

Before drafting final prose, build a claim ledger from the release tags and docs. Each
entry will record exact release, source path/URL, evidence tier, sample/test location,
and the old-version failure mode when relevant.

**The Swift sources moved twice across the three supported tags.** Verified with
`git ls-tree`:

| Tag | Swift SDK path | Sample app |
|---|---|---|
| `sdk-release-4.14.6` | `cocoa/DittoSwift/` | `cocoa/DittoCarsApp/` |
| `sdk-release-5.0.3` | `sdks/cocoa/DittoSwift/` | `sdks/cocoa/DittoCarsApp/` |
| `sdk-release-5.1.0` | `sdks/swift/DittoSwift/` | `sdks/swift/DittoCarsApp/`, `quickstart/swift/` |

`quickstart/` exists **only** at 5.1.0. Every ledger entry must record the literal path
*at the tag it cites*; a path copied from one tag resolves at neither of the others.

**A file present at a tag is not a shipped public symbol.** The ledger records symbol
visibility, not `git ls-tree` output, because the two diverge in exactly the cases that
matter. Worked example — the 4.14.4 release notes
(`mintlify-docs/sdk/v4/release-notes/swift.mdx:41`, #SDKS-2998) announce
`DittoAttachmentToken`, **`DiskUsage`**, `DiskUsageItem`, `DittoObjCInterop`,
`DittoTransportDiagnostics`, `DittoTransportSnapshot`, `DittoAuthenticationDelegate`
and `DittoError.MigrationErrorReason` for removal in 5.0. Checking files alone gets
these wrong in two distinct ways:

- `DiskUsage` was **renamed exactly as announced** —
  `sdk-release-4.14.6:cocoa/DittoSwift/DiskUsage/DiskUsage.swift:10` is
  `@available(*, deprecated, message: "Renamed to `DittoDiskUsage` in SDK 5.0.")`.
  Comparing the *new* name against the *old* announcement is what makes it look retained.
- `DittoObjCInterop` **was removed from the public API**: `public enum DittoObjCInterop`
  at `4.14.6:cocoa/DittoSwift/DittoObjCInterop.swift:13` becomes bare
  `enum DittoObjCInterop` at `5.1.0:sdks/swift/DittoSwift/DittoObjCInterop.swift:12`.
  The file survives; the symbol does not.
- `DittoAttachmentToken` was **also removed from the public API**: `public class` at
  `4.14.6:cocoa/DittoSwift/Store/DittoAttachmentToken.swift:11` becomes bare
  `final class` at `5.1.0:sdks/swift/DittoSwift/DittoAttachmentToken.swift:9`.
  Corroborated three ways — `5-0-capabilities/swift-specific-changelog.mdx:49`
  (*"`DittoAttachmentToken` class is obsolete and has been removed"*),
  `swift-dql.mdx:742` (*"In v5 a Swift attachment token is a plain `[String: Any]`
  dictionary — there is no `DittoAttachmentToken` type"*), and the public
  `fetchAttachmentPublisher(attachmentToken: [String: Any])` overload at
  `DittoStore+Combine.swift:113` while the token-typed overload at `:123` is `private`.

**All three were removed exactly as the 4.14.4 notes announced.** An earlier draft of
this plan concluded the opposite — that the notes were unreliable and one symbol
survived — which was wrong on every count, and wrong in the direction that would have
had an agent emit a nonexistent type.

So the corrected rule is narrower than "deprecation notes are a claim to verify": the
notes were accurate; the **method** was wrong. Resolve every symbol against its
`public` modifier at the tag (or the DocC JSON), under the name it carries *at that
tag* — `git ls-tree` and file presence prove nothing, because `public class X` becoming
`final class X` in the same file is exactly how removal looks. **Attachments in v5 use
`[String: Any]` tokens**, which `attachments.md` must reflect.

The hosted DocC API reference is the authoritative per-version symbol list.
`sdk/latest/migration-guides/swift-v4.mdx:28-30` documents the lookup protocol: fetch
the parent type's JSON (for example `dittoconfig.json`) and read exact member slugs and
declaration fragments from its `topicSections`, rather than hand-constructing a slug.
The host-path split is **NOT settled — the two docs pages conflict** and the ledger must resolve it with the docs owners:
`sdk/v4/api-reference/swift.mdx:5` uses `software.ditto.live/cocoa/DittoSwift/4.14.6/…`
and `sdk/latest/api-reference/swift.mdx:6` uses
`software.ditto.live/swift/DittoSwift/5.1.0/…`; but `swift-v4.mdx:28` directs the `/cocoa/` form at *"`5.0.1`, `5.0.0`, or **any later
`5.x` release**"* — which includes 5.1.0, where the published reference is `/swift/`.
A skill that repeated the guide's instruction would 404 on its own default version
line. Additionally no 5.0.3 DocC URL is published anywhere in the docs checkout, so for
the 5.0.x line the source tree at `sdk-release-5.0.3:sdks/cocoa/DittoSwift/` is the
primary symbol evidence.

At minimum the ledger will verify:

1. package distribution and platform/toolchain matrix: the SPM/XCFramework
   coordinates (all three supported lines resolve from the same
   `getditto/DittoSwiftPackage` URL), the Xcode 16 / Swift 6.0 v5 floor, 5.1's
   removal of Intel `x86_64` Mac and tvOS, tvOS's availability on 5.0.x, and the 4.14
   macOS documentation discrepancy;
2. v4 legacy identity/collection APIs versus v4 preview config/open APIs versus v5's
   required config/open, authentication, `sync`, and DQL APIs;
3. callback delivery, `@Sendable` annotations, `Sendable` conformances, actor captures,
   explicit queue behaviour, result dematerialization, and 5.1 observer changes;
4. the Combine surface per line — which publishers exist, their `@available`
   annotations, and whether any were added or removed between 4.14.6 and 5.1.0;
5. renamed/removed types and members, each resolved by `public` modifier at the tag per
   the visibility rule above. **Do not reconstruct this from source — `swift-v4.mdx`
   already carries it as tables** (`### DittoConnection Property Renames`,
   `### DittoPeer Property Renames`, `### API Changes`, `## APIs Removed`,
   `## New APIs in v5`). The ledger's job is to spot-check those tables against the
   tags, not to rebuild them. They cover, at minimum: `peerKeyString`→`peerKey`,
   `peerKeyString1/2`→`peer1/peer2`, `osV2`→`os`,
   `isConnectedToDittoCloud`→`isConnectedToDittoServer`, `ditto.activated`→`isActivated`,
   `ditto.appID`→`ditto.config.databaseID`, `ditto.siteID`→ via
   `presence.graph.localPeer`, `observePeers`/`observePeersV2`→`presence.observe(didChangeHandler:)`,
   `DiskUsage`→`DittoDiskUsage`, `DiskUsageItem`→`DittoDiskUsageItem`,
   `DiskUsage.exec`→`DittoDiskUsage.item`, nested `DiskUsageObserverHandle`→standalone
   `DittoDiskUsageObserver`, `DittoLogger.enabled`→`isEnabled`,
   `metadataJSONString`→`metadataJSONData`, and the removals
   (`DittoSwiftError` typealias, `MigrationErrorReason`, `transportDiagnostics()`,
   `DittoTransportSnapshot`, `runGarbageCollection()`, `disableSyncWithV3()`,
   history tracking, `DittoIdentity.manual`, `approximateDistanceInMeters`,
   `queriesHash`, `DittoConnectionPriority`, `DittoAddress`, `DittoRemotePeer`,
   `DittoLogger.setLogFile()`). Note `DittoDiskUsageItem`'s **property** names are
   explicitly unchanged — only the type was renamed, a distinction worth preserving so
   the skill does not invent property renames;
6. the two Swift 6 compile traps the migration guide documents, both of which produce
   errors on code that looks correct and neither of which is discoverable from the API
   surface alone (`swift-v4.mdx:857-888`):
   - `DittoConnection` gains `Identifiable`/`Equatable`/`Hashable`/`Sendable` in v5, so
     `Foundation.filter(_:Predicate)` outranks `Sequence.filter(_:)` and
     `connections.filter { $0.peer1 == localKey }` fails with *"trailing closure passed
     to parameter of type `Predicate<DittoConnection>`"*. The fix is an explicit
     closure parameter type.
   - Retroactive `Sendable` shims written for v4-era Swift 6 code now collide with the
     SDK's own in-module conformance: *"conformance of 'X' to protocol 'Sendable' was
     already stated in the type's module 'DittoSwift'"*. The fix is deleting the shim.

   Both belong in `SKILL.md` §8 anti-patterns with their exact error strings, since an
   agent that has never seen them will otherwise "fix" the wrong thing;
7. **`DQL_STRICT_MODE` — the skill does not discuss it, and delegates it entirely to
   the included migration guide.** See "The skill's audience is new clients" and
   "Including the migration guides" below for the reasoning and the mechanism. The
   ledger's only job here is to confirm no v5 sample emits
   `ALTER SYSTEM SET DQL_STRICT_MODE = …`. One check already done: the **Swift** v5
   playground snippet (`snippets/connect-examples-v5/playground/swift-playground.mdx`)
   is **clean**, so the connect sample inherits nothing. Its siblings are not — the v5
   Flutter and JS playground snippets still execute
   `ALTER SYSTEM SET DQL_STRICT_MODE = false` and the Kotlin one carries it commented
   out — which is a cross-SDK docs inconsistency to raise with the docs owners and to
   avoid repeating when the other eight skills are written. v5.1-only DQL features stay
   delegated to the DQL skill;
8. the persistence-directory default change (`ditto` in v4 → `ditto-{databaseID}` in
   v5). **Source overrides the guide here, and an earlier draft of this plan had it
   backwards.** `swift-v4.mdx:726+` says the new naming applies *"only [to] new databases
   created in v5. v5 does not migrate existing databases to the new structure"*, which
   reads as "an upgrading app silently gets a new empty database". The SDK explicitly
   prevents that. `sdk-release-5.1.0:sdks/swift/DittoSwift/DittoConfig.swift:172-181`,
   in `encode(to:)`, when no explicit directory is set:

   > `// SDKS-3187/SDKS-3539: When the user hasn't set an explicit persistence directory,`
   > `// provide the v4 default path as a legacy fallback so that v4→v5 upgrades`
   > `// don't silently create a new empty database.`
   > `// … Core will check both for databases and prefer the non-legacy path.`

   with `legacyPersistenceDirectory` resolving to `…/documentDirectory/ditto`
   (`:187-191`). Byte-identical at
   `sdk-release-5.0.3:sdks/cocoa/DittoSwift/DittoConfig.swift:171-179`, so it is not
   5.1-only. Per `CONTRIBUTING.md` evidence tiers, source (tier 2) beats docs (tier 3).

   **Do not publish a data-loss warning.** The skill must not tell customers they will
   get an empty database; that claim is false on both v5 lines and would be actively
   harmful in a public repo. What the skill *should* say is narrower and still useful:
   the default directory **name** changed, existing v4 data is found via a legacy
   fallback that prefers the non-legacy path, and setting `persistenceDirectory`
   explicitly removes all ambiguity. The executed test's job is to confirm the fallback
   actually resolves, including the `NSDocumentDirectory` (v4 `Ditto(identity:)`) versus
   `NSApplicationSupportDirectory` (v5 `openSync`) split the same comment describes. Also
   run the upgrade/downgrade test for
   existing data: 4.14.6 → 5.0.3, 4.14.6 → 5.1.0, and the supported rollback path.
   The documented rollback contract is already published in
   `snippets/common-release-notes/5-1-capabilities/upgrade-considerations.mdx` — 5.1
   changes the on-disk index format, a downgrade must route through 5.0.2+ or
   4.14.6+, and composite indexes are replaced by one single-field index per key. The
   skill will **cite that contract** and use the executed test to confirm it, rather
   than re-deriving it from scratch. Where the test cannot confirm a part, the skill
   will mark it unverified instead of inferring an on-disk migration guarantee.

## Executable verification plan

1. Build the test fixture as an Apple app/test target, with version-selected source or
   build settings where the 4.14 legacy and v5 APIs cannot share one declaration. Keep
   the public example a single logical minimal workflow, but make its version branch
   visible rather than hiding incompatible code behind prose.
2. Resolve the published Swift package at exactly 4.14.6, 5.0.3, and 5.1.0. All three
   resolve from the same `getditto/DittoSwiftPackage` SPM URL, so the fixture is one
   SwiftPM graph with the version pin changed between runs. Compile for an iOS/iPadOS
   simulator target and macOS/AppKit (plus Catalyst where the build environment
   supports it). Execute the offline, temporary-persistence workflow on a runnable
   supported target and paste each exact build/run transcript into the example and
   `README.md` verification section. Record the host architecture in the transcript,
   since 5.1 drops Intel Macs and an Apple-silicon-only transcript should not be read
   as evidence about `x86_64`.
3. Add focused tests for one opened instance per persistence directory, subscription
   registration/cancellation, observer callback delivery, `signalNext` coalescing,
   Combine publisher delivery and `Cancellable` teardown (for the four publishers that
   exist), UI/actor handoff compilation, attachment-fetcher cleanup, and the 4.14-to-v5
   persistence scenario. Use deterministic events/expectations, never sleeps.
   **The `deliverOn` delivery-queue assertion must be version-gated**: it passes on
   4.14.6 and 5.1.0 and fails on 5.0.3, where the parameter is ignored. Assert the
   documented behaviour per line rather than writing one assertion that red-lines the
   5.0.3 matrix leg — the 5.0.3 expectation is that delivery is *not* guaranteed on the
   requested queue, which is itself the fact the skill needs to teach.
4. Execute every documented DQL statement in the Swift fixture on its claimed release
   line. Keep all DQL fences tagged `sql` so they remain extractable if the existing DQL
   harness is expanded beyond `skills/dql` later.
5. Run the new SDK-skill structural validator, existing marketplace/scoped-symlink
   checks, `git diff --check`, and the relevant Swift build/test matrix. Record exactly
   what could not be exercised (for example, physical-radio mesh behaviour) as a
   declared evidence gap.

### Splitting the delivery

This is a large unit of work — a nine-SDK structural validator, a three-version fixture
across three Apple targets, an executed cross-version persistence migration, twenty
capabilities, and the plugin/marketplace wiring. Template §12.2 only requires CI to
compile the minimal app **before the third SDK skill merges**, not for the first one.
So the split is:

- **PR 1 (this issue):** the skill, plugin, marketplace row, the `ci.yml` structural
  validator, and the fixture built and run locally with pasted transcripts.
- **PR 2:** `swift-skill-tests.yml` wiring the fixture into the macOS matrix.

Decide this up front rather than discovering it mid-implementation; if PR 1 is kept
whole, say so explicitly in the Linear issue so the scope is a choice and not a drift.

## Implementation sequence

1. Work on `aaronlabeau/da-281-author-swift-sdk-skill` (Linear's canonical branch name
   for DA-281) and copy the approved template.
2. Build the version/evidence ledger and test fixture first; resolve discrepancies
   before writing a claim into the skill.
3. Wire the Swift plugin, marketplace, README row, and the `ubuntu-latest` structural
   CI validation so the new canonical skill is installable from the first commit. The
   `macos-latest` Swift build workflow follows per the delivery split above.
4. Work CAP-01 through CAP-20 in order, writing each reference and filling its
   capability-map evidence/target entry before advancing to the next capability.
5. Write and run the version-specific minimal workflow; add its pasted transcripts and
   persistence-migration results to `versions.md`.
6. Draft `SKILL.md` last from verified conclusions: routing description, exceptions,
   compact default workflow, concurrency, lifetime rules, named anti-patterns, and
   short version table.
7. Review for public-customer suitability, ownership boundaries with the four concept
   skills, version-tag consistency, exact Swift identifiers, and minimal diffs.
8. Run all validation, document remaining non-executable gaps, and prepare the PR
   description with required version, testing, and source evidence.

## Evidence starting points

The implementation will cite the sources actually used, rather than citing this plan
or another skill. The initial verified source set is:

- `mintlify-docs/sdk/latest/{install-guides,compatibility,release-notes}/swift.mdx`
  and `snippets/connect-examples-v5/playground/swift-playground.mdx`;
- **`mintlify-docs/sdk/latest/migration-guides/swift-v4.mdx` (1,059 lines) and
  `swift-dql.mdx` (928 lines) — read these first, in full.** There is no
  `migration-guides/swift.mdx`; these two are the actual migration sources and, between
  them, by far the richest Swift-specific material in the docs. `swift-v4.mdx` is
  effectively a pre-built version ledger: it carries the exact `DittoConfig` initializer
  signature, the complete rename/removal/new-API tables, both Swift 6 compile traps, the
  platform-removal warning, the `Foundation` re-export and `DittoObjC` product changes
  with concrete `.pbxproj` edit steps, the
  `open`-vs-`openSync` decision rule, the DittoSwiftTools version coupling, a migration
  checklist, a common-pitfalls section, and the DocC symbol-lookup protocol. It also
  ships an "AI Agent Prompt" written for exactly this task — worth reading as a
  statement of what Ditto already considers the correct migration behaviour, and worth
  diffing against the skill so the two do not contradict each other in public. Most
  reconciliation items above are answered here; source is for spot-checking, not
  first-pass discovery. It is **research input for `swift-sdk`, and the primary source for
  the separate migration skill** — `swift-sdk` ships none of it, but must not contradict
  it: the initialization, sync and observation forms recommended here are the same ones
  this guide recommends;
- `mintlify-docs/snippets/common-release-notes/`, which is where the Swift release
  notes actually keep their content — `sdk/latest/release-notes/swift.mdx` is mostly
  imports. The two directories do **not** hold the same file set:
  `5-1-capabilities/` has `swift-specific-changes.mdx` and `upgrade-considerations.mdx`;
  `5-0-capabilities/` has **no** `upgrade-considerations.mdx`, and its Swift material is
  `migration-guidance-swift.mdx`, `initialization-swift.mdx`, `terminology-swift.mdx`,
  `schema-free-swift.mdx`, `dql-migration-swift.mdx`, `swift-specific-changes.mdx` and
  `swift-specific-changelog.mdx` — the densest 5.0 Swift sources available.
  **Read `swift-specific-changelog.mdx` on both lines, not just `swift-specific-changes.mdx`.**
  The changelog carries ticket numbers and the precise symptom wording that the
  prose summary drops — `#SDKS-3856` ties the `@Sendable` change to the `deliverOn`
  crash fix, and the 5.1 changelog is the only source for the multicast-beta
  constraints, the `DittoPeerOS.tvOS` retention rationale, and the `CBOR` deprecations;
- `mintlify-docs/sdk/v4/{install-guides,compatibility,release-notes}/swift.mdx` and
  its v4 Swift connect snippet;
- `ditto` tags `sdk-release-4.14.6`, `sdk-release-5.0.3`, and `sdk-release-5.1.0`,
  reading the Swift public sources at the path that exists **at each tag** per the
  three-row path table above, plus the sample apps listed there as first-party usage
  references (noting `quickstart/swift/` exists only at 5.1.0);
- the hosted DocC API reference per version, resolved through the JSON lookup
  protocol described in `swift-v4.mdx` rather than by constructing slugs by hand; and
- the local template contract in `docs/SDK-SKILL-TEMPLATE.md` and its skeleton.

## Approval gate

**Tracking issue: [DA-281](https://linear.app/ditto/issue/DA-281/author-swift-sdk-skill)**
— "Author Swift SDK skill", team *Dev Advocacy & Demo Apps*, project *Ditto AI Skills for
SDK and DQL Development*, milestone *SDK Skills*. The issue moved to this team on
reassignment, which is why earlier drafts of this plan carried an `SDKS-3603` identifier.
That identifier is **retired** — it was never a Dev Advocacy ticket, and `SDKS-…` is the
Ditto SDK *engineering* namespace used by the defect tickets this plan cites as evidence
(#SDKS-3856, #SDKS-3944, #SDKS-4471). Using it for this work would have invited confusion
in a public branch and PR.

Accordingly: branch is `aaronlabeau/da-281-author-swift-sdk-skill` (Linear's canonical
name), this file is `docs/DA-281-swift-sdk-skill-plan.md`, and the PR title and commits
reference DA-281. DA-281's description has been updated to carry this plan's scope,
decisions, verified hazards, and deliverables.

**Related:** DA-280 (Author Kotlin SDK skill) is the sibling issue under the same
milestone. Template and capability-map decisions made here should stay in sync with it.

**DA-281's acceptance criteria are not yet addressed by this plan** and must be folded
into the delivery sequence: *"Passes all Swift-specific test prompts from the validation
harness"* — a prompt-level evaluation, which the compile/run fixture does not provide;
the repo's precedent is `tests/data-modeling/`, which scores live-model output against a
rubric. And *"Reviewed by at least one Swift SDK engineer"* — a named review gate, which
the Implementation sequence currently ends short of.

After you approve this plan, the next action is to update the Linear issue with
the approved plan/status. I will then ask for explicit permission before making any
implementation changes. Until then, this plan file is the only repository change.
