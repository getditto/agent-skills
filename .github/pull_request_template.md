<!--
Before opening: see CONTRIBUTING.md. The four sections below are required.
Delete any section that genuinely does not apply, and say why it doesn't.

This repo is consumed by AI agents and, through them, by customers. A claim that
is wrong here becomes a wrong answer in someone's editor, so the bar is
"verified", not "plausible".
-->

## What this changes

<!--
What information is being added, changed, or removed — in your own words.
Name the skill and the files. If you are correcting something, say what was
wrong before, not just what is right now.

Not: "improve docs", "update DQL skill", "various fixes".
-->

## SDK versions

<!--
Which Ditto SDK releases does this content apply to?

State exact patch versions you actually ran against (e.g. 4.14.6, 5.0.3, 5.1.0),
not just the line. If a claim is version-gated, say where the gate is documented
(a version tag inline, plus a row in skills/write-dql/references/versions.md).

If this change is version-independent (tooling, packaging, prose with no
technical claims), write "N/A — no version-specific claims" and move on.
-->

| SDK | Applies | Verified how |
| --- | :-----: | ------------ |
| 4.14.x (LTS) |  |  |
| 5.0.x        |  |  |
| 5.1.x        |  |  |

## How this was tested

<!-- Tick what applies and fill in the detail. -->

- [ ] **Automated** — the skill's test harness covers it
- [ ] **Manual** — I ran statements against a real SDK by hand
- [ ] **Both**
- [ ] **Not executable** — explain what you did instead (source reading, docs)

**Automated:** <!-- Which harness, and the result. e.g. "tests/dql, 259 entries,
0 FAIL on 4.14.6 / 5.0.3 / 5.1.0". If you added catalog entries, say how many. -->

**Manual:** <!-- What you ran and what came back. Paste the statement and the
actual output/error, not a summary of it. -->

**Not covered:** <!-- Anything in this PR that is NOT verified, and why.
An honest gap here is fine; a silent one is not. -->

## Sources

<!--
Where did this information come from? Cite the strongest source you actually
used — see the evidence hierarchy in CONTRIBUTING.md.

  1. Executed against a real SDK  — exact version + the statement you ran
  2. Ditto source                 — repo path + branch/ref, e.g.
                                    crates/ditto-dql/src/engine/mod.rs:463
                                    on origin/releases/stable/sdk-5.1
  3. Official documentation       — full URL
  4. Inference / reasoning        — allowed, but label it as such

Another file in THIS repo is not a source. If you are propagating an existing
claim, verify it independently or say that you did not.
-->

## Checklist

- [ ] Branched from `main`, named for the Linear issue
- [ ] CI green (`ci.yml`, plus the skill's test workflow if one applies)
- [ ] Version claims tagged inline **and** reflected in the skill's version matrix
- [ ] Every code sample I added or edited was actually executed
- [ ] `README.md` skills table updated (new skill only)
- [ ] `AGENTS.md` updated if conventions or structure changed
- [ ] No customer-inappropriate content — this repo is public

Linear: <!-- https://linear.app/ditto/issue/... -->
