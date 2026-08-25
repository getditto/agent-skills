# Contributing

Thanks for contributing! This repo holds tool-agnostic agent skills for
[Ditto](https://ditto.com). Skills follow the `SKILL.md` convention and work
with Claude Code, opencode, Codex, Gemini, and other agent tools.

**This repo will become public for customer use — only add content appropriate
for customer consumption.**

## Adding a new skill

1. **Branch.** Never commit to `main`. Branch from `main` named after the
   Linear issue, e.g. `sdks-1234/<short-description>`.

2. **Scaffold** from [docs/SKILLS-TEMPLATE.md](docs/SKILLS-TEMPLATE.md):

   ```
   skills/<skill-name>/
   ├── SKILL.md
   ├── README.md
   ├── references/
   └── examples/
   ```

   The directory name must match the `name:` in the SKILL.md frontmatter.

3. **Write the skill.** Follow the template: strong `description` (it's the
   activation trigger), lean SKILL.md body, depth in `references/` and
   `examples/`.

4. **Add tests** under `tests/<skill-name>/` if the skill documents executable
   statements. See `tests/dql/README.md` for the reference harness (extraction
   → catalog curation → per-SDK-version runner → report).

5. **Wire up packaging:**
   - Add a row to the skills table in [README.md](README.md).
   - Add the skill to the Claude Code marketplace: create or extend a thin
     wrapper under `plugins/<plugin>/` (a `.claude-plugin/plugin.json` plus
     symlinks into `skills/` / `agents/`) and add an entry to
     `.claude-plugin/marketplace.json` whose `source` points at that wrapper.
     Do **not** duplicate skill content inside `plugins/`.

6. **Validate locally:**
   - `python3 -m json.tool .claude-plugin/marketplace.json > /dev/null` (and
     any plugin.json you touched)
   - Check SKILL.md frontmatter starts with `---` and has `name:` +
     `description:` (same checks CI runs)
   - If you added/removed files under the skill, re-run the test harness
     extraction for that skill
   - Smoke-test the skill in at least one agent tool

7. **PR checklist:**
   - [ ] CI green (`ci.yml` + the skill's test workflow)
   - [ ] README table updated
   - [ ] Template requirements met (frontmatter, sections, token budget)
   - [ ] No customer-inappropriate content
   - [ ] AGENTS.md updated if you changed structure or conventions

## Style

- Minimal diffs; don't reformat files you didn't otherwise touch.
- Document unreleased SDK features as future/not-yet-shipped, never as
  available.
- Keep `SKILL.md` files lean; push detail into `references/`.
