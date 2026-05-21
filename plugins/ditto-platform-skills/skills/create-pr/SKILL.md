---
name: create-pr
description: Create a GitHub pull request. Use when user asks to create a PR, open a pull request, or submit changes for review. Confirms the repo, handles branch creation if on main, drafts a PR message from the diff, and creates the PR via gh.
allowed-tools: Bash
---

# Create Pull Request

Guides the user through creating a GitHub PR: confirm the repo, ensure a feature branch exists, draft a message from the diff, iterate with the user, then create the PR.

## Step 1: Confirm the Repo

Detect the current repo:
```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

- If the user specified a repo (e.g. "create a PR for cloud-infra-apps"), use that name — skip confirmation.
- Otherwise, show the detected repo and ask: **"Create a PR for `<org>/<repo>`?"** Wait for confirmation before continuing.

## Step 2: Check the Current Branch

```bash
git rev-parse --abbrev-ref HEAD
```

- If the branch is **not** `main` or `master`, continue to Step 3.
- If the branch **is** `main` or `master`:
  1. Ask: **"You're on `main`. What should the new branch be named?"**
  2. Once the user provides a name, display this command for them to run (do NOT run it directly):
     ```
     git checkout -b <branch-name>
     ```
  3. Wait for the user to confirm they've created and switched to the branch, then continue.

## Step 3: Inspect the Diff

Run in parallel:
```bash
git log main..HEAD --oneline
git diff main...HEAD --stat
git diff main...HEAD
```

Use this to understand:
- What commits are included
- Which files changed and how
- The nature of the changes (new feature, fix, config change, etc.)

## Step 4: Draft the PR Message

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

## Step 5: Iterate on the Message

Ask: **"Does this look good, or would you like to adjust anything?"**

Incorporate any feedback and re-display until the user confirms.

## Step 6: Create the PR

Once the user approves, push the branch and create the PR:

```bash
git push -u origin <branch-name>
```

Then create the PR:
```bash
gh pr create \
  --title "<approved title>" \
  --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

Output the PR URL once created.
