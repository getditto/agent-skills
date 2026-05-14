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

## Step 6: Post as PR Comment (optional)

Ask the user: "Do you want to post this review as a PR comment?"

If yes, confirm first — this is publicly visible — then run:
```bash
gh pr comment <number> --body-file ~/PR-reports/<repo-name>/pr_<number>_review.md
```
