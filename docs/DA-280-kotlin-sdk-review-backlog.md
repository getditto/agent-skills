# DA-280 kotlin-sdk skill — adversarial review backlog

## Source-validation sweep (user-requested, all claims vs Ditto source)

Six auditors checked every load-bearing claim in the skill against the
`sdk-release-5.1.0` and `sdk-release-4.14.7` source trees plus the published
jars/AARs (~300 claims verified). All source-proven FALSE claims were fixed;
each fix below names the decisive source evidence:

- **observers.md coroutine-scope hazard was inverted** — cancelling the scope
  passed to `DittoFactory.create(config, coroutineScope=…)` does NOT kill
  observers: `InternalDittoResource.kt:39` appends an *unparented*
  `SupervisorJob()`, detaching the user's Job. Only `ditto.close()` cleans up.
- **observers.md "finally before signalNext"** is 5.1.0-only; 5.0.3 re-armed
  before closing (the memory rule itself holds on both).
- **observers.md differ ownership** — created via `ditto.createChild` (child of
  the Ditto instance), closed in the observer's `onClose`
  (`InternalDittoStore.kt:296-298`).
- **observers.md `dematerialize()`** frees the Kotlin-heap materialized value
  (`materializedValue = null`), not native memory.
- **presence.md 128 KB -> 4 KB** — `peerMetadataMaxSizeInBytes = 4096`
  (`InternalDittoPresence.kt:47`), enforced via FFI; 128 KB is the separate
  `smallPeerInfo.metadata` limit (`DittoSmallPeerInfo.kt:45`). Docs page wrong.
- **presence.md v4 `peer1`/`peer2`** are `DittoPeerKey`, not `DittoAddress`
  (v4 `DittoConnection.kt:13,17`).
- **presence.md `.toDittoJson()`** has only `Map<String,String>` /
  `Map<String,Int>` / `Map<String,DittoJsonSerializable>` overloads; generic
  maps need `toDittoJsonOrThrow()` (serializationHelpers.kt:84-99).
- **transports.md / connect.md websocketUrls** — `Connect.websocketUrls` EXISTS
  in v5 (`DittoTransportConfig.kt:411,441`, both jars); only the
  need-to-add-the-cloud-URL workflow is gone.
- **versions.md / preview.md Data Streams floor** — the full surface ships in
  the 5.0.3 jar; docs name 5.1.0 as the requirement, KDoc still warns
  closed-preview. Matrix row and floor statement hedged accordingly.
- **connect.md v4 store pickup** — a default-path v4 store IS picked up
  (`legacyPersistenceDirectoryPath`, `InternalDittoFactory.kt:64-76`); explicit
  path only needed for custom v4 directories.
- **connect.md/sync.md `sync.stop()`** declares no `@Throws` (`DittoSync.kt:48`)
  — the sample's try/catch could never fire; removed.
- **connect.md `logout` cleanupFn** is called synchronously BEFORE logout
  completes (`DittoAuthenticator.kt` KDoc), not after.
- **store.md v4 transaction enum** is `Commit`/`Rollback` — no `Abort`
  (Swift-ism inherited from the migration guide); v4 also had a generic
  value-returning overload.
- **attachments.md `store.attachmentFetchers`** exists since v4.6.0
  (`@since 4.6.0`, v4 `DittoStore.kt`), not "new in v5".
- **observability.md v4 `exportToFileBlocking(path: String): BigInteger`**
  DOES take a path since 4.8.0 (v4 `DittoLogger.kt:167`) — migration guide
  wrong about the v4 baseline.
- **setup.md consumer-rules rationale** — the SDK's internal AARs DO bundle
  consumer rules since 5.0.1 (`proguard.txt` in `ditto-internal-android` /
  `ditto-cinterop-android`, verified in the published AARs); the two
  install-guide rules remain required for the public facade + rustls verifier.
- **Error-string exactness**: backtick `INSERT` (core/query/src/errors.rs:11),
  backtick `ditto-binaries` (NativeLibraryLoader.kt:135), trailing period on
  "Query result item has already been closed."
  (InternalDittoQueryResultItem.kt:115), backticks in "attachment property
  `metadata` is invalid" (crates/ditto-types/src/attachment_handle.rs:30).
- **store.md `mutatedDocumentIds().first()`** prints the CBOR wrapper, not
  `"123"` — sample now unwraps with `.stringOrNull`.
- **sync.md commitId sample** printed `null`, never `1548` (value captured
  pre-commit); rewritten to say so and point at the post-commit read.
- **errors.md** reason-less subclass list now includes `DataStreamsException`
  (DittoException.kt:103 — no public `reason`).
- **SKILL.md** "or is finalized" removed (no finalizer path in v5 Kotlin);
  description error string now exact.

Several falsehoods were inherited verbatim from Ditto's own docs/migration
guide (128 KB, `Abort`, exportToFileBlocking path, websocketUrls removal,
`getPeerMetadataMap()`) — candidates for upstream doc reports.

Unresolved tension (left as-is, docs-backed): `Connect.Server.url` — the
migration guide says paste the portal's https URL; the `DittoConfig.kt` KDoc
example shows `wss://YOUR-APP.ditto.live`. The skill follows the migration
guide.

## Round 2 (2-vote consensus rule, panel re-run independently)

Five fresh reviewers (API accuracy, Android best practices vs `android/skills`,
spec compliance, copy-paste execution, reader experience), each instructed not to
read this backlog. Fixed in the round-2 commit (each with ≥2 independent votes,
some far over):

- **attachments.md fetch sample** (①④⑤): `execute(...).use{}` → `executeRaw(...).use{}`,
  `tokenMap =` → `token =` (compile-verified 5.1.0; the docs page's own snippet is
  v4-shaped and does not compile). CAP-12 evidence upgraded `docs-sample` → `source`.
- **presence.md `getPeerMetadataMap()`** (①④): method does not exist in 5.0.x/5.1.0
  (source + javap); removed, with a pointer to the real surface. The phantom traces
  to Ditto's own migration guide — worth reporting upstream.
- **Kotlin toolchain floor** (①②④): "artifacts embed 2.3.x metadata" was false —
  jars carry metadata 2.0.x (5.1.0) / 2.1.x (5.0.3), which is what actually breaks a
  2.0.x compiler. versions.md/setup.md/gradle-project-generation.md now state the
  true mechanism and the AGP 9 built-in-Kotlin rule (no `org.jetbrains.kotlin.android`
  on AGP 9; v5-on-Android flagged as not-yet-executed).
- **ProGuard rules** (②④⑤): `setup.md` / `gradle-project-generation.md` / `errors.md`
  omitted `-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }`
  (present in testing.md and the install guide) — minified `Connect.Server` TLS would
  break. All three files now carry both rules + the vendor-mandated-broad-rule caveat.
- **testing.md evidence honesty + runtime trap** (③④): added real fixture
  `tests/kotlin-sdk/minimal-app/src/test/kotlin/DittoStoreTest.kt` (2 tests green on
  5.0.3 and 5.1.0); documented dependency block now includes required `kotlin("test")`
  and coroutines-test 1.10.2; observer test moved from `runTest` to `runBlocking`
  with the executed `TimeoutCancellationException … _virtual_ time` explanation.
- **§12.1 structural checks** (prior ③ + ③): added a checker and wired it into
  `.github/workflows/ci.yml` (the spec's "same PR as the first SDK skill"
  requirement). At merge, main's `scripts/validate-sdk-skills.py` superseded this
  branch's checker. Negative-tested against mutated skill copies.
- **observers.md headline examples** (②⑤): shape 1 `registerObserver` now carries the
  mandatory try/catch; shape 2 `observe()` uses `repeatOnLifecycle(STARTED)`; shape 3
  `collect()` hops to `Dispatchers.IO` instead of doing heavy work on the handler's
  (Android main) dispatcher. The duplicated try/catch block was merged out to hold
  the 400-line budget.
- **`.development()` Swift-ism** (④⑤): gradle-project-generation.md rule 7 now says
  `DittoAuthenticationProvider.development()` (valid Kotlin).
- **Internal ticket IDs removed** (prior ③ + ③): SDKS-4367 / SDKS-3944 / #22500 /
  SDKS-4471 / SPO-941 stripped from observers/presence/preview; doc citations kept.
- **kotlinx-serialization + lifecycle-runtime-compose prerequisites** (prior ⑤ + ⑤):
  setup.md's "only dependency line" now lists the two non-Ditto additions the samples
  assume.
- **Coroutines attribution** (prior ① + ①): "1.10.x" → 1.9.0 (Ditto's own
  libs.versions.toml) + 1.10.2 (harness); both verified to have functional Native
  `Dispatchers.IO` (`DefaultIoScheduler`).

## Below threshold in round 2 (1 vote each — not fixed)

- ③ `allowed-tools: Bash` in SKILL.md frontmatter (spec §4 mandates without) —
  deliberate, mirrors Swift skill; decide as cross-skill policy.
- ③ pervasive inline v4 asides outside versions.md (spec §10 "one fact one home").
  Structural decision; ⑤ noted some duplications but did not flag them as
  reader-impacting.
- ③⑤ concept-material restatements in sync.md/store.md/transports.md/testing.md
  (mesh capability matrix, subscription query rules, EVICT semantics) vs spec §1.
- ① presence.md "128 KB metadata limit" — SDK enforces **4 KB**
  (`InternalDittoPresence.kt:47`, `DittoPresence.kt` KDoc); docs page says 128 KB.
  High-confidence source-verified, but only ① reported it. Likely worth fixing on
  the evidence regardless of votes.
- ① transports.md/connect.md "no `connect.websocketUrls` in v5" — the API exists in
  5.1.0 (`DittoTransportConfig.kt:411,441`); the *workflow* guidance is right, the
  nonexistence claim is not.
- ① preview.md "Data Streams requires 5.1.0" — the surface is present in the 5.0.3
  jar (usability there untested).
- ② transports.md permission flow splits legacy `requestPermissions` (no result
  handler) from a never-launched ActivityResult launcher; no rationale/permanent-
  denial path (android-permissions-security 3-state flow).
- ② gradle-project-generation.md "prefer copying fixtures" → android-app fixture
  models Activity-scoped `Ditto` + raw `Thread` in `onCreate`, contradicting
  best-practices.md; no v5 Android fixture exists.
- ②④ fixture pins compileSdk 35 while skill text says 36.
- ③ examples/minimal-app.md 5.0.3 leg has no pasted transcript (§12.2).
- ③ README CAP-17 `inference` row lacks an inline path-and-ref per §7.
- ③ "currently only accepts"/"currently rejects" time-relative language
  (attachments.md:30, errors.md:115).
- ③ lowercase placeholders (`"your-database-id"`, `"your-token"`) vs §9 rule 7.
- ③ SKILL.md §8 performance symptoms lack measured numbers/symbols (§9 rule 4).
- ⑤ store.md/observers.md accessor tables omit `uLongOrNull` etc. that sync.md uses.
- ⑤ transports.md/preview.md duplicate the foreground-service manifest verbatim.
- ⑤ "Query result item has already been closed" quoted with/without trailing period
  across files (errors.md claims exactness).
- ⑤ versions.md:160 cryptic "`false`/V6" phrasing near the strict-mode guidance.

## Round 1 (3-vote consensus rule) — historical

Fixed: `DittoLog.exportToFile` → `DittoLogger.exportToFile`; v4 DittoTools
coordinate `live.ditto:ditto-tools-android`; versions.md 5.0.x matrix row.
Round-1 detail preserved in git history (commit cdcb627's version of this file).
