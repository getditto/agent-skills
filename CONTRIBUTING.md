# Contributing

Thanks for contributing. This repo holds tool-agnostic agent skills for
[Ditto](https://ditto.com). Skills follow the `SKILL.md` convention and work
with Claude Code, opencode, Codex, Gemini, and other agent tools.

**This repo is public and consumed by customers.** Only add content appropriate
for customer consumption.

Two things make contributing here different from a normal docs repo, and they
drive most of the rules below:

1. **Nobody reads these files.** An agent loads them and answers from them. A
   wrong sentence doesn't get skimmed past — it becomes a wrong answer in
   someone's editor, usually with no visible signal that it came from here.
2. **Almost every claim is version-specific.** Ditto ships 4.14.x (LTS), 5.0.x,
   and 5.1.x concurrently, and they genuinely differ — features appear,
   defaults flip, and in at least one case the string-escape convention
   reversed between lines. "It works" is not a fact until you say *where*.

So the bar for a claim in this repo is **verified**, not **plausible**.

---

## Contents

- [Reporting a problem](#reporting-a-problem)
- [The four requirements](#the-four-requirements)
- [Quick start](#quick-start)
- [1. Write a clear PR](#1-write-a-clear-pr)
- [2. State which SDK releases it applies to](#2-state-which-sdk-releases-it-applies-to)
- [3. Say how you tested it](#3-say-how-you-tested-it)
- [4. Cite your sources](#4-cite-your-sources)
- [Using AI tools](#using-ai-tools)
- [Adding a new skill](#adding-a-new-skill)
- [Changing an existing skill](#changing-an-existing-skill)
- [Running the tests](#running-the-tests)
- [Style](#style)
- [Review](#review)

---

## Reporting a problem

You don't need to open a PR to be useful. Three issue templates cover the
common cases:

| Template | Use it when |
|---|---|
| [Incorrect or outdated skill content](.github/ISSUE_TEMPLATE/1-incorrect-content.yml) | A skill states something wrong, or wrong for a specific SDK version |
| [Propose a new skill](.github/ISSUE_TEMPLATE/2-new-skill.yml) | Agents get something about Ditto wrong and no skill covers it |
| [Tooling or packaging bug](.github/ISSUE_TEMPLATE/3-tooling-bug.yml) | The harness, CI, or packaging is broken |

The content template asks the same four questions as the PR template, scaled
down: where it is, what's actually true, which versions you checked, and how
you know. **An unverified report is still worth filing** — just pick
"Inference / not verified" so a reviewer knows what they're looking at.

---

## The four requirements

Every PR that touches skill content must answer four questions. The
[PR template](.github/pull_request_template.md) has a section for each.

| # | Question | Why |
|---|----------|-----|
| 1 | **What** is being added or changed, and why? | Reviewers can't check work they can't identify. |
| 2 | **Which SDK releases** does it apply to? | Three supported lines that behave differently. |
| 3 | **How** was it tested? | Automated, manual, both, or not at all — say which. |
| 4 | **Where** did the information come from? | So the next person can re-verify without redoing your work. |

A PR that leaves these blank will be sent back. That isn't bureaucracy — it is
the only way a reviewer can tell a verified claim from a confident guess, and
this repo has shipped confident guesses before.

---

## Quick start

```bash
# 1. Branch from main, named for the Linear issue
git checkout main && git pull
git checkout -b SDKS-1234-short-description

# 2. Set up test credentials (once)
cp .env-sample .env      # then fill in DITTO_OFFLINE_LICENSE

# 3. Make your change, then validate
set -a && . ./.env && set +a
cd tests/dql && npm run test        # all three SDK versions

# 4. Open a PR and fill in every section of the template
```

Never commit to `main`.

---

## 1. Write a clear PR

Describe **what information is being added**, in your own words, specifically
enough that a reviewer knows what to check.

**Not acceptable:**

> Improve DQL docs
> Update skill with latest info
> Various fixes and improvements

**Acceptable:**

> Adds `RIGHT [OUTER] JOIN` to `select.md` §14. It works on 5.1.0 but the
> grammar block only listed `INNER | LEFT`, so an agent asked about right joins
> would say they don't exist. Also corrects the §14 claim that `FULL OUTER` is
> supported — it is rejected on all three lines.

If you are **correcting** something, say what was wrong before, not just what
is right now. The wrong version may have already propagated into an agent
definition or another reference file, and the reviewer needs to go look.

Other PR hygiene:

- **One logical change per PR.** A version-tag correction and a new cookbook
  section are two PRs. Large mixed PRs get reviewed slowly and badly.
- **Open an issue first** for structural changes — new skills, directory
  moves, changes to `AGENTS.md` conventions. There are
  [issue templates](.github/ISSUE_TEMPLATE) for reporting wrong content,
  proposing a skill, and tooling bugs.
- **Minimal diffs.** Don't reformat, rewrap, or re-order files you didn't
  otherwise need to touch; it buries the real change.

---

## 2. State which SDK releases it applies to

This repo documents **Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x**.

### Name exact patch versions, not lines

Say "verified on 5.1.0", not "works on 5.1.x". You tested one build; claiming a
whole line is an extrapolation, and it has been wrong here before.

### Tag every version-gated claim in two places

1. **Inline**, next to the claim:

   ```markdown
   > **Available in:** Ditto SDK **5.1+**. On 4.14.x / 5.0.x this raises
   > `Explain DML is not supported`.
   ```

2. **In the matrix**, at
   [`skills/dql/references/versions.md`](skills/dql/references/versions.md) §4.

Those must agree. `versions.md` calls itself the single source of truth, so an
inline tag that contradicts it is worse than no tag — it makes both untrustworthy.

### Include the failure mode, not just the availability

"5.1+" tells an agent what to use. The **error text on older versions** tells it
how to recognise the problem in a user's terminal. Include the real string:

```markdown
On 4.14.x and 5.0.x: `DQL parser error: Unexpected token LIKE`
```

### A ✓ means "works", not "parses"

If a statement parses but misbehaves, do not mark it available. Mark it ⚠ and
say what actually happens. A parse-level ✓ on something that silently loses
data is worse than a ✗.

### If your change is version-independent

Say so explicitly — "N/A, no version-specific claims" — rather than leaving the
section blank. Blank reads as "didn't think about it".

---

## 3. Say how you tested it

Pick the honest option. All four are acceptable answers; only silence isn't.

### Automated

The skill's harness covers it. Give the result:

```
tests/dql — 258 catalog entries, 0 FAIL on 4.14.4, 5.0.3 and 5.1.0
(+3 new entries from the examples added in this PR)
```

If you added examples, they should have become catalog entries. Say how many.
See [Running the tests](#running-the-tests).

### Manual

You ran statements against a real SDK by hand. **Paste the statement and the
actual output**, not a summary of it:

```
5.1.0   DELETE FROM nz USE IDS 'k1'   -> ok, rows=0 ; count still 4
4.14.4  DELETE FROM nz USE IDS 'k1'   -> Unexpected token USE at line 1 column 16
```

Real output catches things a summary hides. "Returns 0 rows" and "reports
success while deleting nothing" look identical in prose and are very different
facts.

### Both

The normal case for a substantive change: the harness proves it parses on each
version, and a manual check proves it does the right thing.

### Not executable

Some claims can't be run from a Small Peer — Big Peer behaviour, mesh
propagation, sync timing. Say so, and say what you did instead: which source
files you read, at which ref, or which docs page.

### State what you did *not* verify

If part of your change is unverified, write that down. A declared gap is
something a reviewer can weigh. An undeclared one is a trap — and it is
exactly how a "verified" list ended up in this repo containing two claims that
were false on the current SDK.

---

## 4. Cite your sources

Say where the information came from, strongest source you actually used.

### Evidence hierarchy

| Tier | Source | Cite it as |
|------|--------|-----------|
| 1 | **Executed against a real SDK** | Exact version + the statement you ran + what came back |
| 2 | **Ditto source code** | Repo path + line + branch, e.g. `crates/ditto-dql/src/engine/mod.rs:463` on `origin/releases/stable/sdk-5.1` |
| 3 | **Official documentation** | Full URL, not "the docs say" |
| 4 | **Inference or reasoning** | Allowed — but label it as inference |

Tier 1 beats tier 2 when they disagree: a release branch has moved on from the
published dot release, and the installed SDK is what a customer actually runs.

### Another file in this repo is not a source

This is the rule that matters most. If you are repeating a claim that already
appears in another skill file, either **verify it independently** or **say you
didn't**. Do not cite it.

Self-citation is how a single error becomes a consensus. In this repo it has
already happened: a wrong entry in `versions.md` was copied into an agent
definition, at which point two files "agreed" and the mistake looked
well-established.

### Don't invent citations

Do not cite a source you did not open, a file path you did not read, or an
issue number you did not look up. If you can't find a source for something you
believe is true, write it as inference and let the reviewer decide.

---

## Using AI tools

**AI assistance is welcome here.** Much of this repo's content was produced or
checked with agent tooling, and the test harness exists precisely so that
machine-generated claims can be mechanically falsified.

The standard is the same regardless of how the text was produced: **you are
responsible for every line you submit.** Two conditions:

**Disclose it.** Say in the PR which tool you used and roughly what for
("drafted the reference tables with Claude Code, verified each claim by hand").
There is no penalty for disclosing; concealment is the problem, because
reviewers calibrate how hard to check based on where the content came from.
Routine assistance — spelling, grammar, rewrapping — needs no disclosure.

**Understand it.** If a reviewer asks why a line is there and the honest answer
is "the model wrote it", the PR isn't ready. You should be able to explain what
a claim means and why it's correct without going back to the tool.

What this means in practice for this repo:

- **Never submit an unverified version claim.** Models are fluent about SDK
  behaviour and frequently wrong about it. Every generated claim goes through
  §2, §3 and §4 like any other.
- **Don't paste raw model output** into PR descriptions or review replies.
  Rewrite it in your own words — generated text is verbose in a way that hides
  what a reviewer needs.
- **Strip generated footers and co-author trailers** you didn't intend. Their
  presence signals nobody re-read the submission.
- **Don't request automated AI review** on PRs here. It produces volume, not
  signal, and reviewers have to read it anyway.

A good AI-assisted PR and a bad one are told apart by evidence, not by tooling.
Plenty of low-quality contributions involve no AI at all.

---

## Adding a new skill

### Does it need to exist?

New skills should fill a **demonstrated gap** — something agents get wrong or
can't do without it. Before proposing one, try the task against a current model
with no skill loaded and keep the transcript. "The model already handles this
well" is a good reason not to add a skill; every skill's name and description
are injected into every session, so an unnecessary one costs everyone context.

Open a [**Propose a new skill**](.github/ISSUE_TEMPLATE/2-new-skill.yml) issue
with that evidence before writing the skill.

### Scaffold

Follow [`docs/SKILLS-TEMPLATE.md`](docs/SKILLS-TEMPLATE.md):

```
skills/<skill-name>/
├── SKILL.md            # frontmatter + lean body
├── README.md           # human-facing: scope, supported versions, status
├── references/         # depth, loaded on demand
├── examples/           # worked examples
└── best-practices.md   # optional
```

### Frontmatter must match the Agent Skills spec

Only these keys are permitted: `name`, `description`, `license`,
`compatibility`, `allowed-tools`, `metadata`. **Any other key is a hard error**
in stricter loaders — the skill fails to package rather than being ignored, so
a Claude-Code-only field breaks the skill everywhere else.

- `name` — lowercase, hyphenated, ≤64 chars, **must match the directory name**.
- `description` — ≤1024 chars, third person, covers *what* it does **and**
  *when* to use it, with concrete trigger keywords front-loaded. This is the
  activation mechanism; a vague description means the skill never loads.

### Keep SKILL.md lean

Agent tools load the body whenever the skill triggers, so it competes with the
user's actual conversation for context. Target **under 500 lines**; push depth
into `references/`. Keep references **one level deep** from `SKILL.md` — agents
often only partially read files reached through a chain of links.

### Wire up packaging

- Add a row to the skills table in [README.md](README.md).
- Add a thin wrapper under `plugins/<plugin>/`: a `.claude-plugin/plugin.json`
  plus a **real** `skills/` directory containing **one symlink per skill the
  plugin ships**:

  ```bash
  mkdir -p plugins/ditto-<name>/skills
  ln -s ../../../skills/<skill-name> plugins/ditto-<name>/skills/<skill-name>
  ```

  If the plugin also ships agents, namespace them under `agents/<plugin>/` and
  symlink the **directory**:

  ```bash
  mkdir -p agents/ditto-<name>
  ln -s ../../agents/ditto-<name> plugins/ditto-<name>/agents
  ```

  **Agents must be linked as a directory, never as individual files.** Claude
  Code follows a symlinked directory but not a symlinked file — an
  `agents/foo.md -> ../../../agents/foo.md` link is silently dropped and the
  agent never loads, with no error from `claude plugin validate`. Verify with
  `claude plugin details <plugin>` and check the agent count is what you expect.

  Then add a `.claude-plugin/marketplace.json` entry whose `source` points at
  the wrapper. **Never duplicate skill content inside `plugins/`.**

  **Do not symlink the whole `skills/` or `agents/` tree into a wrapper.** That
  makes every plugin ship every skill in the repo, so a user who installs
  `ditto-dql` silently gets unrelated skills too. Each plugin ships only what it
  declares — CI enforces this.

- **A new skill needs its own plugin unless it genuinely belongs to an existing
  one.** Adding a symlink to an existing wrapper changes what that plugin
  installs for everyone who already has it.

### Add tests

If the skill documents executable statements, add a harness under
`tests/<skill-name>/` and extend CI. `tests/dql/` is the reference
implementation: extract fenced code blocks → curate a catalog → run per SDK
version → report.

---

## Changing an existing skill

- **Update the version matrix** alongside any inline tag you touch.
- **Re-run the harness.** Doc edits shift line numbers, and catalog entry IDs
  are content hashes of `(file, line, query)` — so editing prose can invalidate
  overrides and turn a previously-ignored entry into a failure. Regenerate:

  ```bash
  cd tests/dql
  node scripts/extract-queries.mjs
  node scripts/curate-catalog.mjs
  npm run test
  ```

- **Grep for propagation.** If you corrected a claim, check whether it also
  appears in `agents/`, another reference file, or `SKILL.md`:

  ```bash
  grep -rn "<the wrong claim>" skills/ agents/
  ```

- **Don't silence a failing test to make CI green.** `tests/dql/catalog/overrides.json`
  can mark an entry ignored or tag it `availableIn: []`, and both make a red run
  go green. Use them only when the example is *deliberately* unrunnable — a
  Big-Peer-only statement, or a negative example demonstrating that something is
  rejected — and say so in the override's reason string. Reaching for an override
  because a real example broke is how defects hide: a documented query that works
  on no supported SDK is a documentation bug, not a passing test.

---

## Running the tests

One-time setup:

```bash
cp .env-sample .env                # fill in DITTO_OFFLINE_LICENSE
cd tests/dql
(cd sdks/v4.14.4 && npm install)
(cd sdks/v5.0.3  && npm install)
(cd sdks/v5.1.0  && npm install)
```

Run:

```bash
set -a && . ../../.env && set +a
npm run test                       # all three versions
npm run test:v51                   # one version
npm run report                     # cross-version table
```

A run must end with **0 FAIL** on all three SDKs. Status semantics — including
what `PASS-AS-EXPECTED-FAIL` does and does not prove — are in
[`tests/dql/README.md`](tests/dql/README.md).

Requires Node 24+, macOS or Linux, and a license token. Each SDK lives in its
own `node_modules` tree because the versions cannot coexist in one Node process.

---

## Style

- **Minimal diffs.** Don't reformat files you didn't otherwise touch.
- **Consistent terminology.** Pick one term per concept and keep it.
- **Concrete over abstract.** Real collection names, real errors, real output.
- **No time-relative language.** "Currently", "recently", "the latest version"
  all rot. Name the version.
- **Never document unreleased features as available.** Mark them
  not-yet-shipped, and don't guess at a release.
- **Assume the reader is competent.** These files are read by capable models —
  explaining what SQL is wastes context that could hold something Ditto-specific.

---

## Review

Reviewers check, in roughly this order:

1. **Are the four sections filled in?** If not, back it goes.
2. **Are version claims backed by a stated verification?** Every ✓/✗ that
   changed should trace to something you ran or read.
3. **Does the inline tag match `versions.md`?**
4. **Is CI green** — `ci.yml` plus the skill's test workflow?
5. **Did examples actually run?** Reviewers may re-run them.
6. **Is the scope one logical change?**
7. **Is it appropriate for a public, customer-facing repo?**

Findings that turn out to be wrong are normal and expected — say so and move
on. A confidently-stated wrong claim is the thing this process exists to catch.
