---
name: create-pr
description: Create a GitHub pull request. Use when user asks to create a PR, open a pull request, or submit changes for review. Confirms the repo, handles branch creation if on main, drafts a PR message from the diff, and creates the PR via gh.
allowed-tools: Bash
---

# Create Pull Request

Guides the user through creating a GitHub PR: confirm the repo, ensure a feature branch exists, draft a message from the diff, iterate with the user, then create the PR.

## Pre-flight: Permission Check

Before running any commands, check whether a global rule (e.g. in `~/.claude/CLAUDE.md`) restricts running state-modifying commands like `git push`, `git commit`, `git checkout -b`, or `gh pr create`/`gh pr edit`.

If such a restriction exists, ask the user **once** at the start:

> "A global rule restricts me from running state-modifying commands. How would you like to proceed for this session?"
>
> 1. **Yes, Permanent** — Override the restriction permanently (update global settings via `update-config`)
> 2. **Yes, Session** — Override for this session only; don't ask again until next session
> 3. **Yes, This time** — Run commands this once; ask again next time the skill runs
> 4. **No, Provide the commands** — Display all state-modifying commands for manual execution throughout

Store the user's choice and apply it consistently for every state-modifying command throughout the rest of the skill. Do **not** ask again per-command.

- **Yes, Permanent**: invoke the `update-config` skill to add the relevant commands to global allowed settings, then proceed.
- **Yes, Session**: note the override in memory for this session and proceed.
- **Yes, This time** / **No**: apply the choice silently for the rest of this skill run.

If no restriction exists, proceed directly to Step 1.

> **Note:** Read-only commands (`git status`, `git diff`, `git log`, `gh pr list`, `gh repo view`, etc.) are never restricted and can always be run directly.

## Step 1: Discover Repo, Branch, and Existing PR

**1a. Identify the repo path**

- If the user specified a repo (e.g. "create a PR for cloud-infra-apps"), resolve `<repo-path>` from that name and skip the directory listing.
- If **no repo was specified**, run:
  ```bash
  ls -1d */
  ```
  Present the list and ask: **"Which repo should I create a PR for?"** Wait for the answer before continuing.

**1b. Once the repo path is known, run all discovery in parallel:**

```bash
cd <repo-path> && gh repo view --json nameWithOwner -q .nameWithOwner
git -C <repo-path> rev-parse --abbrev-ref HEAD
git -C <repo-path> status --short
git -C <repo-path> rev-list --count main..HEAD
```

This gives us: the GitHub repo name, the current branch, uncommitted changes, and commit count ahead of `main` — all before asking the user anything.

**1c. With branch name now known, immediately check for an existing PR:**

```bash
gh pr list --repo <org>/<repo> --head <branch-name> --json number,title,url --limit 1
```

**1d. Present the full picture to the user in one summary:**

> Repo: `<org>/<repo>`
> Branch: `<branch-name>`
> Uncommitted changes: Yes / No
> Commits ahead of main: `<N>`
> Existing PR: #<number> — <title> (<url>) / None

Then ask for confirmation:

> "Proceed with this repo and branch?"

Wait for confirmation before continuing.

## Step 2: Handle Branch State

Using the branch discovered in Step 1 — no additional commands needed.

**If on `main` or `master`:**

A feature branch is required. Tell the user:

> "You're on `main`. A branch is required before creating a PR. What should the new branch be named?"

Wait for the user to provide a name. Run the checkout directly — unless a global restriction is in effect and no override has been granted, in which case display it and wait for confirmation:
```bash
git -C <repo-path> checkout -b <branch-name>
```

Do not proceed until the branch has been created and switched to. Re-run the parallel discovery from Step 1b to refresh all state for the new branch.

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

  > "A PR already exists for this branch: **#<number> — <title>**
  > <url>
  >
  > Would you like to edit the existing PR instead of creating a new one?"

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

If uncommitted changes are present, ask the user:

> "There are uncommitted changes in this repo. Would you like to commit them before creating the PR?"

- If **No**: proceed to Step 5 without committing.
- If **Yes**: continue below.

Inspect what changed against the current HEAD:
```bash
git -C <repo-path> diff HEAD
git -C <repo-path> diff --stat HEAD
```

Summarise the changes and suggest a short commit message in conventional commit format (e.g. `fix: correct skill step ordering`). Present it to the user:

> "Here's what changed:
> `<summary of diff>`
>
> Suggested commit message:
> `<commit message>`
>
> **Y / N / E** — Commit with this message / Skip / Edit the message"

- **Y (Yes)**: Stage all changes and commit with the message:
  ```bash
  cd <repo-path> && git add -A && git commit -m "<commit message>"
  ```
- **N (No)**: Skip the commit and continue to Step 5.
- **E (Edit)**: Let the user provide or refine the message, re-display for confirmation, then commit once approved.

Once committed (or skipped), continue to Step 5.

## Step 5: Inspect the Diff


Run in parallel:
```bash
git -C <repo-path> log main..HEAD --oneline
git -C <repo-path> diff main...HEAD --stat
git -C <repo-path> diff main...HEAD
```

Use this to understand:
- What commits are included
- Which files changed and how
- The nature of the changes (new feature, fix, config change, etc.)

## Step 6: Draft the PR Message

Based on the diff, produce a draft PR message:

```
## Summary

- <bullet: what changed>
- <bullet: what changed>

## Why

<Explain the motivation — what problem this solves or what it enables. Reference any upstream issues, external PRs, or Linear tickets if present in commit messages or code comments.>

## Test plan

- [ ] <how to verify this works>
- [ ] <edge cases to check>
```

Rules:
- Title: short and imperative (under 70 chars), describes the change
- Surface any external references found in commit messages or code comments (e.g. upstream PRs, issue links)
- Keep the Why grounded in the diff — don't invent motivation

Display the full draft (title + body) to the user.

## Step 7: Iterate on the Message

Ask: **"Does this look good, or would you like to adjust anything?"**

Incorporate any feedback and re-display until the user confirms.

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
