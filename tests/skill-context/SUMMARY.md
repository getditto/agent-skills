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
corrected after the final traces. The bounded iteration makes no claim of a subsequent
model rerun. This also shows why
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

`results.json` preserves 16 primary/retry/regression records including the timeout
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

Every result records its own digest. Subsequent wording or static example corrections
must be described as after these snapshots; these runs do not certify the exact final
working-tree bytes.
