---
name: create-pr
description: Create a GitHub pull request. Use when user asks to create a PR, open a pull request, or submit changes for review. Confirms the repo, handles branch creation if on main, drafts a PR message from the diff, and creates the PR via gh.
allowed-tools: Bash
---

# Create Pull Request

Guides the user through creating a GitHub PR: confirm the repo, ensure a feature branch exists, draft a message from the diff, iterate with the user, then create the PR.

## Arguments

- `<repo>` (optional) — repo name to skip the repo picker (e.g. `cloud-infra-apps`)
- `--verbose` (optional flag) — show all intermediate output including commands, background task status, and step narration

Parse these from the skill arguments. Examples:
- `/create-pr` — no repo, quiet mode
- `/create-pr cloud-infra-apps` — repo specified, quiet mode
- `/create-pr --verbose` — no repo, verbose mode
- `/create-pr cloud-infra-apps --verbose` — repo specified, verbose mode
- `/create-pr --verbose cloud-infra-apps` — flag before repo also valid

## Output Verbosity

**Default (quiet) mode** — only show the user things that require their attention or are final results:
- The permissions table and `AskUserQuestion` (if needed)
- The repo list and `AskUserQuestion` (if needed)
- The discovery summary table and `AskUserQuestion`
- All branch, commit, and PR `AskUserQuestion` prompts
- Changes summary and suggested commit message
- The PR draft
- The PR URL

**Verbose mode** — additionally show:
- Session permission check results
- Background task status ("Fetch started", "Fetch complete", etc.)
- Step narration ("Kicking off discovery...", "Pre-fetching diffs...", etc.)
- Raw command output where relevant

In quiet mode, suppress all intermediate narration. Run commands silently and only surface results when they require user input or are the final output.

## Pre-flight: Permission Check

This skill needs to run the following state-modifying commands. Present these as a markdown table:

| Command | Purpose |
|---------|---------|
| `git checkout -b <branch>` | Create a feature branch |
| `git add` / `git commit` | Stage and commit changes |
| `git push -u origin <branch>` | Push the branch to remote |
| `gh pr create` / `gh pr edit` | Create or update the pull request |

Before running any of them:

**1. Check for a saved session permission** using the Claude session temp directory as the key. If no repo was specified by the user, kick off the Step 1a repo listing commands **in parallel** with this check — don't wait for the result before starting discovery:
```bash
SESSION_DIR=$(ls -td /tmp/claude-1000/-home-tcolbert-Projects/*/ 2>/dev/null | head -1)
[ -f "${SESSION_DIR}create-pr-permission" ] && cat "${SESSION_DIR}create-pr-permission"
```
If the file exists and contains `allowed`, skip the question entirely and proceed to Step 1.

**2. Otherwise**, check whether a global rule (e.g. in `~/.claude/CLAUDE.md`) restricts these specific commands.

If they are restricted, ask the user **once** using `AskUserQuestion`:

> "This skill needs to run: `git checkout -b`, `git commit`, `git push`, and `gh pr create/edit`. Are these okay?"
>
> - **Yes, this time** — allow for this skill run only; ask again next invocation
> - **Yes, this session** — allow until you close Claude Code; don't ask again this session
> - **Yes, always** — permanently add these commands to your allowed list (updates settings.json)
> - **No** — display all state-modifying commands for manual execution throughout

Store the user's choice and apply it consistently for the rest of the skill. Do **not** ask again per-command.

- **Yes, this time**: proceed; ask again on the next invocation.
- **Yes, this session**: write `allowed` to `${SESSION_DIR}create-pr-permission` so subsequent invocations in this session skip the question, then proceed.
- **Yes, always**: invoke the `update-config` skill to add `git checkout -b`, `git commit`, `git push`, `gh pr create`, and `gh pr edit` to the global allowed commands list, then proceed.
- **No**: display every state-modifying command as a shell snippet for the user to run manually.

If the commands are not restricted, proceed directly to Step 1.

> **Note:** Read-only commands (`git status`, `git diff`, `git log`, `gh pr list`, `gh repo view`, etc.) are never restricted and can always be run directly.

## Step 1: Discover Repo, Branch, and Existing PR

**1a. Identify the repo path**

- If the user specified a repo (e.g. "create a PR for cloud-infra-apps"), resolve `<repo-path>` from that name and skip the directory listing.
- If **no repo was specified**, run two commands in parallel:

  1. Get all repos sorted alphabetically for display:
  ```bash
  ls -1d /home/tcolbert/Projects/*/ | xargs -I{} basename {}
  ```

  2. Find the 3 most recently active repos — prioritising repos with uncommitted changes first, then by most recent commit timestamp:
  ```bash
  for d in /home/tcolbert/Projects/*/; do
    name=$(basename "$d")
    dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
    ts=$(git -C "$d" log -1 --format=%ct 2>/dev/null || echo 0)
    [ "$ts" != "0" ] && printf "%d %d %s\n" "$dirty" "$ts" "$name"
  done | sort -k1,1rn -k2,2rn | head -3 | awk '{print $3}'
  ```

  Display the full alphabetical list as a numbered markdown list so the user can see all options.

  Then ask using `AskUserQuestion` with 4 options:
  - Options 1–3: the **repo names** of the 3 most recently active repos (e.g. `cloud-infra-apps`, `claude-code-plugins`, `sre-tooling`) — use the actual name as the option label
  - Option 4: **"Enter a number from the list above"** — when selected, prompt the user to type the number corresponding to their repo in the displayed list

  Wait for the answer before continuing.

**1b. As soon as the repo path is known, immediately kick off `git fetch` in the background** — it's a network call and is the slowest part of discovery. Don't wait for it before running the other commands:

```bash
git -C <repo-path> fetch --quiet origin
```

**1c. In parallel with the fetch, run the remaining fast discovery commands:**

```bash
cd <repo-path> && gh repo view --json nameWithOwner -q .nameWithOwner
git -C <repo-path> rev-parse --abbrev-ref HEAD
git -C <repo-path> status --short
gh api user --jq .login
```

The GitHub username is fetched here so it's available immediately if a branch needs to be created in Step 2.

**1d. As soon as `git rev-parse` returns the branch name**, immediately fire the PR check in parallel with waiting for the fetch to complete:

```bash
gh pr list --repo <org>/<repo> --head <branch-name> --json number,title,url --limit 1
```

**1e. Once the fetch completes**, get the commit count:

```bash
git -C <repo-path> rev-list --count origin/main..HEAD
```

**1f. Output the following summary table to the user first, then immediately follow with the `AskUserQuestion`. Do not call `AskUserQuestion` before the table is displayed.**

| | |
|---|---|
| **Repo** | `<org>/<repo>` |
| **Branch** | `<branch-name>` |
| **GitHub user** | `<username>` |
| **Uncommitted changes** | Yes / No |
| **Commits ahead of main** | `<N>` |
| **Existing PR** | #<number> — <title> (<url>) / None |

Then ask for confirmation using `AskUserQuestion`:

> "Proceed with this repo and branch?"
>
> - **Yes** — proceed
> - **No, wrong repo or branch** — ask the user to clarify before continuing

Wait for confirmation before continuing.

## Step 2: Handle Branch State

Using the branch discovered in Step 1 — no additional commands needed.

**If on `main` or `master`:**

A branch is required. Generate suggestions in parallel:

- If there are **uncommitted changes** (known from Step 1): run `git diff HEAD --stat` to get a sense of what changed and derive a short description slug (e.g. `add-gpg-key`, `fix-ingress-timeout`, `update-eks-version`).
- The GitHub username is already known from Step 1c.

Both of these can run simultaneously — don't wait for one before starting the other.

Produce up to three branch name suggestions based on the description slug and username, then present them to the user using `AskUserQuestion`:

> "A branch is required. Which format would you like for the branch name?"
>
> - **With ticket** — `<username>/<ticket>-<description>` (you'll be asked for the ticket number)
> - **Without ticket** — `<username>/<description>`
> - **Freeform** — type your own

- **Option 1 selected**: ask "What's the ticket number?" and insert it to produce `<username>/<ticket>-<description>`. Confirm the full name with the user before proceeding.
- **Option 2 selected**: confirm `<username>/<description>` with the user. They may adjust the description before confirming.
- **Option 3 selected**: ask "What should the branch be named?" and use whatever they provide.

Run the checkout directly — unless a global restriction is in effect and no override has been granted, in which case display it and wait for confirmation:
```bash
git -C <repo-path> checkout -b <branch-name>
```

After switching, re-run the parallel discovery from Step 1b to refresh state.

- If there are **uncommitted changes on the new branch**: continue to Step 3 as normal.
- If there are **no uncommitted changes and zero commits ahead of `origin/main`** (branch freshly cut from clean `main`): tell the user:

  > "Branch `<branch-name>` created. Make your changes, then re-run `/ditto-platform-skills:create-pr` and I'll pick up from here."

  Exit the skill cleanly.

**If already on a feature branch:**

- **Confirmed in Step 1d**: continue to Step 3.
- **User says wrong branch**: ask what branch they'd like. Run the checkout directly — or display it if restricted — then wait for confirmation:
  ```bash
  git -C <repo-path> checkout <branch>
  ```
  Re-run the parallel discovery from Step 1b to refresh all state.

## Step 3: Handle Existing PR

Using the PR check result from Step 1 — no additional commands needed.

- If **no existing PR**: continue to Step 4.
- If a PR **already exists**:

  Use `AskUserQuestion`:
  > "A PR already exists for this branch: **#<number> — <title>** (<url>). Would you like to edit it?"
  >
  > - **Yes, edit the existing PR**
  > - **No, create a new one** (note: `gh pr create` will fail; warn the user)

  - **Yes**:
    - If there are **uncommitted changes or commits ahead of `main`** (already known from Step 1): continue to Step 4 as normal. Load the existing PR body as the starting point for the draft in Step 6, and use `gh pr edit` in Step 8.
    - If there is **nothing new** (clean + zero commits ahead): skip directly to Step 6. Load the existing PR title and body:
      ```bash
      gh pr view <pr-number> --repo <org>/<repo> --json title,body
      ```
      Pre-populate the draft, tell the user there are no code changes, and ask if they'd like to update the PR description. Use `gh pr edit` in Step 8 and skip the push.
  - **No**: continue to Step 4 (warn the user that `gh pr create` will fail since a PR already exists for this branch).

## Step 4: Handle Uncommitted Changes

Check for uncommitted changes:
```bash
git -C <repo-path> status --short
```

If there are **no uncommitted changes**, skip to Step 5.

If uncommitted changes are present, immediately kick off both diff commands **in parallel** — results will be ready by the time the user responds:
```bash
git -C <repo-path> diff HEAD          # run in parallel
git -C <repo-path> diff --stat HEAD   # run in parallel
```

Then ask the user using `AskUserQuestion`:

> "There are uncommitted changes. Would you like to commit them before creating the PR?"
>
> - **Yes, commit them**
> - **No, skip — include as-is**

- If **No**: proceed to Step 5 without committing.
- If **Yes**: continue below using the pre-fetched diff results.

Summarise the changes using the pre-fetched diff results and suggest a short commit message in conventional commit format (e.g. `fix: correct skill step ordering`).

While waiting for the user's response, kick off the Step 5 diff commands **in the background** so results are ready immediately after they answer. If the user chooses **Commit** or **Edit** (a new commit will be made), discard the pre-fetched results and re-run the diff after the commit completes.

Output **Changes:** `<summary of diff>` as a text line before the question.

Then ask using `AskUserQuestion`, embedding the commit message directly in the question text so it is always visible:

> "Commit with this message?
> `<commit message>`"
>
> - **Commit** — use the suggested message
> - **Edit** — provide a different message
> - **Skip** — don't commit, proceed to Step 5

- **Commit**: Stage all changes and commit with the message:
  ```bash
  cd <repo-path> && git add -A && git commit -m "<commit message>"
  ```
  Only append `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` to the commit message if Claude actually wrote or modified the file content being committed. If Claude only drafted the commit message and the user made all the file changes, do **not** add the co-author trailer.
- **Skip**: proceed to Step 5 using the pre-fetched diff results.
- **Edit**: ask the user for the message, re-display for confirmation, then commit once approved.

Once committed (or skipped), continue to Step 5.

## Step 5: Inspect the Diff

Use pre-fetched results from Step 4 if available. Otherwise run all three commands **in parallel**:
```bash
git -C <repo-path> log origin/main..HEAD --oneline   # parallel
git -C <repo-path> diff origin/main...HEAD --stat     # parallel
git -C <repo-path> diff origin/main...HEAD            # parallel
```

Use this to understand:
- What commits are included
- Which files changed and how
- The nature of the changes (new feature, fix, config change, etc.)

## Step 6: Draft the PR Message

**6a. Check for thin diffs (version bumps)**

Before drafting, inspect the diff for patterns that indicate the change is only a version number update — e.g.:
- A single line change like `version = "1.2.3"` → `version = "1.3.0"` in a Terraform module, `Chart.yaml`, `package.json`, `go.mod`, or similar
- The diff contains no logic changes, only a version string update

If a version bump is detected, ask the user before drafting:

> "This looks like a version bump (e.g. `<module-or-package>` from `<old>` to `<new>`). Can you share the upstream PR or changelog that describes what changed in this version? This will be included in the PR description."

Wait for the user's response. They may provide:
- A PR URL (e.g. `https://github.com/org/repo/pull/123`)
- A changelog entry or release notes
- A Linear ticket
- A brief description of what the version update includes

If the user has no reference, note that in the PR body and proceed.

**6b. Minimum requirements check**

Before drafting, verify the diff provides enough context to fill in each section meaningfully:

- **Summary**: At least one concrete statement of what changed. If the diff is a version bump with no upstream reference, flag this as thin.
- **Why**: Must explain motivation. If the diff gives no clues and the user provided no context, ask: *"What's the reason for this change? (e.g. bug fix, security patch, new feature in the module)"*
- **Test plan**: At least one checkable item. If the change is infrastructure-only with no observable behaviour, note how to verify the deployment succeeded.

Do not draft until the Why can be filled in with real information.

**6c. Draft**

Based on the diff and any upstream references provided, produce the PR message and display it as rendered markdown (not inside a code fence). Format:

---
**Title:** `<title>`

## Summary

- <bullet: what changed>
- <bullet: what changed>

## Why

<Explain the motivation. For version bumps, summarise what changed in the upstream module/package and link to the upstream PR or changelog.>

## References

- <upstream PR / changelog / Linear ticket if applicable>

## Test plan

- [ ] <how to verify this works>
- [ ] <edge cases to check>
---

Rules:
- Title: short and imperative (under 70 chars), describes the change
- For version bumps: title should name the module and new version (e.g. `bump terraform-modules/eks to v1.3.0`)
- Surface any external references found in commit messages, code comments, or user-provided context
- Keep the Why grounded in real information — don't invent motivation

## Step 7: Iterate on the Message

Ask using `AskUserQuestion`:

> "Does this PR message look good?"
>
> - **Looks good, create the PR**
> - **Adjust — I'll describe the changes**

If the user wants adjustments, incorporate their feedback, re-display the full draft, and ask again with the same `AskUserQuestion` until confirmed.

## Step 8: Create the PR

Apply the permission decision from the Pre-flight check — run commands directly or display them for manual execution as appropriate.

All commands must be run from within the repo directory (`<repo-path>`). Use `cd <repo-path> &&` as a prefix for `gh` commands since they have no `-C` equivalent.

**Check whether a push is needed:**
```bash
git -C <repo-path> status -sb
```

- If the output shows `ahead` commits, a push is required — run it:
  ```bash
  cd <repo-path> && git push -u origin <branch-name>
  ```
- If the branch is already up to date with the remote (no `ahead` indicator), skip the push entirely.

**Create or update the PR:**

If this is a **new PR**:
```bash
cd <repo-path> && gh pr create \
  --title "<approved title>" \
  --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

If this is an **existing PR** (editing):
```bash
cd <repo-path> && gh pr edit <pr-number> \
  --title "<approved title>" \
  --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

Output the PR URL once done.
