---
name: compile-ditto-problem-report
description: Use when the user wants to file a Ditto bug report, report a problem with a Ditto SDK or Big Peer, prepare a support ticket for Ditto, or compile diagnostic information about a Ditto SDK / mesh / Big Peer issue. Conducts a structured interview, then produces a Markdown report (or a .zip bundle when logs/attachments are supplied) and optionally files a Linear issue for internal Ditto staff.
---

# Compile a Ditto problem report

This skill produces a structured bug report for a Ditto SDK or Big Peer issue. The user may be an external Ditto customer or a Ditto staff engineer. The same interview drives both; the only difference is what is offered at the end (external: instructions to send to support; internal: option to file a Linear issue).

## What this skill produces

- **Default output:** a single Markdown file `ditto-problem-report-YYYYMMDD-HHMMSS.md` in the current working directory.
- **If any logs or attachments are supplied:** a directory `ditto-problem-report-YYYYMMDD-HHMMSS/` containing `report.md` plus all attachments, zipped to `ditto-problem-report-YYYYMMDD-HHMMSS.zip` in the current working directory.
- **Internal users only (optional):** after the file/zip is written, offer to file a Linear issue with the report body via the `linear-server` MCP.

Always print the final path of what was written (Markdown file or zip) on the last line of your response.

## Required fields

The report must include the following before being considered complete. Drive the interview to fill in any that the user has not already supplied. Mark optional items clearly.

1. **One-sentence summary** of the problem.
2. **Problem scope** — is this a **small-peer** problem (Ditto SDK on a device / app / edge server), a **Big Peer / portal** problem (Ditto cloud, HTTP API, or portal UI), or **both** (a mesh issue involving sync between small peers and Big Peer, or a behaviour that only manifests when both are in the loop)? Ask this early — the answer routes the rest of the interview (e.g. skip Big Peer environment questions for a pure small-peer problem; skip transport questions for a pure portal problem).
3. **Detailed description** — observed behaviour vs. expected behaviour.
4. **Ditto SDK(s) in use** — for each, the language/platform variant (Swift, Kotlin/Java, JS/TS, React Native, C++, Rust, Go, .NET / MAUI, Flutter) **and** the exact version (e.g. `4.14.2`, `5.0.0-alpha.3`). If the deployment involves multiple SDKs syncing in a mesh, list every variant + version present. (Skip if scope is pure Big Peer / portal and no SDK is involved.)
5. **Big Peer details** (required if scope is "Big Peer / portal" or "both") — environment (production / staging / on-prem), app ID, and region/cluster if known. For portal-UI issues, also capture the portal page URL and browser + version.
6. **Operating system(s) + versions** — for every device, server, or container involved (e.g. `iOS 17.4`, `Android 14 (Pixel 7)`, `macOS 14.5 (M2)`, `Ubuntu 22.04 x86_64`, `Windows 11 23H2`).
7. **Device models** where relevant (`Pixel 7`, `iPhone 15 Pro`, `Galaxy S20 FE`, `Raspberry Pi 4 64-bit`, etc.).
8. **Transports** in use, if known (BLE, LAN, AWDL/MultipeerConnectivity, WebSocket to Big Peer). The user may not know — that's fine. (Skip if scope is pure Big Peer / portal.)
9. **Regression status** — was this working in a previous SDK version (or, for portal issues, a previous portal release)? If yes, the last-known-good version and the version where it broke. If they don't know, mark "unknown".
10. **Reproduction steps** — numbered list. If not reliably reproducible, capture what *is* known (timing, frequency, conditions).
11. **Reproduction rate** — always / often / sometimes / once.
12. **When did it happen** — one or more concrete date/time windows when the problem was observed, in **ISO-8601 with an explicit timezone offset** (e.g. `2026-05-18T14:30:00-04:00` to `2026-05-18T14:45:00-04:00`). If multiple incidents, list each as its own window. Also record the **timezone the user is in** so a recipient reading raw UTC logs knows how to convert. This is the single most useful field for narrowing Datadog dashboards and SDK / Big Peer log searches, so push for the most precise answer the user can give — minute-level if possible, otherwise hour-level, otherwise "around <date> in the afternoon, EST". If the problem is ongoing / continuous rather than a discrete event, say so and capture the start time (and "ongoing" as the end). If the user doesn't know, mark "unknown" but try once to refresh their memory ("when did you first notice it?", "when did you last see it?").
13. **Impact / scope** — number of users or devices affected, severity (data loss vs. degraded sync vs. annoyance), production vs. development.
14. **Workarounds tried** and their outcomes.
15. **Application code** — how the application uses the Ditto SDK. Collect in this preference order:
    1. **Full application source** (best) — a path to the project root or a `.zip`/`.tar.gz` of it. Copy it into the bundle directory as `app/` (or the archive verbatim). If the project is large, ask the user to exclude `node_modules/`, `build/`, `target/`, `Pods/`, `.gradle/`, etc. before zipping.
    2. **A minimal reproducer repo URL** — record the URL, branch, and commit SHA. No file copy needed.
    3. **Code snippets** (fallback when neither is possible) — the user pastes representative excerpts. Ask specifically for: SDK initialization (identity / auth / app ID / sync URL / persistence directory), sync subscription setup (`registerSubscription` or `sync.registerSubscription`, including the DQL), observer / store-observer / live-query setup, the DQL statements the app issues (SELECT/INSERT/UPDATE/DELETE/EVICT), any transaction/batch usage, attachment usage, and any custom transport / device-name / role configuration. Embed each snippet in the report as a fenced code block with the source language tag (e.g. ` ```swift `, ` ```kotlin `, ` ```ts `).
    
    Always note whether what was provided is "full source", "reproducer repo", or "snippets only" so the recipient knows what level of fidelity to expect.
16. **Attachments** — Ditto SDK logs, app logs, OS/system logs, screenshots, sample queries or documents, packet captures, Big Peer HTTP API request/response captures, portal screenshots. List filenames + brief description; copy the files into the bundle directory.

Optional but useful:
- DQL query text or subscription queries involved (if not already captured under Application code).
- Network conditions (Wi-Fi SSID, NAT type, VPN, firewall).
- App ID / online playground ID (redacted as appropriate).

## Interview rules

**The interview must be lightweight.** Every question costs the user time. Mine existing context first, infer where you can, and ask only for what's genuinely missing and genuinely useful for the recipient.

### Step 1 — extract what's already known (no questions)

Before asking anything, harvest from:

- **The current conversation** — the user's initial problem statement, file paths they've mentioned, code they've shown you, commands they've run, prior tool output. Anything they've already said is "supplied".
- **`git config user.email`** — for the Reporter email; and to decide internal vs. external audience (`@ditto.com` ⇒ internal).
- **`git config user.name`** — for the Reporter name.
- **`date +%Y-%m-%dT%H:%M:%S%z` and `date +%Z`** — for the report's Date field and the reporter's timezone (e.g. for the Occurrence times section's `Reporter timezone:`).
- **Current working directory contents** — `ls`, `cat` of obvious manifest files (`package.json`, `Cargo.toml`, `pubspec.yaml`, `*.csproj`, `build.gradle`, `Package.swift`, `Podfile.lock`) to infer the Ditto SDK variant and version without asking.
- **Any log files the user has already supplied or referenced** — they often contain the SDK version, OS, device model, and timestamps verbatim. Extract those instead of asking.

Tell the user briefly what you found ("I see you're on macOS 14.5 with the Swift SDK 4.14.2 from Package.swift — let me know if that's wrong") and ask them to correct anything inferred wrongly. **Do not re-ask for inferred values.**

### Step 2 — apply scope-based skipping

Once you have the problem scope (small peer / Big Peer / both), skip whole categories:

- **Pure small-peer scope** → skip Big Peer / portal questions, skip portal URL / browser version.
- **Pure Big Peer / portal scope** → skip Transports, skip per-device Environment rows (except the browser for portal-UI issues), skip Application code unless the user is using the HTTP API from app code.
- **Pure portal-UI scope** → also skip SDK version (portal UI is server-rendered).
- **Regression = no** → skip "last-known-good version" and "first broken version" follow-ups.
- **No attachments offered** → skip log-excerpt prompts.
- **Reproduction rate = "always"** → skip the "when did it happen" precision push; the user can reproduce on demand, so a generic timestamp suffices.

### Step 3 — ask only for what's left

- **Batch heavily**: combine all remaining required fields into one or two `AskUserQuestion` rounds, not field-by-field. A single batch covering "What SDKs/OS/devices are involved, and what's the one-sentence summary?" is fine.
- **For each remaining required field**, accept "unknown" or "skip" — never block the report on a missing field. Record `unknown` verbatim in the report so the recipient knows it was asked.
- **Optional fields are not interviewed.** Mention once that the report supports them ("you can add DQL snippets or network conditions later if useful") and move on.
- **Don't push for precision the user obviously doesn't have.** If they say "sometime last week", accept "around 2026-05-12, exact time unknown" and move on — don't demand minute-level.
- **No confirmation rounds.** After the first batch, do not summarise back and ask "anything else?". Assemble the report immediately with whatever you have, mark missing fields `unknown`, and tell the user where the file is.
- **When the user says "that's everything" / "just write what we have" / "good enough" — stop immediately** and proceed to assembly.

### What "lightweight" means in practice

A typical session should be: read context → one batched question round (often zero questions if context is rich) → write report. If you find yourself asking three or more rounds of follow-ups, you're over-interviewing — write what you have and let the recipient ask follow-ups directly.

## Audience detection

Determine whether the user is internal Ditto staff:

1. Check the conversation context for any `@ditto.com` email or "I work at Ditto" / "I'm on the SDKs team" signal.
2. Otherwise, run `git config user.email` via Bash and check whether it ends in `@ditto.com`.
3. If still uncertain, ask once: "Are you reporting this as a Ditto employee or as an external customer?"

Record the audience in the report's Reporter section.

## Log handling

When the user supplies logs (file path, pasted content, or directory of files):

1. **Read the file(s)** with the `Read` tool. For large logs, read in chunks; don't load the whole file if it's huge — use `Read` with `offset`/`limit` to scan, then focus on the area around the failure.
2. **Find the relevant window.** Search for the first occurrence of `ERROR`, `WARN`, `panic`, `tracing::error`, `logger.error`, exception backtraces, or the user-described error string. Capture roughly 50 lines before and 150 lines after.
3. **Embed an excerpt** in the report as a fenced code block (language `text`), preceded by the file name and the line range. Truncate to ~200 lines; note that the full file is in the zip.
4. **Copy the original file** into the bundle directory unmodified so the recipient can see full context.
5. If the user doesn't have logs handy, point them to `platform-logs.md` (in this skill directory) for instructions on how to capture them per platform, then offer to proceed with what they have.

Redaction: do **not** automatically redact tokens, app IDs, or device names — Ditto support needs them. But if the user explicitly asks for redaction, replace the value with `<REDACTED>` consistently in both the embedded excerpt and the bundled file.

## Search for related / duplicate reports (internal users only)

**Skip this section entirely for external users** — they don't have access to Linear / Notion / internal docs, and we shouldn't fabricate links they can't follow.

For internal Ditto staff, run a duplicate-search after the required fields are gathered and before output assembly. Build 2–5 short search queries from the report's known fields: the one-sentence summary, the most distinctive error string or panic message from supplied logs, the affected SDK + version, and any explicit feature name (e.g. "attachment fetch", "BLE permission", "Big Peer HTTP 503").

Hit each of the following sources in **parallel** (single message, multiple tool calls). Cap results to ~5 per source; don't grind through pagination.

- **Linear** — `mcp__linear-server__list_issues` with `query` set to each search phrase. Prefer recent open issues, but include closed ones from the last 90 days too (they're often the resolved-duplicate the user is looking for). Look across the SDKs team for SDK problems, Big Peer / Networking / Core Library teams for infra problems.
- **GitHub** (`getditto/*`) — `gh search issues --owner getditto "<query>" --json url,title,state,repository,updatedAt` for each phrase. SDK bugs are sometimes tracked in `getditto/ditto` issues rather than Linear.
- **Inkeep** — `mcp__ditto-inkeep__ask-question-about-ditto` with a one-sentence framing of the problem (e.g. "Are there known issues with attachment fetch failing on iOS 17 with Swift SDK 4.14.x?"). Inkeep surfaces docs and previously-answered customer questions and is good at catching known issues with documented workarounds.
- **Notion** — `mcp__claude_ai_Notion__notion-search` for each phrase. Surfaces post-mortems, customer-issue tracking pages, and SDK-team root-cause docs.

Skip any source that errors (auth expired, MCP unavailable) — note "search skipped: <source> unavailable" in the report and move on; don't block on it.

### Classify each hit

For each candidate result, assign one of:

- **Likely duplicate** — same SDK + version, same observable behaviour, same error string or stack frame. Very high confidence the user is hitting the same bug.
- **Related** — overlapping symptom or component but different SDK version, different root cause, or different fix. Worth linking but not a duplicate.
- **Reference** — a doc, runbook, or post-mortem that explains the area but isn't itself a bug report.

Discard everything else; don't pad the section with weak matches.

### Surface the findings

1. **In-chat to the user, before writing the report**, summarise the top hits and ask: *"This looks like a possible duplicate of [Linear PROJ-123 — same panic on iOS 17 attachment fetch]. Want to (a) file a new report linked to that issue, (b) comment on PROJ-123 instead, or (c) ignore the match and proceed?"*. Default to (a) if the user doesn't answer.
2. **In the report's `Related reports` section** (see template), list each retained hit with: source, URL, one-line summary, and classification. If there's a likely-duplicate, put a `**Likely duplicate of:** <URL>` line right under the report's Summary so it's the first thing a triager sees.
3. **When asking about Linear-issue creation later**, if the user picked option (b), skip the new-issue flow and instead use `mcp__linear-server__save_comment` to add the report body as a comment on the existing issue.

If all four sources return nothing useful (or all are unavailable), write `No similar reports found in Linear, GitHub, Inkeep, or Notion as of <timestamp>.` in the `Related reports` section and move on — that absence is itself useful information for the recipient.

## Output assembly

Use the template in `report-template.md` (same skill directory) verbatim. Fill in placeholders; for fields the user marked unknown, write `unknown` rather than leaving the placeholder.

Generate the timestamp as `YYYYMMDD-HHMMSS` local time via `date +%Y%m%d-%H%M%S` in Bash.

**No attachments path:**
```bash
date +%Y%m%d-%H%M%S
# then write ditto-problem-report-<ts>.md via the Write tool
```

**With attachments path:**
```bash
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p "ditto-problem-report-$ts"
# Write report.md inside the dir via Write tool
# Copy each attachment into the dir via cp
zip -r "ditto-problem-report-$ts.zip" "ditto-problem-report-$ts"
echo "ditto-problem-report-$ts.zip"
```

After writing, print the absolute path of the final artifact.

## Linear issue option (internal users only)

If the audience is internal Ditto staff and the report is written, choose between three flows based on what the duplicate-search found:

- **No duplicate**, or the user picked "file new" — ask: "Would you like to file this as a new Linear issue? (yes / no)". If yes:
  1. Use `mcp__linear-server__list_teams` to confirm the team (default to the SDKs team unless the report is clearly about Big Peer infrastructure, in which case ask).
  2. Use `mcp__linear-server__save_issue` with:
     - `title`: the one-sentence summary.
     - `description`: the full Markdown report body.
     - `team`: the chosen team.
     - Leave priority/labels for the user to set in Linear UI unless they specify.
  3. Print the Linear issue URL.
  4. Note in the chat that attachments must be uploaded manually in Linear's UI (MCP cannot upload binary files from a local path in this flow).
- **User picked "comment on existing"** during the duplicate-search step — use `mcp__linear-server__save_comment` to add the full report body as a comment on the duplicate issue. Print the existing-issue URL.
- **Likely duplicate found but user not yet asked** — ask: "This looks like a duplicate of <existing URL>. File a new issue, comment on the existing one, or skip Linear entirely?" then route to the corresponding flow.

If external, instead print: "Email this report (and attach the `.zip` if one was created) to support@ditto.com, or paste it into your existing support thread."

## Supplementary files

- `platform-logs.md` — per-platform log gathering instructions (Android, iOS/macOS, Linux, Windows, JS/Web/Node, C++/Rust/Go/.NET/Flutter SDKs, Big Peer portal). Read this when the user needs help locating logs.
- `report-template.md` — the exact Markdown template the report renders to. Always use this; do not invent your own structure.
