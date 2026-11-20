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

## Flutter SDK skill addition — 2026-11-18

Twelve `flutter_*` cases were added for the new `flutter-sdk` skill: first app, a
`StatefulWidget` observer, a planted-bug `dispose` review, presence, v4 → v5 migration,
three web cases (P2P gate, attachments, an app below `/app/`), Android permissions, hot
restart, a plain Kotlin negative control, and a run with only the `ditto-flutter` plugin
installed. Hosts: Claude Code 2.1.327 (`claude-opus-5-5`, reported the same) and Codex
0.169.1 (`gpt-6.1-sol`; Codex does not report the model it used), isolated as the README
describes. Catalogs were checked first. Codex showed its four vendor builtins plus the
canonical skills, or only `flutter-sdk` and `native-app-config` for the plugin-only case,
or nothing else for the baselines.

The skill changed twice after runs, and each time every skill case was rerun on both
hosts. The results below come from the last tree of 2026-11-18 (digest `388fc349…`; plugin-only
install `62db713e…`) and were scored literally: a criterion passes only when the answer
covers every clause, including clauses for other SDK lines or platforms than the prompt's.
Criteria passed out of the total, with partials or fails in brackets:

| Case | Claude Code | Codex |
|---|---|---|
| `flutter_init_first_query` | 6/6 | 6/6 |
| `flutter_statefulwidget_observer` | 7/7 | 7/7 |
| `flutter_dispose_cleanup` | 5/7 (2 partial) | 5/7 (2 partial) |
| `flutter_presence_peers` | 6/6 | 4/6 (2 partial) |
| `flutter_v4_migration` | 7/7 | 6/7 (1 partial) |
| `flutter_web_p2p_config` | 5/6 (1 partial) | 4/6 (2 partial) |
| `flutter_web_attachments` | 7/7 | 7/7 |
| `flutter_web_base_href` | 7/7 | 7/7 |
| `flutter_android_permissions` | 5/5 | 2/5 (2 partial, 1 fail) |
| `flutter_hot_restart_observer` | 4/7 (3 partial) | 4/7 (3 partial) |
| `flutter_negative_kotlin` | Pass; `kotlin-sdk` only | Pass; `kotlin-sdk` only |
| `flutter_only_plugin` | 5/5 | 5/5 |

- Routing was correct on every run. `flutter-sdk` was used for every Flutter case and
  never for the Kotlin control. In the plugin-only install both hosts read
  `native-app-config/references/apple.md` without error, and every relative link in the
  installed `flutter-sdk` resolves there (checked). There were no timeouts and no policy
  rejections. Codex's nonzero exits were `rg`/`cat` probes for a `pubspec.lock` that the
  workspace does not have.
- Every observer answer registered without `onChange`, held one `changes` listener, and
  cancelled it and then the observer while Ditto was open. None used a `StreamBuilder`
  over `changes`. Both hot-restart answers rejected the static holder, used a debug-only
  per-launch directory with the SDK default in release, and named V2 observers as the
  crash on 5.2.0.
- The partials are omissions, not wrong guidance:
  - Hot restart: neither host gave the 5.1.0 `Ditto.open` hang, the V1 crash on 5.1.0 or
    the web dev-server restart. The prompt was about 5.2.0 on macOS and iOS.
  - Dispose: neither said that assigning `result.items` to a `List` does not compile,
    and neither gave the whole `close()` rule.
  - P2P config: neither said that 5.0.x/5.1.x throw from `updateTransportConfig`. Codex
    also did not say that enabling a transport throws, and gave no AWDL/Wi-Fi Aware note.
  - Codex presence: it did not say that dropping a `PresenceObserver` leaves it running,
    or that the callback fires at once with the current graph.
  - Codex v4 migration: it did not say that `sync.start()` throws without the handler.
  - Codex permissions: it gave no merged-manifest check and no "Ditto never requests"
    statement, and its fail is the missing restart-sync-after-a-late-grant rule, which
    `setup.md` states and Codex read.
- Generated Dart: each Dart block from an answer was checked with the skill's analyzer
  setup (Flutter 3.50.0, ditto_live 5.2.0, `flutter analyze`; format not checked), after
  the normalization recorded in each result. On the final tree every block passed. Lints
  were info-level only: `package:flutter/material.dart` is deprecated in Flutter 3.50,
  plus Codex's `avoid_print`.
- Isolation: one final Codex run (`flutter_presence_peers`) read `ditto_live` source from a
  temp directory outside its workspace, left by an earlier local session. Nothing in the
  workspace referenced that directory, and the trace does not show how the model found the
  path. The run is kept as `flutter-final-excluded`, with the path redacted. The case was
  retried once; the retry read only the skill and is the final record. No other Codex run
  read outside its workspace, apart from baseline runs listing their own fresh
  `CODEX_HOME` skills.
  The cause is a limit of the method: Codex's `--sandbox read-only` blocks writes, not
  reads, so a model can read any file the user can, inside the workspace or not. A fresh
  `HOME` and `CODEX_HOME` hide the usual locations but not other paths on disk, such as
  temp directories. Each Codex trace was checked for reads outside its workspace.
- Claude Code ran with `--setting-sources project` and only the Read, Grep, Glob and Skill
  tools. That this excluded user-level guidance files (`CLAUDE.md` and its includes) is
  not proven. No Claude trace shows any sign of them: none mentions or follows the user's
  shell-command convention.

### Changes after the runs

**Initial tree (`7c251f2e…`).** Three problems showed up:
- Codex's Android answer added manifest entries, capping `ACCESS_FINE_LOCATION` at API 30
  where the plugin declares it through API 32. It requested permissions without
  `DittoSyncPermissions`.
- Claude's `dispose` called `_changes.cancel()` without `unawaited`.
- Claude's web answer called `setOfflineOnlyLicenseToken` a no-op.

The skill now lists the permissions that the plugin manifest declares, with their limits,
and says the app's work is the runtime request. It shows `unawaited` for the listener
cancel in `State.dispose()`, and says that the web license call still verifies the token.
All cases were rerun on that tree (`ab7a26e9…`, the `flutter-intermediate` records). On
it, Claude's base-href `main()` imported only `foundation.dart` and called
`WidgetsFlutterBinding`, as it had on the initial tree.

**Fix round 1.** The `SKILL.md` body was trimmed to 8,977 characters to fit the task
budget of 9,000. `web.md` now notes that a `main()` calling `WidgetsFlutterBinding` and
`runApp` needs `package:flutter/widgets.dart`. Every skill case was then run again on the
final tree.

**Criteria corrected.** Two criteria were corrected to match the skill after the first
scoring:
- `flutter_web_attachments` criterion 5 now also accepts awaiting `fetcher.attachment`,
  which `attachments.md` documents.
- `flutter_hot_restart_observer` criterion 6 now calls the presence-observer crash an
  inference, as the skill does.

The initial and intermediate records were rescored against the corrected criteria. In
them, hot-restart criteria 2, 4 and 6 and Codex's permissions criterion 2 were also
rescored literally, as partial. Other criteria in those records were scored before that
literal rule and were not re-reviewed.

### No-skill baselines

Three cases ran with no skills installed. Summaries are in
[flutter-baseline.md](flutter-baseline.md).
- Both hosts registered the observer with `onChange`.
- Neither knew the `wasmShimUrl` fix for an app below `/app/`. Claude used the v4 identity
  API, and Codex said COOP/COEP headers are required.
- Hot restart came closest: both rejected the static holder. Neither separated V1 from V2
  observers, and neither kept production on the SDK default directory.

There was one run per host, case and tree, plus the one recorded retry. Claude reported
USD 2.21 (initial), 2.24 (intermediate), 2.20 (final) and 0.20 (baselines). Codex does not
report cost. Raw traces stay private.

## Flutter SDK skill rerun — 2026-11-19

Superseded the same day by [the final run](#flutter-sdk-skill-final-run--2026-11-19),
which used the same criteria on the final tree. Kept as the record of that tree.

The `flutter-sdk` skill changed after a three-reviewer pass: `dart:io` on web (it
compiles and throws at run time), a new `release-builds.md` with a diagnosis table for a
release build that cannot sync and an R8 note, an executed sync-scopes sample, 5.x
opening a 4.14.7 default directory in place, `main.dart` and run steps in the minimal
app, `best-practices.md` in the template's nine sections, and evidence notes plus a
documentation-mismatch table in its README.

The Flutter criteria changed too, so these scores are not comparable criterion by
criterion with the tables above:

- Clauses about SDK lines or platforms the prompt does not ask about were removed (the
  5.1.0 hang and the web dev-server restart in the hot-restart case, the 5.0.x/5.1.x
  throw site in the P2P case, and similar).
- `flutter_v4_migration` criterion 7 and `flutter_web_p2p_config` criterion 4 were
  rewritten to match the corrected skill.
- Two cases were added: `flutter_release_no_sync` (a macOS release build that does not
  connect) and `flutter_negative_plain_flutter` (Riverpod and Drift, no Ditto).

All fourteen `flutter_*` cases ran once per host: Claude Code 2.1.328
(`claude-opus-5-5`, reported the same) and Codex 0.169.1 (`gpt-6.1-sol`), isolated as
the README describes, catalogs checked first. Records: `"run":
"flutter-rerun-2026-11-19"` in [results.json](results.json). Criteria passed out of the
total, with partials or fails in brackets:

| Case | Claude Code | Codex |
|---|---|---|
| `flutter_init_first_query` | 6/6 | 6/6 |
| `flutter_statefulwidget_observer` | 7/7 | 7/7 |
| `flutter_dispose_cleanup` | 5/7 (2 partial) | 5/7 (2 partial) |
| `flutter_presence_peers` | 6/6 | 6/6 (retry; first run excluded) |
| `flutter_v4_migration` | 6/7 (1 partial) | 6/7 (1 partial) |
| `flutter_web_p2p_config` | 5/6 (1 partial) | 5/6 (1 partial) |
| `flutter_web_attachments` | 7/7 | 6/7 (1 partial) |
| `flutter_web_base_href` | 7/7 | 6/7 (1 partial) |
| `flutter_android_permissions` | 5/5 | 3/5 (1 partial, 1 fail) |
| `flutter_hot_restart_observer` | 7/7 | 7/7 |
| `flutter_release_no_sync` | 5/5 | 5/5 |
| `flutter_negative_kotlin` | Pass; `kotlin-sdk` only | Pass; `kotlin-sdk` only |
| `flutter_negative_plain_flutter` | Pass; no skill | Pass; no skill |
| `flutter_only_plugin` | 5/5 | 4/5 (1 fail) |

- Routing was correct on every run. `flutter-sdk` was used for every Flutter-with-Ditto
  case, never for the Kotlin control, and no skill was invoked or read for the plain
  Flutter control on either host. There were no timeouts and no policy rejections.
  Codex's nonzero exits were `rg`/`cat` probes for files the workspace does not have.
- The new content was used. Both `flutter_release_no_sync` answers read
  `release-builds.md`, named `Release.entitlements` and the two network keys, gave the
  `codesign -d --entitlements -` check, quoted the `Operation not permitted (os error 1)`
  log lines, and said that nothing throws in Dart. Both migration answers kept the v4
  app ID as `databaseID` and said 5.x opens the v4 store in place.
- The partials and fails are omissions, not wrong guidance. No answer contradicted the
  skill.
  - Dispose (both hosts): neither named `DittoClosedException`. Claude did not say that
    `registerSubscription` throws at the call. Codex did not say that dropped handles
    keep running.
  - v4 migration (both): neither named the directory change itself (`{Documents}/ditto`
    against `ditto-{databaseID}`). Codex also gave no "test on a copy" advice.
  - P2P config (both): the code enabled Bluetooth LE and LAN alike on every native
    platform, with no AWDL or Wi-Fi Aware branch.
  - Codex web attachments: the fetcher was a local that was not kept.
  - Codex base href: it did not say that `Ditto.init()` fails with the default URL.
  - Codex permissions: it named only the Bluetooth permissions the plugin declares and
    gave no merged-manifest check. Its fail is again the restart-sync-after-a-late-grant
    rule, which `setup.md` states and Codex read: the same miss as on 2026-11-18.
  - Codex plugin-only: it did not say that iOS prompts come from the Info.plist strings
    and that Ditto requests nothing itself.
- Isolation: one Codex run (`flutter_presence_peers`) read `presence_graph.dart` of
  ditto_live 5.2.0 from the pub cache outside its workspace. It is kept as
  `flutter-rerun-2026-11-19-excluded` and the case was retried once. The retry listed a
  temp directory outside the workspace for that file name, found nothing, and read only
  the skill; it is the final record. No other run touched a path outside its workspace.
- Tree digests: the full-install runs carry `39ee8ece…`, the final tree, except four
  (`flutter_init_first_query` and `flutter_statefulwidget_observer` on both hosts), which
  started before a one-cell wording change in `release-builds.md` and carry `d38f2aee…`.
  None of the four read that file. The plugin-only install is `e14cee84…`.
- Limits of this rerun: the answers were scored literally by two model reviewers, one
  per host, given the criteria, answers and traces, and then spot-checked by hand; the
  earlier Flutter runs were scored by hand. The Dart in these answers was not analyzed.
  One run per host and case, plus the one recorded retry. Claude reported USD 2.38.

### Migration prompt added — 2026-11-19

The skill then gained `references/migration-v4-to-v5.md`: the AI agent prompt from the
Flutter v4 migration guide, with a table of the points where the released SDK differs.
`flutter_v4_migration` was rerun once per host on that tree (`9fc164fa…`; records
`"run": "flutter-migration-prompt-2026-11-19"`, scored by hand). Both hosts read the new
file and scored 6/7 with one partial, as before: both said to keep the v4 app ID and
pass no `persistenceDirectory`, and neither named the v5 default directory. New in both
answers, from the prompt: the server URL copied from the portal as a `String`, and
strict mode set through `systemParameters`. Claude's observer had no `onChange`, as the
correction table says. The other thirteen `flutter_*` cases were not rerun on this tree.

## Flutter SDK skill final run — 2026-11-19

The current Flutter result. After the migration prompt, the iOS Simulator disk-key note
and the platform tables were added, all fourteen `flutter_*` cases were run again, once
per host, on one tree: digest `57d2339f…` (plugin-only install `4f0c8b6e…`). Hosts and
isolation as above (Claude Code 2.1.328, Codex 0.169.1). Records: `"run":
"flutter-final-2026-11-19"`. Criteria passed out of the total:

| Case | Claude Code | Codex |
|---|---|---|
| `flutter_init_first_query` | 6/6 | 6/6 |
| `flutter_statefulwidget_observer` | 7/7 | 7/7 |
| `flutter_dispose_cleanup` | 5/7 (2 partial) | 6/7 (1 partial) |
| `flutter_presence_peers` | 6/6 | 6/6 |
| `flutter_v4_migration` | 6/7 (1 partial) | 6/7 (1 partial) |
| `flutter_web_p2p_config` | 5/6 (1 partial) | 5/6 (1 partial) |
| `flutter_web_attachments` | 7/7 | 7/7 |
| `flutter_web_base_href` | 7/7 | 7/7 |
| `flutter_android_permissions` | 5/5 | 3/5 (1 partial, 1 fail) |
| `flutter_hot_restart_observer` | 7/7 | 7/7 |
| `flutter_release_no_sync` | 5/5 | 5/5 |
| `flutter_negative_kotlin` | Pass; `kotlin-sdk` only | Pass; `kotlin-sdk` only |
| `flutter_negative_plain_flutter` | Pass; no skill | Pass; no skill |
| `flutter_only_plugin` | 5/5 | 4/5 (1 partial) |

- Routing was correct on all 28 runs, with no timeouts and no policy rejections. No run
  read a path outside its workspace, so nothing was excluded or retried. Codex's nonzero
  exits were probes for files the workspace does not have; one Codex run logged two
  "model is at capacity" reconnects and completed.
- No answer contradicted the skill. The partials and the one fail are omissions:
  - Dispose: Claude did not name `DittoClosedException` or say that
    `registerSubscription` throws at the call. Codex did not say that dropped handles
    keep running.
  - v4 migration (both): neither named the v5 default directory. Both read
    `migration-v4-to-v5.md`, kept the v4 app ID as `databaseID` and passed no
    `persistenceDirectory`.
  - P2P config (both): Bluetooth LE and LAN only, with no AWDL or Wi-Fi Aware branch.
  - Codex permissions: only the Bluetooth permissions were listed, with no
    merged-manifest check, and the restart-sync-after-a-late-grant rule was missing for
    the third run in a row, although `setup.md` states it and Codex read that file.
  - Codex plugin-only: it did not say that Ditto requests nothing itself on iOS.
- Limits: thirteen cases were scored literally by two model reviewers, one per host,
  given the criteria, answers and traces; `flutter_v4_migration` was scored by hand. The
  Dart in these answers was not analyzed. One run per host and case. Claude reported
  USD 2.32.
- One sentence was added to the skill's human-facing `README.md` after these runs (the
  mobile targets run 5.2.0 and 4.14.7 only), so the committed tree differs from
  `57d2339f…` by that sentence. No run read that file, and no agent-facing file changed.

