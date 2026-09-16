# Testing

Every skill ships with executable verification under `tests/<skill>/`. This
file is the map: which harness covers which feature, how to configure your
local environment (`.env`), and what each config key means.

## Harnesses by feature

| Feature / skill | Harness | What it does | Docs |
|---|---|---|---|
| [`dql`](skills/dql) (`write-dql`) | [`tests/dql/`](tests/dql/) | Runs every `sql` code block in the skill against real Ditto SDK builds (4.14.4, 5.0.3, 5.1.0), proving each documented query works on the versions it claims | [tests/dql/README.md](tests/dql/README.md) |
| [`data-modeling`](skills/data-modeling) | [`tests/data-modeling/`](tests/data-modeling/) | Live-model evals: feeds raw-JSON cases plus the skill to a real AI model and deterministically scores its recommendations against the rubric finding IDs | [tests/data-modeling/README.md](tests/data-modeling/README.md) |

Both runners share the same config mechanism: the repo-root `.env`, loaded at
startup via `tests/lib/load-env.mjs`. New harnesses should reuse it.

## Configuring your environment (`.env`)

1. Copy the sample to the repo root and fill in your values:

   ```bash
   cp .env-sample .env
   ```

2. `.env` is gitignored — it never gets committed. `.env-sample` is the
   checked-in template; when you add a new config key, document it there.

3. Precedence: variables already set in your shell (or CI secrets) **win**
   over `.env`. The file only fills in what's missing, so CI keeps working
   unchanged and you can override ad hoc:

   ```bash
   DM_MODEL_CMD="opencode run" npm run run   # one-off override of .env
   ```

## Config keys

| Key | Used by | Required | What it is |
|---|---|---|---|
| `DITTO_OFFLINE_LICENSE` | `tests/dql` | **Yes** | Offline license token from [portal.ditto.live](https://portal.ditto.live). The DQL harness spins up real Ditto Small Peers; without a license, DQL mutations are blocked. (Legacy alias also accepted: `DITTO_PLAYGROUND_TOKEN`.) |
| `DITTO_DATABASE_ID` | `tests/dql` | No | Your Ditto database ID from the portal. Defaults to the offline-playground zero UUID (`00000000-1111-2222-3333-444444444444`) — fine for local-only harness runs. |
| `DM_MODEL_CMD` | `tests/data-modeling` | Yes, unless `--prompts-only` | Shell command that runs the model under test. See below. |

### `DM_MODEL_CMD` in detail

The data-modeling harness is model-agnostic. For each case it builds one
self-contained prompt (full skill + raw JSON + context), spawns
`DM_MODEL_CMD`, **pipes the prompt to its stdin**, and captures **stdout** as
the model's response. Any CLI with a non-interactive stdin→stdout mode works:

| Value | Model under test | Reference |
|---|---|---|
| `claude -p` | Claude Code (print mode; uses your existing login) | [Claude Code CLI reference](https://docs.anthropic.com/en/docs/claude-code/cli-usage) |
| `opencode run` | opencode | [opencode CLI docs](https://opencode.ai/docs/cli/) |
| `gemini -p` | Gemini CLI | [gemini-cli repo](https://github.com/google-gemini/gemini-cli) |
| `./wrapper.sh` | Anything you wrap yourself — e.g. `curl` against an OpenAI-compatible endpoint | must read stdin, write only the answer to stdout |

Full contract and tips: [tests/data-modeling/README.md](tests/data-modeling/README.md#how-dm_model_cmd-works)
("How `DM_MODEL_CMD` works").

## CI

GitHub Actions does not use `.env` — the DQL matrix workflow
(`.github/workflows/dql-skill-tests.yml`, triggers on `skills/dql/**` or
`tests/dql/**` changes) injects the `DITTO_OFFLINE_LICENSE` repo secret
directly into the environment, which takes precedence per the rule above. The
data-modeling harness is run manually (it spends live-model tokens).
