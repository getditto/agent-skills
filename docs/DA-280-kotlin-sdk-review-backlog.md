# DA-280 kotlin-sdk skill — adversarial review backlog

Five-reviewer adversarial panel run against `da-280-kotlin-sdk-skill` (commits
`6ca5150`, `089f19b`; consensus fixes in `4ee1eca`). Rule: a problem is fixed
only if **≥3 reviewers independently agree**. This file records everything that
fell below threshold, with the evidence, so a later pass can re-triage without
re-running the panel.

Reviewers: ① API accuracy (vs. Ditto source + published jars) · ② Android best
practices (vs. `github.com/android/skills` @ 95ea931) · ③ template compliance
(vs. `docs/SDK-SKILL-TEMPLATE.md`) · ④ copy-paste execution (compiled ~15
samples against `com.ditto:ditto-kotlin:5.1.0`, Kotlin 2.3.21) · ⑤ reader
experience (role-played 6 user tasks).

## Fixed (consensus reached)

- `DittoLog.exportToFile` → `DittoLogger.exportToFile` in
  `references/gradle-project-generation.md` (①④⑤).
- v4 DittoTools coordinate `live.ditto:ditto-tools` →
  `live.ditto:ditto-tools-android` and 5.0.x matrix row filled in
  `references/versions.md` (①③⑤). Verified on Maven Central: only
  `ditto-tools-android` exists under `live/ditto`.

## Below threshold — compile-proven (2 votes: ①④ and ④⑤)

These are certain bugs; they fell below threshold only because only one
reviewer compiled the samples.

1. **`ditto.presence.getPeerMetadataMap()` does not exist in 5.1.0** —
   `references/presence.md:98,103-104`. `javap` on `ditto-kotlin-jvm-5.1.0.jar`
   shows the real `DittoPresence` surface: `getPeerMetadata():
   DittoJsonSerializable$ObjectValue`, `setPeerMetadata(ObjectValue)`,
   `getPeerMetadataJsonString()`, `setPeerMetadataJsonString(String)`,
   `getPeerMetadataJsonBytes()`, `setPeerMetadataJsonBytes(ByteArray)`. The
   sample also claims the method is a "v5 addition" — it is not in v5 at all.
2. **attachments.md:75-101 fetch sample does not compile** —
   `execute(...).use { }` returns `Unit` in v5 (`DittoQueryResult` is not
   `Closeable` on that path) and the fetch parameter is `token =`, not
   `tokenMap =`. Reviewer ④ produced a compiling rewrite using `executeRaw` +
   `token =`; scratch project at
   `/private/var/folders/g0/pr8bp8xj75x8btfr4pjwpktr0000gn/T/opencode/review-scratch/`.

## Below threshold — other findings (1 vote each unless noted)

### ③ Template / spec compliance

- `SKILL.md` `allowed-tools` includes `Bash`; spec §4 mandates exactly
  `Read, Grep, Glob, Edit, Write`. (Deliberate deviation mirroring the Swift
  skill — decide as a policy question across both skills, not per-file.)
- `references/testing.md` claims "Executed" evidence for a JUnit5 skeleton
  that has no test fixture demonstrating a run.
- Pervasive inline v4 asides across the reference tree vs. spec §10 ("v4
  material lives only in versions.md"). Partially supported by ⑤ — flag for a
  structural decision.
- CI not extended with spec §12.1 structural checks (20 CAPs, exact H2s,
  budgets) for the first SDK skill.
- Internal ticket IDs (SDKS-4367 etc.) appear in shipped text; repo is
  intended to become public.
- Root `README.md` install block omits `ditto-kotlin` and cites the stale
  `getditto/claude-code-plugins` repo.

### ② Android best practices (vs. android/skills)

- Blanket "`Dispatchers.IO` for all observer work" judged *defensible, not
  wrong* for mixed blocking-FFI + decode handlers (matches the official
  `jetpack-compose/jetpack-compose-performance` skill), but should note
  `Dispatchers.Default` as the choice for pure-CPU decode.
- `references/transports.md:188-194` uses the deprecated
  `ActivityCompat.requestPermissions` snippet instead of
  `ActivityResultContract` (`RequestMultiplePermissions`).
- `references/observers.md:44-53` headline example uses bare
  `lifecycleScope.launch` instead of `repeatOnLifecycle(Lifecycle.State.STARTED)`.

### ① API accuracy

- Coroutines attribution should be **1.9.0** per Ditto 5.1.0's
  `sdks/kotlin/gradle/libs.versions.toml:47`; the skill says "1.10.x".
  (Behavioral `Dispatchers.IO`-on-Native claim verified for both versions —
  this is an attribution nit.) Note: an earlier source check found 1.10.1 in a
  *test-app* catalog; resolve which catalog is authoritative before editing.

### ⑤ Reader experience

- "the only dependency line you need" (SKILL.md setup claim) is false given
  the kotlinx-serialization / lifecycle-runtime-compose prerequisites used by
  later samples.
- `sync.md` / `store.md` / `transports.md` restate concept-skill semantics
  (also flagged by ③ as a §10-adjacent one-fact-one-home issue).

## Re-triage notes

- If any single finding above gets two more independent reports (e.g. from a
  second panel or user reports), it crosses threshold and should be fixed.
- The two compile-proven items are the highest-value backlog items: both will
  produce wrong code on first use by a customer.
