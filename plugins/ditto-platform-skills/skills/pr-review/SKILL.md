---
name: pr-review
description: Review a pull request. Use when user asks to review a PR, check a pull request, or do a code review. Works on the current branch or by PR number.
allowed-tools: Bash, Agent, Read, Glob, Grep
---

# PR Review

Review a pull request with a structured 3-section report, saved to disk with an option to post as a PR comment.

## Step 1: Identify the PR

If no PR number was provided, run:
```bash
gh pr list
```
Use the current branch name to identify the relevant PR, or ask the user to pick one.

Once the PR number is known, fetch details and diff in parallel:
```bash
gh pr view <number>
gh pr diff <number>
```

## Step 2: Analyze the Changes

For small diffs, analyze directly. For large diffs (>500 lines), spawn an Explore agent to read the key source files alongside the diff so the review is grounded in full context rather than just the delta.

## Step 3: Write the Report

Produce a report with this exact structure:

```
## Code Review — <feature name>

**Verdict: READY / NOT READY**
<one sentence reason>

### Does it do what it says?
<verify every claimed feature or fix is actually implemented; call out anything missing or incomplete>

### Is it covered by tests?
<list what is tested and what is not; flag untested critical paths>

### Code smells or errors?
<flag real bugs with file:line references; note FIXMEs worth addressing; call out what was checked and found clean>
```

Formatting rules:
- Verdict goes at the top — reviewers should see it immediately
- No redundant metadata (author, branch, date — already visible on the PR)
- Write directly to the author, not about them
- Fold minor FIXMEs into the relevant section rather than giving them standalone headings
- Keep file:line references, code blocks, and bullet structure throughout

## Step 4: Save the Report

Determine the repo name from `gh repo view --json name -q .name` and save to:
```
~/PR-reports/<repo-name>/pr_<number>_review.md
```

Create the directory if it doesn't exist:
```bash
mkdir -p ~/PR-reports/<repo-name>
```

## Step 5: Security Review (optional)

Ask the user: "Do you want a security review as well?"

If yes, invoke the `security-review` skill and incorporate its findings into the report under a new section:

```
### Security
<findings from security review, or "No issues found">
```

Then save the updated report.

## Step 6: Inline Blocking Comments (optional)

After writing the report, collect every item from the **Does it do what it says?** and **Code smells or errors?** sections that represents a required change — broken behaviour, bugs, missing logic, or anything that should block merging.

Walk the user through each item one at a time, asking whether to include it as a review comment:

```
I found N blocking items. I'll go through each — reply yes/no to include it.

[1/N] `src/auth/token.go:88` — tokens are never invalidated on logout; any logged-out token remains valid until expiry.
Include this comment? (yes/no)

[2/N] `pkg/handler/upload.go:34` — file size is not validated before writing to disk; could exhaust disk space.
Include this comment? (yes/no)
...
```

Collect all the confirmed items. Once the user has gone through all of them:

1. Get the PR head commit SHA:
   ```bash
   gh pr view <number> --json headRefOid -q .headRefOid
   ```

2. Get `{owner}/{repo}`:
   ```bash
   gh repo view --json nameWithOwner -q .nameWithOwner
   ```

3. Post all confirmed items as a single batched PR review requesting changes:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<number>/reviews \
     -f event="REQUEST_CHANGES" \
     -f body="Blocking issues identified during review — see inline comments." \
     -f "comments[][path]=<file>" \
     -F "comments[][line]=<line>" \
     -f "comments[][body]=<comment>" \
     -f "comments[][side]=RIGHT"
   ```
   Repeat the `comments[]` fields for each confirmed item in the same API call.

4. Confirm with the user once posted — this will mark the PR as "Changes requested" on GitHub.

**Note:** If the user confirms zero items, skip posting entirely.

## Step 7: Inline Nit Comments (optional)

After writing the report, collect every item from the **Code smells or errors?** section that has a specific `file:line` reference and is a nit, suggestion, or minor style issue (not a blocking bug).

Present them to the user as a numbered list:
```
I found N nit items with file/line references. Post these as inline PR comments?

1. `src/foo.go:42` — nit: unused import
2. `pkg/bar/baz.go:17` — suggestion: prefer errors.Is over == comparison
...
```

If the user says yes:

1. Get the PR head commit SHA:
   ```bash
   gh pr view <number> --json headRefOid -q .headRefOid
   ```

2. Post all nit comments as a single batched PR review using the GitHub API:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<number>/reviews \
     -f event="COMMENT" \
     -f "comments[][path]=<file>" \
     -F "comments[][line]=<line>" \
     -f "comments[][body]=<comment>" \
     -f "comments[][side]=RIGHT"
   ```
   Repeat the `comments[]` fields for each nit item in the same API call.

   Get `{owner}/{repo}` from:
   ```bash
   gh repo view --json nameWithOwner -q .nameWithOwner
   ```

3. Confirm with the user once posted — these are publicly visible on the PR.

**Note:** Only include nits in this step. Blocking issues should remain in the report and be discussed separately.

## Step 8: Post Full Report as PR Comment (optional)

Ask the user: "Do you want to post the full review report as a PR comment?"

If yes, confirm first — this is publicly visible — then run:
```bash
gh pr comment <number> --body-file ~/PR-reports/<repo-name>/pr_<number>_review.md
```
