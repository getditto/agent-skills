# Skill context evaluation results — 2026-10-15

The revised skills were discovered and used on Claude Code and OpenCode/Kimi K3.
This demonstrates useful task routing in these tested configurations. It does not
certify small-context deployments or every generated claim.

| Task | Claude Code | OpenCode / Kimi K3 |
|---|---|---|
| 5.1 JOIN and right-side index requirement | Core pass | Core pass |
| Swift 5.0.3 observer concurrency/lifetimes | Core pass; snippet not compiled | Core pass; snippet not compiled |
| Narrow relay loses non-blue cars | Core pass; stronger final regression pass | Core pass with original count/cloud errors; stronger final regression pass |
| Offline concurrent order model | Core pass; stronger final regression pass | Initial 120s timeout; 240s-budget retry core pass; final regression core pass with ancillary correctness failure |
| Mixed-platform no-AP mesh/configuration | Core pass | Core pass |

Codex CLI could authenticate, but managed approval handling rejected local guidance
reads even after the RTK command convention was enforced. Inherited global guidance
also prevented a clean context comparison. The other four tasks were not run on that
host. No policy bypass was attempted.

## Final-content rerun — 2026-10-27

After the data-modeling corrections and the narrowed `swift-sdk` description, every
case was rerun once per host against the final skill tree (commit `7538627`, digest
`af58eb2c…`). A new `swift_no_ditto` case checks trigger scope: a plain SwiftUI
concurrency task with no Ditto dependency, where `swift-sdk` must not fire.

| Task | Claude Code 2.1.311 (Opus 5.5) | Codex 0.163.0 (`gpt-6.1-sol`) |
|---|---|---|
| 5.1 JOIN and right-side index requirement | Core pass | Core pass |
| Swift 5.0.3 observer concurrency/lifetimes | Core pass; snippet not compiled | Core pass; says "traps" where the skill says "can trap" |
| Narrow relay loses non-blue cars | Core pass | Core pass |
| Offline concurrent order model | Core pass, all seven criteria | Core pass, all seven criteria |
| Mixed-platform no-AP mesh/configuration | Core pass | Core pass |
| Plain SwiftUI task, no Ditto (new) | Pass; `swift-sdk` not invoked | Pass; no skill file read |

- Both order-model answers read the corrected `workflow.md`. Neither repeats the earlier
  residual errors: any offered JOIN uses the complete scoped `parent_id` with an index,
  and neither says an unchanged image is resent on every order edit.
- Trigger-scope control: the same new case run with the pre-`e377ca7` description also
  did not invoke `swift-sdk` on either host. Codex listed files matching `*swift*`
  under that description before answering without them; under the current one it did
  not look. This is one run per variant, so it shows no false trigger, not a measured
  effect of the narrowing.
- The criterion "does not mention Ditto" was reworded after the first Claude run. Both
  Claude answers mention Ditto only to say the installed skills do not apply.
- Codex ran with a fresh `HOME` and `CODEX_HOME` holding only a link to the existing
  auth file. Its catalog was the four vendor builtins plus the five canonical skills,
  and guidance reads succeeded, unlike the initial matrix. The CLI reported a
  hook-trust bypass warning from the local wrapper. Hooks were disabled and none ran.
- A first Claude batch registered the plugin outside the session's working directory,
  so reference reads were rejected and answers fell back to the entry points. That
  batch was discarded; the reported runs had no tool errors.
- OpenCode/Kimi K3 was not available for the rerun. Claude reported USD 0.78 for the
  seven runs; Codex does not report cost.

## Kotlin SDK skill addition — 2026-10-27

With `kotlin-sdk` added alongside `swift-sdk`, two new cases and the Swift observer case
were run once per host against the tree that includes both SDK skills.

| Task | Claude Code 2.1.311 (Opus 5.5) | Codex 0.163.0 (`gpt-6.1-sol`) |
|---|---|---|
| Kotlin observer: `flowOn` jank, retained items, silent observer close | Pass, all five criteria; read `concurrency.md` only | Pass, all five criteria |
| Plain Room/Compose Flow, no Ditto (new, trigger scope) | Pass; `kotlin-sdk` not invoked | Pass; no skill file read, no Ditto mention |
| Swift 5.0.3 observer (routing check with both SDK skills installed) | Pass; `swift-sdk` only | Pass; `swift-sdk` only |

- The `kotlin_observer` case targets the corrected guidance that `.flowOn(Dispatchers.IO)`
  does not move an `observe()` transform off the Android main thread; both answers made
  that point and hopped with `withContext` inside the transform.
- One run per host and case; OpenCode/Kimi K3 was not available. Claude reported USD 0.37
  for the three runs; Codex does not report cost.

### Rerun after the 5.2.0 GA pin flip — 2026-10-27

The Kotlin skill moved from `5.2.0-rc.2` to the released `5.2.0` (pins, "latest GA"
guidance, transcripts). The two Kotlin cases were rerun on the same hosts against that
tree: `kotlin_observer` passed all five criteria on both (Claude read `anti-patterns.md`
only; Codex read the skill), and `kotlin_no_ditto` again invoked no skill and read no
Ditto file on either host. Claude reported USD 0.20 for the two runs.

## Data Streams skill addition — 2026-10-28

With the new `data-streams` concept skill and the `data-streams.md` references in both SDK
skills, two new cases were run once per host against the tree holding all seven skills.

| Task | Claude Code (Opus 5.5) | Codex (`gpt-6.1-sol`) |
|---|---|---|
| Kotlin 5.2.0 sensor streaming with six planted faults (NGN after create, dashed topic, reliability mismatch, stored candidate, connect in presence callback, connect per frame) | Pass, all five criteria; invoked `data-streams`, read `kotlin-sdk/references/data-streams.md` | Pass, all five criteria; read `data-streams` and `kotlin-sdk` |
| Swift 5.1.0 app asking whether Data Streams exist and how to use them | Pass, all five criteria; invoked `data-streams` and `swift-sdk`, read `swift-sdk/references/data-streams.md` | Pass, all five criteria; read `data-streams` and `swift-sdk` |

- Both hosts stated the version floors correctly (Kotlin 5.1.0; Swift 5.2.0 only, via
  `@_spi(PreviewDataStreams)`, undocumented by Ditto) and the preview status, and neither
  invented a 5.1.0 Swift API.
- One run per host and case; OpenCode/Kimi K3 was not available. Claude reported USD 0.36
  for the two runs; Codex does not report cost.

## Final bounded regressions

The same natural relay and order-model prompts were rerun on fresh Claude and Kimi
workspaces after narrow wording corrections. Both relay answers now avoid invented
counts and qualify cloud healing on holdings and permissions. Both order-model answers
use unique IDs for repeatable instances of a SKU. Three of four final regressions pass
the strengthened criteria; Kimi's order-model answer retains ancillary errors:

- It offers an unscoped child JOIN against `_id.order_id` without the right-side
  subfield index prerequisite.
- It says the unchanged inline image is retransmitted on every order edit, confusing
  field-level wire deltas with whole-document merge/storage cost.

Trace review found conflicting reference examples behind both residual errors:
`data-modeling/references/workflow.md:68` still promotes the abbreviated unscoped JOIN,
and `data-modeling/examples/order-management.md:44` claims every edit resyncs the blob.
Those conflict with the corrected entry-point scope/index rule and the correct
field-delta explanation in `references/performance.md`. These examples and the related relational-migration and best-practices guidance were
corrected after the final traces and model-tested in the 2026-10-27 rerun above. This also shows why
preserving prose and code blocks is not a semantic correctness check.

## Evidence and limits

- Versions: Codex 0.160.0; Claude Code 2.1.292; OpenCode 1.19.1.
- Requested models: `gpt-6.1-sol`, `opus[1m]`, `configured-provider/kimi-k3`. Claude reported
  `claude-opus-5-5[1m]`; the Kimi trace records its configured provider/model ID.
- Claude exposed the five canonical plugin skills plus vendor builtins, only
  Read/Grep/Glob/Skill tools, and zero MCP servers. Debug logging reports project
  memory disabled.
- OpenCode native global skills remained in debugger inventory, but an explicit
  skill-name whitelist denied every noncanonical skill. External scans/plugins/MCP,
  shell, writes, web and delegation were disabled. This is permission-filtered
  isolation, not an empty global installation. No forbidden tool calls were observed.
- Models sometimes read entry points directly instead of invoking the host skill
  tool; invocation and actual guidance reads are recorded separately.
- Claude used targeted searches and partial reads in the model task. Kimi often read
  complete relevant references. Routing hints do not guarantee section-only loading.
- Observed per-request input peaks across valid completed calls were about
  9,445–22,878 tokens, including host overhead. Cumulative prompt totals across turns
  are recorded separately. No small context cap was configured and no baseline model
  runs were performed, so these figures are not measured before/after savings.
- The initial Kimi model-review timeout had productive local reads and pending final
  generation. An unchanged-prompt/model/config retry allowed 240s and completed in
  101.62s; preserve both outcomes. This is not a statistical latency study.
- Claude's five primary successful calls reported USD 0.6520152; the two final
  regressions reported another USD 0.2675852. Earlier setup pilot cost is not included
  in those subtotals. Kimi's configured prices were zero, so actual billed cost is
  unknown.
- Generated Swift and extra SQL were not compiled or executed by this smoke suite.
  Core-task passes do not certify all ancillary statements or snippet completeness.

`results.json` preserves 36 primary/retry/regression/rerun records including the timeout
and blocked Codex record. Pilot setup failures and all raw traces remain private.
`cases.json` contains prompts and separate review criteria. `README.md` describes the
reproducible method and command templates without credentials, private endpoints,
user paths or assumptions about global model configuration. The environment-specific
private orchestration script must not be copied into the public repository unchanged.

## Source snapshots

- Initial matrix and successful timeout-extension retry:
  `3f8501ec5c7890b094610e13fda027cb70aba6254f4e2fa53dfe1a6506bca8b6`.
- Four final targeted regressions:
  `10ad14c6454eb7b3cfbbee12637b5cb9587d2847bdebba029379c37ab3ef2f7f`.
- 2026-10-27 final-content rerun (commit `7538627`):
  `af58eb2c189c0e74ab8c71f7702711bad52c4e5f4f3387ae99336c4c6a5debfe`; old-description
  control `be13e2f437cd9d732e156877c0debf9fce2842189086a4f5cf63e647ce0a67e0`. The rerun
  hashes sorted relative paths plus per-file SHA-256, so compare its digests only with
  each other.

Every result records its own digest. Subsequent wording or static example corrections
must be described as after these snapshots; these runs do not certify the exact final
working-tree bytes.

## Best-practices alignment — 2026-11-14

Descriptions for `write-dql`, `data-modeling`, `sync-subscriptions`,
`ditto-mesh-networking`, `data-streams`, `js-sdk`, `swift-sdk` and `kotlin-sdk` were
rewritten to say what the skill does (after any `Use ONLY for` gate) and to drop SDK
release lists. `write-dql` gained a workflow (version from build files, field grounding,
parameters, plan check, destructive-statement confirmation). Eleven cases were added for
the concept skills: four DQL, three subscription (one negative), two mesh (one negative)
and two Data Streams (one boundary). All 21 cases ran once per host; the four DQL cases
were rerun after the final workflow wording.

Hosts: Claude Code 2.1.325 (`claude-opus-5-5`), Codex 0.167.1 (`gpt-6.1-sol`, fresh
`HOME`/`CODEX_HOME`). Routing was correct on every run: each case invoked or read the
expected skill, and the four no-Ditto/boundary controls (`swift_no_ditto`,
`kotlin_no_ditto`, `subs_negative_kafka`, `mesh_negative_zigbee`) invoked no skill and read
no Ditto file on either host. No tool errors.

| Case | Claude Code | Codex |
|---|---|---|
| Existing ten cases | Core pass on all | Core pass on all |
| `dql_missing_field` (new) | Pass, all criteria | First run missed parameters; final rerun pass |
| `dql_join_version_gate` (new) | Pass | Pass |
| `dql_destructive_delete` (new) | Pass | First run: no confirmation, trailing `;`; final rerun asks for confirmation but omits the explicit DELETE-is-mesh-wide contrast |
| `dql_boundary_model` (new) | Pass; routed to `data-modeling` | Pass; routed to `data-modeling` |
| `subs_rejected_query` (new) | Pass | Core pass; does not mention splitting the collection |
| `subs_restart` (new) | Pass | Pass |
| `subs_negative_kafka` (new) | Pass; no skill | Pass; no skill file read |
| `mesh_ios_lan_discovery` (new) | Pass | Pass |
| `mesh_negative_zigbee` (new) | Pass; no skill | Pass; no skill file read |
| `ds_handshake_timeout` (new) | Pass | Pass |
| `ds_negative_doc_sync` (new) | Pass | Pass (read `sync-subscriptions`) |

- The full run's digests are `473f4689…`/`9fc76412…` (a `write-dql/README.md` table edit
  landed mid-run; no case read the README). The DQL rerun digest is `03d73147…`.
- One run per host and case. Claude reported USD 2.74 for the full run and USD 0.46 for
  the rerun; Codex does not report cost. Generated snippets were not compiled.

### Follow-up: stubs, version claims, concept workflows, JS cases — 2026-11-14

Stub sections in `write-dql` and the Swift minimal-app example were removed and their links
retargeted; blanket "works identically on …" and "all supported versions (…)" claims now
name 5.2.0 (each backed by the harness passing those examples on 4.14.6, 5.0.3, 5.1.0 and
5.2.0); a searched-`CASE` note that wrongly claimed 4.14.x support was corrected.
`ditto-mesh-networking`, `sync-subscriptions` and `data-streams` gained trigger lists and
copyable diagnosis checklists. Five JS platform cases were added (Expo Go, Next.js SSR,
Electron, bare RN Android permissions, and a plain React negative control).

All 26 cases ran once per host (Claude Code 2.1.325 `claude-opus-5-5`, Codex 0.167.1
`gpt-6.1-sol`) against digest `9caba082…`. Routing was correct on every run; the five
negative controls invoked no skill on either host; no tool errors.

| Case | Claude Code | Codex |
|---|---|---|
| Earlier 21 cases | Core pass on all | Core pass on all |
| `js_expo_go` (new) | Pass | Pass |
| `js_next_ssr` (new) | Pass | Core pass; omits the memory-only storage note |
| `js_electron` (new) | Pass | Pass |
| `js_rn_cli_permissions` (new) | Pass | Pass |
| `js_negative_react` (new) | Pass; mentions Ditto only to say the skills do not apply | Pass |

- Ancillary gaps repeated this run: neither host mentioned splitting the collection in
  `subs_rejected_query`, and Codex's `dql_destructive_delete` again asked for
  confirmation without contrasting `DELETE`'s mesh-wide effect.
- One run per host and case. Claude reported USD 3.10; Codex does not report cost.

### SDK entry points under the 10,000-character target — 2026-11-14

`kotlin-sdk` (11,477 → 9,626 characters) and `swift-sdk` (10,775 → 9,944) moved detail
that already lives in their references (threading table, full anti-pattern list, release
resolution procedure, routing caveats) out of SKILL.md. Every version mention was kept
(22 and 24, before and after), as were both version-difference sections. The six SDK cases
ran once per host against digest `8a27a090…`: routing correct, negative controls invoked
no skill, and all core criteria passed on both hosts. Claude reported USD 0.84.

### Supported versions restored to descriptions — 2026-11-14

The supported SDK range was put back into the six descriptions that originally carried it
(`write-dql`, `data-modeling`, `sync-subscriptions`, `js-sdk`, `swift-sdk`, `kotlin-sdk`),
and the validator rule rejecting release numbers in descriptions was dropped: customers
span 4.14 LTS and 5.x, and the description must say which lines a skill covers. All 26
cases ran once per host against digest `01704287…`: routing correct on all 52 runs, the
five negative controls invoked no skill, no tool errors. Codex's `dql_destructive_delete`
answer this time named the local/mesh-wide difference but did not ask for confirmation
(it did in the previous run); one run per host, so treat that as variance to watch.
Claude reported USD 3.12.

## C# SDK skill — best-practices alignment, 2026-11-15

`csharp-sdk` was brought in line with the conventions above: a description that says what
the skill does after the `Use ONLY for` gate and names 4.14.x, 5.0.x, 5.1.x and 5.2.0; the
Swift/Kotlin `SKILL.md` layout (reading instructions, related-skill table, condensed
latest-version note, one-line anti-patterns, `Task | Read` reference table); generated
C# blocks via `scripts/sync-snippets.py`; tables of contents on long files; and no links
into this repository. Three cases were added: a negative control (`csharp_no_ditto`, a
plain ASP.NET Core background-service task) and two cases for guidance added from the
drive-through sample builds (`csharp_maui_xcode27`, `csharp_late_subscriber`). The two
existing C# cases had not been run before; this is their first recorded result.

All five C# cases ran once per host (Claude Code 2.1.325 `claude-opus-5-5`, Codex 0.167.1
`gpt-6.1-sol`, fresh `HOME`/`CODEX_HOME`) against digest `3400979b…`. Routing was correct on
every run: each positive case used `csharp-sdk`, and `csharp_no_ditto` invoked no skill and
read no Ditto file on either host. No tool errors.

| Case | Claude Code | Codex |
|---|---|---|
| `csharp_net48` | Core pass: x64/Prefer32Bit, Ditto on the startup exe, packages.config kept, 5.0.2 fix, C# 7.3 syntax, `Task.Run` around store calls, BeginInvoke dispatch, deferred FormClosing; no explicit `Main` shown | Core pass on the same points; omits the 5.0.2 note; no explicit `Main` shown |
| `csharp_native_platforms` | Pass | Pass (also read `js-web` and `native-app-config` for the browser and Android-permission parts) |
| `csharp_no_ditto` (new) | Pass; no skill, says the Ditto skills do not apply | Pass; no skill file read |
| `csharp_maui_xcode27` (new) | Pass: `net11.0` for Xcode 27, workload update does not help, generator, Mac Catalyst 17.0, scene manifest and `SceneDelegate`, 5.2.0 floor, permission sequence | Pass on the same points |
| `csharp_late_subscriber` (new) | Pass: observer delivers once then on change; cached snapshot (`TaskStore.Current`) or per-consumer observer; UI-thread dispatch and DTOs | Pass on the same points |

- One run per host and case. Claude reported USD 0.97 for its five runs; Codex does not
  report cost. Generated snippets were not compiled.
