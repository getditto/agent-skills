---
name: check-permissions
description: Check or request permissions for state-modifying commands. Use when the user asks what commands are allowed or denied, or to gate a set of commands before running them. Supports session and permanent caching. Other skills should invoke this to handle their pre-flight permission checks.
allowed-tools: Bash, AskUserQuestion
---

# Check Permissions

> **This skill is always allowed.** It must never be gated by its own permission system — doing so would be circular. All modes run unconditionally regardless of session blocks, allows, or global rules. No pre-flight check is needed or permitted before invoking this skill.

Nine modes depending on the arguments provided.

## Arguments

- No args — **status mode**: show current permission state
- `--help` — **help mode**: display usage reference for all modes
- `<identifier> --permissions cmd1,cmd2,cmd3` — **request mode**: check and request permission for a set of commands
- `--allow "cmd1,cmd2"` — **allow mode**: add commands to the session allow list
- `--block "cmd1,cmd2"` — **block mode**: add commands to the session block list
- `--permanent-allow "cmd1,cmd2"` — **permanent allow mode**: permanently add commands to `settings.json`
- `--clear` — remove all session allows, blocks, and identifier caches at once
- `--clear-allow` — remove all session allows; `--clear-allow "cmd1,cmd2"` removes specific ones
- `--clear-block` — remove all session blocks; `--clear-block "cmd1,cmd2"` removes specific ones

Parse the mode from the leading flag or the presence of `--permissions`. Commands after `--allow`/`--block`/`--permanent-allow`/`--clear-allow`/`--clear-block` are comma-separated. Strip leading/trailing whitespace from each.

**Storage files** (all in `${SESSION_DIR}`):
- `<identifier>-permission` — identifier-level cache (contains `allowed`)
- `session-allows` — newline-separated list of exact command strings granted for this session
- `session-blocks` — newline-separated list of exact command strings blocked for this session

**Priority order** (highest to lowest) when resolving any command:
1. **Session allow** — if the exact command is in `session-allows`, it is **allowed** (wins over everything, including blocks)
2. **Session block** — if the exact command is in `session-blocks`, it is **denied**
3. **Identifier cache** — if `<identifier>-permission` contains `allowed`, the command is **allowed**
4. **Global rules** — consult `~/.claude/CLAUDE.md`; if restricted, ask the user

---

## Mode 1: Status Check (no args)

Run the following in parallel:

```bash
# Global rules
cat ~/.claude/CLAUDE.md

# Session: identifier caches, command allows, command blocks
# Output format: type|name|status|skill_path (skill_path empty for commands)
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
for f in "${SESSION_DIR}"*-permission; do
  if [ -f "$f" ]; then
    id=$(basename "$f" -permission)
    skill_match=$(ls /home/tcolbert/Projects/claude-code-plugins/plugins/*/skills/"${id}"/SKILL.md 2>/dev/null | head -1)
    echo "identifier|${id}|Allowed|${skill_match}"
  fi
done
if [ -f "${SESSION_DIR}session-allows" ]; then
  while IFS= read -r cmd; do
    echo "command|${cmd}|Allowed|"
  done < "${SESSION_DIR}session-allows"
fi
if [ -f "${SESSION_DIR}session-blocks" ]; then
  while IFS= read -r cmd; do
    echo "command|${cmd}|Blocked|"
  done < "${SESSION_DIR}session-blocks"
fi

# Permanent allows
cat ~/.claude/settings.json 2>/dev/null
```

Display as three sections:

**Global Restrictions** — one row per rule from the Command Execution Rules section of `~/.claude/CLAUDE.md`. Do not group multiple rules into one row:

| Restriction | Detail |
|-------------|--------|
| `<exact command or pattern>` | `<what it prevents or requires>` |
| `<exact command or pattern>` | `<what it prevents or requires>` |

**Session Overrides** — all active session-level entries. The command above outputs pipe-delimited `type|name|status|skill_path` lines. Render as a single table. Show ✓ in the Skill column if `skill_path` is non-empty, otherwise —:

| Override | Type | Status | Skill |
|----------|------|--------|-------|
| `create-pr` | Identifier | Allowed | ✓ |
| `kubectl edit` | Command | Allowed | — |
| `git push` | Command | Blocked | — |

If no entries exist, note: _No session overrides active._

**Permanent Allows** — from `settings.json`. Cross-reference with global rules in `~/.claude/CLAUDE.md` to populate the Restrictions column — e.g. path restrictions, pattern-scoped allows, or global rules that still apply even when the tool is allowed:

| Command / Tool | Description | Restrictions | Source |
|----------------|-------------|--------------|--------|
| `<command>` | `<what it does>` | `<any limits that still apply, or — if none>` | `settings.json` |

---

## Mode 2: Permission Request (`<identifier> --permissions cmd1,cmd2,...`)

Use a two-phase approach to make repeat checks as fast as possible.

**Session file format** — `<identifier>-permission` stores two lines:
```
allowed
cmd1,cmd2,cmd3,...
```
The first line is the status (`allowed`). The second line is a comma-separated list of the commands that were approved. Legacy files with only `allowed` (no command line) are treated as approved for any command set.

### Phase 1: Fast path — identifier cache only (single file read)

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
[ -f "${SESSION_DIR}<identifier>-permission" ] && cat "${SESSION_DIR}<identifier>-permission"
```

Parse the result:
- If the file does not exist → go to Phase 2.
- If line 1 is `allowed` and line 2 is absent (legacy format) → return `allowed` immediately.
- If line 1 is `allowed` and line 2 is present → check whether every requested command appears in the stored comma-separated list:
  - **All requested commands are covered** → return `allowed` immediately. **Stop here.**
  - **Any requested command is not in the stored list** → go to Phase 2 to handle the new commands only.

### Phase 2: Slow path — full resolution (only reached on cache miss or new commands)

Read session allows, session blocks, and the global rules cache in parallel:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
[ -f "${SESSION_DIR}session-allows" ] && cat "${SESSION_DIR}session-allows"
[ -f "${SESSION_DIR}session-blocks" ] && cat "${SESSION_DIR}session-blocks"
# Use cached global rules if available, otherwise read CLAUDE.md and cache it
if [ -f "${SESSION_DIR}global-rules-cache" ]; then
  cat "${SESSION_DIR}global-rules-cache"
else
  cat ~/.claude/CLAUDE.md | tee "${SESSION_DIR}global-rules-cache"
fi
```

Only evaluate the **new commands** (those not already in the stored approval list). Previously approved commands are already cleared — do not ask about them again.

For each new command, apply priority order:

1. **Session allow match** (exact string) → `allowed`
2. **Session block match** (exact string) → `denied`
3. **Global rules cache** → if restricted, fall through to the question

If **any** command is `denied` via step 2, return `denied` immediately explaining which command is blocked.

If **any** new command falls through to step 3 (needs user approval), display only the **new** commands and ask **once**:

| Command |
|---------|
| `new-cmd1` |
| `new-cmd2` |

Ask using `AskUserQuestion`:

> "**`<identifier>`** needs permission to run these additional commands. Are these okay?"
>
> - **Yes, this time** — allow for this invocation only; ask again next time
> - **Yes, this session** — add to the cached approval list for this session
> - **Yes, always** — permanently add these commands to the allowed list (updates settings.json)
> - **No** — deny; display the commands for manual execution

Apply the response:

- **Yes, this time**: return `allowed`. Do not update the session file.
- **Yes, this session**: merge the new commands into the stored list and rewrite `${SESSION_DIR}<identifier>-permission`:
  ```
  allowed
  cmd1,cmd2,...,new-cmd1,new-cmd2
  ```
  Return `allowed`.
- **Yes, always**: invoke `update-config` skill to add each new command to the global allowed list, return `allowed`.
- **No**: return `denied`. Display each denied command as a shell snippet for manual execution.

---

## Mode 3: Allow (`--allow "cmd1,cmd2"`)

For each command, remove it from `session-blocks` if present, then add it to `session-allows` if not already there. The last operation wins — adding an allow always cancels any existing block for the same command:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
for cmd in <parsed commands>; do
  # Remove from blocks if present
  if [ -f "${SESSION_DIR}session-blocks" ]; then
    grep -vxF "${cmd}" "${SESSION_DIR}session-blocks" > "${SESSION_DIR}session-blocks.tmp" && mv "${SESSION_DIR}session-blocks.tmp" "${SESSION_DIR}session-blocks"
  fi
  # Add to allows if not already present
  grep -qxF "${cmd}" "${SESSION_DIR}session-allows" 2>/dev/null || echo "${cmd}" >> "${SESSION_DIR}session-allows"
done
```

Confirm to the user:

> Added to session allow list:
> - `cmd1`
> - `cmd2`

---

## Mode 4: Block (`--block "cmd1,cmd2"`)

For each command, remove it from `session-allows` if present, then add it to `session-blocks` if not already there. The last operation wins — adding a block always cancels any existing allow for the same command:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
for cmd in <parsed commands>; do
  # Remove from allows if present
  if [ -f "${SESSION_DIR}session-allows" ]; then
    grep -vxF "${cmd}" "${SESSION_DIR}session-allows" > "${SESSION_DIR}session-allows.tmp" && mv "${SESSION_DIR}session-allows.tmp" "${SESSION_DIR}session-allows"
  fi
  # Add to blocks if not already present
  grep -qxF "${cmd}" "${SESSION_DIR}session-blocks" 2>/dev/null || echo "${cmd}" >> "${SESSION_DIR}session-blocks"
done
```

Confirm to the user:

> Added to session block list:
> - `cmd1`
> - `cmd2`

---

## Mode 5: Clear Allow (`--clear-allow` or `--clear-allow "cmd1,cmd2"`)

**No commands specified** — remove the entire session allow list:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
rm -f "${SESSION_DIR}session-allows"
```

**Commands specified** — remove only those exact entries:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
for cmd in <parsed commands>; do
  grep -vxF "${cmd}" "${SESSION_DIR}session-allows" > "${SESSION_DIR}session-allows.tmp" && mv "${SESSION_DIR}session-allows.tmp" "${SESSION_DIR}session-allows"
done
```

Confirm what was removed.

---

## Mode 6: Clear Block (`--clear-block` or `--clear-block "cmd1,cmd2"`)

**No commands specified** — remove the entire session block list:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
rm -f "${SESSION_DIR}session-blocks"
```

**Commands specified** — remove only those exact entries:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
for cmd in <parsed commands>; do
  grep -vxF "${cmd}" "${SESSION_DIR}session-blocks" > "${SESSION_DIR}session-blocks.tmp" && mv "${SESSION_DIR}session-blocks.tmp" "${SESSION_DIR}session-blocks"
done
```

Confirm what was removed.

---

## Mode 7: Permanent Allow (`--permanent-allow "cmd1,cmd2"`)

Invoke the `update-config` skill to add each command to the global allowed list in `settings.json`:

```
/update-config add permission "cmd1"
/update-config add permission "cmd2"
```

Confirm to the user once done:

> Permanently allowed:
> - `cmd1`
> - `cmd2`
>
> These commands are now in `settings.json` and will be allowed in all future sessions.

---

## Mode 9: Clear All (`--clear`)

Remove all session-level overrides in one operation — allows, blocks, and all identifier permission caches:

```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
rm -f "${SESSION_DIR}session-allows"
rm -f "${SESSION_DIR}session-blocks"
rm -f "${SESSION_DIR}"*-permission
```

Confirm to the user:

> Session permissions cleared. All allows, blocks, and identifier caches have been removed.

---

## Mode 8: Help (`--help`)

Display the following usage reference as rendered markdown:

---

**check-permissions** — manage command permissions for Claude Code sessions.

| Usage | What it does |
|-------|-------------|
| `/check-permissions` | Show current permission state — global restrictions, session overrides, and permanent allows |
| `/check-permissions <id> --permissions cmd1,cmd2` | Request permission to run a set of commands, using `<id>` as a cache key. Asks the user once and caches the answer |
| `/check-permissions --allow "cmd1,cmd2"` | Add commands to the session allow list — overrides blocks and global rules for this session |
| `/check-permissions --block "cmd1,cmd2"` | Add commands to the session block list — prevents those commands from running this session |
| `/check-permissions --permanent-allow "cmd1,cmd2"` | Permanently add commands to `settings.json` — allowed in all future sessions |
| `/check-permissions --clear` | Remove all session allows, blocks, and identifier caches at once |
| `/check-permissions --clear-allow` | Remove all session allows |
| `/check-permissions --clear-allow "cmd1,cmd2"` | Remove specific commands from the session allow list |
| `/check-permissions --clear-block` | Remove all session blocks |
| `/check-permissions --clear-block "cmd1,cmd2"` | Remove specific commands from the session block list |
| `/check-permissions --help` | Show this help |

**Priority order** (highest to lowest):
1. Session allow — wins over everything, including blocks
2. Session block — denies the command for this session
3. Identifier cache — allowed for all commands under that identifier
4. Global rules (`~/.claude/CLAUDE.md`) — last resort; asks the user if restricted

---
