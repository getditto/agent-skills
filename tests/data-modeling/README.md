# data-modeling Skill Tests

Model-level evaluation for the `data-modeling` skill (`skills/data-modeling/`).
Unlike `tests/dql` (which executes DQL against real SDK builds), this harness
evaluates **live AI models**: each case feeds the skill plus a raw JSON
document to a model and deterministically scores the review it produces.

Answers the question: *given this raw JSON, does a model armed with the skill
recommend the right CRDT approach — and catch the landmines?*

## Layout

```
tests/data-modeling/
├── README.md            this file
├── package.json         npm run prompts / run / score (no dependencies)
├── cases/
│   └── <case>/
│       ├── input.json      the raw JSON document the "user" brings
│       └── expected.json   context + expected findings keyed to rubric IDs
├── runner/
│   ├── prompt.mjs          assembles skill files + case into one prompt
│   ├── run.mjs             feeds prompts to a model command, saves responses
│   └── score.mjs           regex-group scoring against expected findings
└── results/             generated, gitignored (responses, prompts)
```

## Cases

| Case | What it must catch |
|---|---|
| `pos-order` | arrays that must become keyed MAPs, inline PDF → ATTACHMENT, 4.14.x strict-mode declarations, size limits |
| `chat-channel` | unbounded embedded messages → split, readBy/members arrays, messageCount → COUNTER, inline image, observer scoping |
| `iot-sensor` | telemetry stream → one doc per reading, 256 KiB / 5 MiB limits, counter, whole-array LWW |
| `team-portal` | comments/history splits, counter-or-count-at-read, JOIN (5.1+) vs denormalize (4.14.x), observer scoping |
| `inventory` | stock/soldToday → COUNTER with INCREMENT/RESTART, attrs on 4.14.x, money as integer cents |
| `user-profile` | **negative control** — a healthy model must not invent splits or unbounded-growth alarms |

Expected findings use the stable rubric IDs from the skill
(`skills/data-modeling/references/workflow.md` §2). Each finding lists
`groups`: arrays of regex alternatives; the finding counts as HIT when every
group has at least one match in the model's response.

## Running

Requirements: Node 18+ and a model CLI. No Ditto license needed.

```bash
cd tests/data-modeling

# 1. (Optional) inspect the prompts without a model
npm run prompts

# 2. Run all cases against a live model.
#    DM_MODEL_CMD must read the prompt on stdin and write the answer to stdout.
DM_MODEL_CMD="claude -p" npm run run          # e.g. Claude Code
DM_MODEL_CMD="opencode run" npm run run       # any stdin/stdout-wrapped CLI

# Single case:
DM_MODEL_CMD="claude -p" node runner/run.mjs --case pos-order

# 3. Score the saved responses (default recall threshold 0.75)
npm run score
node runner/score.mjs --min 0.8
```

Exit codes: `score.mjs` returns 0 when every scored case meets the recall
threshold and no anti-finding regexes match; 1 on any failing case, when no
responses were found, or when `--case` matches nothing (run `run.mjs` first);
2 for an invalid `--min` value. `run.mjs` returns 1 if any case's model
invocation failed (successful cases still get written) or when
`DM_MODEL_CMD` is unset without `--prompts-only`.

## Adding a case

1. `cases/<name>/input.json` — the raw document. Keep base64 payloads
   truncated with a size note (e.g. `~380 KB truncated`) so prompts stay small.
2. `cases/<name>/expected.json` — context paragraph + findings. Each finding:
   `id` (rubric ID), `path`, `severity`, `groups` (array of regex-alternative
   arrays). Test your regexes against a known-good response before committing.
3. Use `antiFindings` sparingly — phrases like "never change `_id`" contain
   `change.*_id` and will false-positive; only add patterns a *correct* answer
   would never produce.

## Caveats

- Scoring is keyword-level: a model can name-check `MAP` without understanding
  it. Read failing cases by hand; the harness is a regression tripwire, not a
  proof of expertise.
- Prompt assembly (`runner/prompt.mjs`) intentionally approximates what an
  agent loads when the skill triggers. If the skill gains a reference file,
  add it to `SKILL_FILES` there.
- Responses are not committed (`results/` is gitignored); they may contain
  model-specific noise and are cheap to regenerate.
