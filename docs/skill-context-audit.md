# Skill context audit

This records the audit snapshot at commit `1c33670`. Later Swift workflow work adds
references/assets; use the validator context report for the current inventory.

Updated 2026-10-15 after independent adversarial review. The baseline is commit
`3885ed1`; scope is all five canonical skills, their references/examples/READMEs,
plugin discovery names, the DQL agent prompt, and shared authoring checks.

## Review findings and fixes

| Finding | Resolution | Evidence |
|---|---|---|
| Contents lists do not guarantee partial reads | Split the ten oversized resources at topic boundaries. Every skill Markdown file is now ≤20,000 characters even when read in full. Entrypoints link directly to topic files. | Full inventory and CI size checks; live reference-read traces described below |
| DQL directory and activation name differ | Renamed canonical directory and plugin entry to `write-dql`; retained activation key and plugin name `ditto-dql`; removed the validator exception. | Canonical name checks, all five plugin entries checked, native Claude/OpenCode activation trials |
| Budgets could be mistaken for model limits | Explicitly distinguish repository policy, approximate estimates and observed behavior. | Budget interpretation below; no claim that the original files exceeded provider limits |
| Cross-host behavior was untested | Added representative live tasks and recorded outcomes and blockers. | [Host evaluation method and cases](../tests/skill-context/README.md) |

## Entry-point cost

Whole-file characters include frontmatter. Approximate tokens use characters ÷ 4;
these are not tokenizer measurements and do not guarantee fit on any model.

| Skill | Baseline characters | Current characters | Approx. current tokens |
|---|---:|---:|---:|
| [data-modeling](../skills/data-modeling/SKILL.md) | 14,603 | 6,869 | 1,717 |
| [ditto-mesh-networking](../skills/ditto-mesh-networking/SKILL.md) | 16,397 | 6,897 | 1,724 |
| [swift-sdk](../skills/swift-sdk/SKILL.md) | 14,104 | 9,773 | 2,443 |
| [sync-subscriptions](../skills/sync-subscriptions/SKILL.md) | 10,044 | 4,785 | 1,196 |
| [write-dql](../skills/write-dql/SKILL.md) | 6,430 | 8,016 | 2,004 |

Combined body size is **58,884 → 34,383 characters (42% smaller)**.
This sum describes possible multi-skill activation cost, not discovery overhead.
All five descriptions remain below 500 characters. The DQL agent prompt is 1,687
characters versus 10,370 at baseline; it routes to maintained skill guidance.

## Resource organization

The skill tree contains **85 Markdown files**. The largest is
`skills/swift-sdk/README.md` at **19,800 characters**. No size warnings are waived.

- DQL SELECT, JOIN, planner hints, diagnostics, string/date functions, compatibility,
  model patterns and worked reads/mutations have separate topic files. Existing index
  filenames and section headings route readers to the relocated detail.
- The Swift minimal program stays intact and byte-identical to its compiled fixture;
  dependency/run/output notes moved to a directly linked reference.
- Presence/Combine/patch compatibility notes are separate from core Swift version guidance.
- The canonical skill and plugin entry use `write-dql`. The executable harness keeps
  its historical `tests/dql` path; it is not a discovered skill.

The new files reduce the cost of whole-file reads. They do not force models to select
only relevant resources or stop them from reading multiple files on a complex task.

## What the budgets mean

These are conservative **repository authoring policies**, not measured failure
thresholds or provider guarantees:

| Surface | Target | Repository hard limit |
|---|---|---|
| Description | ≤500 characters | 1,024 characters |
| SKILL.md body | ≤10,000 characters | 12,000 characters |
| Supporting Markdown file | One focused topic or intact program | 20,000 characters |

Supporting files above 8,000 characters or 200 lines need linked contents. SDK
references also retain their 800-line ceiling. A contents list cannot excuse an
oversized file. The negative controls in `tests/skill-context/test_contract.py`
exercise this distinction and the strict name-directory rule.

**The original entry points were all below 500 lines and, using the rough chars/4
estimate, below the specification's recommended 5,000 tokens.** No actual tokenizer
counts or original provider-limit failures were established. The rationale is reducing
avoidable consumption when user code, tools and several skills share context.

[Codex skill loading](https://learn.chatgpt.com/docs/build-skills),
[Claude Code supporting resources](https://code.claude.com/docs/en/skills),
[OpenCode discovery and naming](https://opencode.ai/docs/skills/) and the
[Agent Skills specification](https://agentskills.io/specification#progressive-disclosure)
support progressive loading. The particular character limits above are repository choices.
[Kimi K3](https://github.com/MoonshotAI/Kimi-K3) advertises a million-token context;
it is not evidence of a small advertised window. Effective deployment budgets vary.

## Corrections found by live tasks

The smoke review found narrow semantic gaps beyond file sizing. Subscription
guidance no longer claims cloud connectivity always avoids relay gaps: the server
must hold the missing documents and be permitted to deliver them. Numeric topology
counts are explicitly illustrative. Model-design guidance now preserves full scoped
parent identities in references/joins, requires an index for right-side subfield
joins, and distinguishes repeated SKU instances from unique entity IDs. These are
targeted corrections; generated app code is not thereby compiler-verified.
The final trace review also found conflicting examples promoting partial parent
identities and claiming unchanged blobs retransmit on every edit. Corrected the
workflow, order and relational-migration examples and best-practices wording:
initial transfer/blob changes send the value; unrelated edits still incur whole-document
merge/storage work. The DQL indexing reference also records the verified 5.1.0
whole-object reference case instead of ruling out all MAP indexing. These last
source corrections were not model-retested.

| Host/model | Observed result |
|---|---|
| Claude Code / Opus | All five primary core tasks passed; both targeted final regressions passed |
| OpenCode / Kimi K3 | Four primary tasks completed; modeling timed out at 120s, then passed core criteria on retry. Final relay passed; final modeling retained ancillary errors traced to the conflicting examples above |
| Codex / gpt-6.1-sol | Local reads blocked by managed approvals; no valid model-task pass |

See the [reviewed results and limitations](../tests/skill-context/SUMMARY.md).
No small context window was configured; these runs do not establish universal fit.

## Preservation and executable verification

- The structural split preserved pre-fix fenced blocks. The later semantic fixes
  intentionally changed four modeling/example blocks (including the output template);
  all other blocks remain byte-identical as a multiset. DQL-skill harness queries and Swift program
  code are unchanged. Preservation alone does not certify semantic correctness.
- Migrated all **276 DQL block IDs**, including override/ignore/golden keys. Catalog
  regeneration retains **258 cases and 250 golden assertions**. Primary queries,
  version/error expectations and goldens are unchanged.
- Reordering exposed one existing cleanup leak: the auto-ID `INSERT … RETURNING`
  review remained in the store and changed a later expected row count. Added explicit
  cleanup for that inserted review; kept the expected row count at three.
- Real DQL SDK runs: **4.14.6: 205 PASS + 53 expected failures; 5.0.3: 222 + 36;
  5.1.0: 252 + 6**. No failures remain. The 5.1 run was repeated after the cleanup fix.
- Both corrected scoped JOIN examples pass SDK 5.1.0 regression checks with duplicate
  parent numbers in different stores/teams; cross-scope matches are excluded.
- Structural validation passes without warnings; five context guard tests and the
  embedded CI packaging checks pass; `git diff --check` passes.
- Swift examples still pass the fixture byte-identity validator. The Swift runtime
  matrix was not rerun because Swift code was unchanged.

The first DQL attempt inherited `NO_COLOR=1`, which the SDK core rejects. The recorded
passing runs cleared that variable; this environment failure is not counted as a pass.

## Repeatable checks and remaining limits

```bash
python3 scripts/validate-sdk-skills.py --context-report
python3 tests/skill-context/test_contract.py
cd tests/dql
# Clear a non-boolean NO_COLOR inherited from wrappers before running the SDK.
env -u NO_COLOR npm test
```

For live discovery, reference reads, model identity, elapsed time and reported usage,
see [the host evaluation record](../tests/skill-context/README.md). Host-reported input
usage aggregates requests and can include cached tokens; it is not peak context or
an exact attribution to skill files. Comparisons across hosts are not controlled
before/after benchmarks.

The validation covers representative tasks, not every model or application. In
particular, Codex CLI local reads hit a managed approval request that exec mode cannot
accept, even with read-only RTK-prefixed commands. No approval control was bypassed.
That host validation remains externally blocked; the report must not claim a Codex
pass or universal compatibility from static checks or successful runs on other hosts.
