# Anti-patterns — TODO_LANGUAGE

> **Sources for this file.** The `FORBIDDEN patterns` blocks in
> `sdk/latest/migration-guides/<lang>-v4.mdx`, plus anything the SDK's own release notes
> flag. Resolve `<lang>` per directory using the table in
> `docs/SDK-SKILL-TEMPLATE.md` §8.1 — JS, Java, C# and Go do not follow the obvious
> pattern, and Go has no migration guides at all.

<!--
  This file holds the EXPLANATION. SKILL.md § Anti-patterns holds the one-line punchline
  for each of these, and links here. Spec §5.

  One H2 per anti-pattern, each with: the wrong form, the right form, and a **Symptom:**
  line naming the exact compiler error, exception, profiler symbol, or measured factor.
  Never the word "slow".

  Add a `## Contents` list once this file passes 8,000 characters or 200 lines — CI enforces it (spec §3).
-->

Each of these compiles. Most produce no error at runtime either — the symptom is a silent
wrong result, a frozen screen, or a peer that never reconnects. The one-line rules are in
[`SKILL.md` § Anti-patterns](../SKILL.md#anti-patterns); this file carries the code and
the diagnosis.

## TODO_ANTIPATTERN_NAME

```TODO_LANG
// WRONG
TODO
```

```TODO_LANG
// CORRECT
TODO
```

**Symptom:** TODO — the exact compiler error, exception name, profiler symbol, or
measured factor.
