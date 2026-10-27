# Skill context smoke evaluations

These cases evaluate natural skill selection, reference use and core answer correctness.
They are a small manually reviewed smoke suite, not a benchmark or context compatibility
certification. `cases.json` contains public synthetic tasks and review criteria. Send
only `environment_prompt` plus a case's `prompt` to the model, never `review_criteria`.

## Reproduce the method

1. Create a private temporary workspace for each host and case. Copy only canonical
   skills into it; do not copy repository AGENTS.md, CLAUDE.md, config, MCP, .env,
   credentials, examples outside the skills, earlier answers or traces.
2. Record the CLI version, requested and reported model IDs, a SHA-256 digest of the
   copied skill tree, tool and skill catalogs, and effective tool/MCP isolation.
3. Preserve existing authentication without changing global configuration. Account
   permissions and managed policy apply; record a blocker if they prevent local reads.
4. Run the same natural task once per host/model in a fresh session. Bound runtime
   externally (120 seconds in the initial matrix), and kill the process group on timeout.
   Claude also used 12 turns and a USD 1 budget. OpenCode used 12 agent steps and an
   explicit task-local 8,192-token output cap. Record retries separately.
5. Capture raw stdout JSON events and stderr privately. Save the final answer, actual
   skill invocations, file reads/searches, byte sizes, token/cache usage, elapsed time,
   errors, and source digest. Do not publish raw traces without reviewing them.
6. Review against the criteria. Keep host setup/discovery, reference use, task correctness,
   timeout and generated-code validity as separate dimensions. Do not score a timeout
   as a pass. These tasks do not compile generated snippets or run SDK code.

## Host command surfaces

These are command templates, not turnkey automation. Supply host/model options from
the environment being evaluated and verify startup catalogs before interpreting results.
The private run's environment-specific orchestration script is not part of this package.

**Codex:** copy skills into `WORKSPACE/.agents/skills/`. Supported CLI options include:

```text
codex --no-daemon -a never exec --json --ephemeral --ignore-user-config --ignore-rules
  --skip-git-repo-check --sandbox read-only --disable plugins --disable hooks
  --disable memories -c project_doc_max_bytes=0 -c web_search="disabled"
  -C WORKSPACE -m MODEL -
```

Pass the prompt on stdin. Disable discovered global skills with explicit
`skills.config` path overrides if supported. Do not assume `--ignore-user-config`
removes managed/global instructions. Record approval rejection; never bypass policy.
The observed Codex host retained global guidance and rejected local file commands,
including commands following the local RTK convention; it was not a clean comparison.
The 2026-10-27 rerun isolated Codex by running it with a fresh empty `HOME` (no
`~/.agents/skills`, no shell profile) and a fresh `CODEX_HOME` containing only a
symlink to the existing `auth.json` (no config, rules, memories or global guidance).
Confirm the catalog shows only vendor builtins plus the canonical skills before a run.

**Claude Code:** copy skills into a temporary local plugin's real `skills/` directory
and create `.claude-plugin/plugin.json` with a synthetic name, version and description.
Register that plugin with `--plugin-dir`, retaining normal authentication:

```text
claude --print --verbose --output-format stream-json --no-session-persistence
  --restricted --strict-mcp-config --mcp-config {"mcpServers":{}}
  --setting-sources project --tools Read,Grep,Glob,Skill
  --allowedTools Read,Grep,Glob,Skill --permission-mode dontAsk
  --permission-prompts none --settings {"disableAllHooks":true,"autoMemoryEnabled":false}
  --max-budget-usd 1 --max-turns 12 --plugin-dir PLUGIN --model MODEL PROMPT
```

Use proper subprocess argument arrays; JSON arguments above are single arguments.
Put PLUGIN inside the session's working directory, with symlinks resolved. Otherwise
Read rejects skill reference files as outside the working directory, and answers fall
back to the entry point alone; check traces for those tool errors.
The startup `init` event records skills, tools, MCP servers and resolved model. The
observed local plugin exposed all five canonical skills plus vendor builtins; the
four named tools were available and MCP was empty. Filesystem-only registration under
restricted mode omitted canonical skills in the first pilot; preserve that failure.

**OpenCode:** copy skills into `WORKSPACE/.opencode/skills/`. Use:

```text
opencode run --pure --format json --dir WORKSPACE --model PROVIDER/MODEL --agent eval PROMPT
```

Define a task-local `eval` primary agent with read/grep/glob/skill tools, 12 steps,
and explicit deny permissions for shell, edits, web, questions, delegation and external
directories. Whitelist only canonical skill names; deny all other skills. Disable
every configured MCP server in the task-local config. `--pure` disables plugins,
not MCP. Use `OPENCODE_CONFIG_CONTENT` for local overrides, never edit user config.
Disable external skill scans/default plugins/model refresh/auto-update using supported
environment flags. Native global OpenCode skills may remain in debugger inventory;
explicit deny permissions exclude them from the usable model skill catalog. Record
this as permission-filtered isolation rather than an empty global installation.

The initial OpenCode pilot returned reasoning without a final answer. One retry
replaced broad default-deny permissions with explicit tool denials and added a
task-local output limit to otherwise zero-valued custom-model metadata. Keep this
provenance; the run does not identify which setup change resolved the empty response.

## Interpreting usage

Report uncached input, cache creation, cache read, output and reasoning separately.
Cumulative input across turns is not the size of one context window. Per-request
input is available in some traces and excludes later unreported work after a timeout.
Provider tokenizers, host prompts, caching and builtin catalogs differ, so cross-host
totals are not a before/after estimate of the changes' savings. Zero configured prices
are not proof of zero billed cost. An advertised model maximum is not its configured
or effective deployment budget.

No credentials, private endpoints, user paths or raw traces belong in a public report.

## Repository regression checks

Run `python3 tests/skill-context/test_contract.py` for the size, navigation and
canonical-name negative controls (also in CI). Run
`env -u NO_COLOR node tests/skill-context/check-scoped-joins.mjs` after installing
the existing `tests/dql` SDK packages and configuring `DITTO_OFFLINE_LICENSE` in
the repository `.env` or environment. The latter executes the corrected order and
ticket JOIN examples on SDK 5.1.0, with duplicate parent numbers across scopes,
and asserts that unrelated stores/teams are excluded. It does not run a model or
validate generated snippets. Results are summarized in [SUMMARY.md](SUMMARY.md);
`results.json` preserves the reviewed model observations, including failures.
