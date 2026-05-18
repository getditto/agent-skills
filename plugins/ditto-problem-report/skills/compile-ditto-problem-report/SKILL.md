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
12. **Impact / scope** — number of users or devices affected, severity (data loss vs. degraded sync vs. annoyance), production vs. development.
13. **Workarounds tried** and their outcomes.
14. **Application code** — how the application uses the Ditto SDK. Collect in this preference order:
    1. **Full application source** (best) — a path to the project root or a `.zip`/`.tar.gz` of it. Copy it into the bundle directory as `app/` (or the archive verbatim). If the project is large, ask the user to exclude `node_modules/`, `build/`, `target/`, `Pods/`, `.gradle/`, etc. before zipping.
    2. **A minimal reproducer repo URL** — record the URL, branch, and commit SHA. No file copy needed.
    3. **Code snippets** (fallback when neither is possible) — the user pastes representative excerpts. Ask specifically for: SDK initialization (identity / auth / app ID / sync URL / persistence directory), sync subscription setup (`registerSubscription` or `sync.registerSubscription`, including the DQL), observer / store-observer / live-query setup, the DQL statements the app issues (SELECT/INSERT/UPDATE/DELETE/EVICT), any transaction/batch usage, attachment usage, and any custom transport / device-name / role configuration. Embed each snippet in the report as a fenced code block with the source language tag (e.g. ` ```swift `, ` ```kotlin `, ` ```ts `).
    
    Always note whether what was provided is "full source", "reproducer repo", or "snippets only" so the recipient knows what level of fidelity to expect.
15. **Attachments** — Ditto SDK logs, app logs, OS/system logs, screenshots, sample queries or documents, packet captures, Big Peer HTTP API request/response captures, portal screenshots. List filenames + brief description; copy the files into the bundle directory.

Optional but useful:
- DQL query text or subscription queries involved (if not already captured under Application code).
- Network conditions (Wi-Fi SSID, NAT type, VPN, firewall).
- App ID / online playground ID (redacted as appropriate).

## Interview rules

- Open by reading whatever context the user has already given. **Do not re-ask for fields they have already supplied.**
- Batch related questions in a single `AskUserQuestion` call where possible (e.g. SDK + version + OS in one batch per device).
- For each required field, accept "unknown" or "skip" — never block the report on a missing field. Record "unknown" verbatim in the report so the recipient knows it was asked.
- After the first round of questions, summarise back what you have and ask only about remaining gaps.
- When the user says "that's everything" or similar, stop interviewing and proceed to assembly.

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

If the audience is internal Ditto staff and the report is written, ask: "Would you like to file this as a Linear issue? (yes / no)". If yes:

1. Use `mcp__linear-server__list_teams` to confirm the team (default to the SDKs team unless the report is clearly about Big Peer infrastructure, in which case ask).
2. Use `mcp__linear-server__save_issue` with:
   - `title`: the one-sentence summary.
   - `description`: the full Markdown report body.
   - `team`: the chosen team.
   - Leave priority/labels for the user to set in Linear UI unless they specify.
3. Print the Linear issue URL.
4. Note in the chat that attachments must be uploaded manually in Linear's UI (MCP cannot upload binary files from a local path in this flow).

If external, instead print: "Email this report (and attach the `.zip` if one was created) to support@ditto.com, or paste it into your existing support thread."

## Supplementary files

- `platform-logs.md` — per-platform log gathering instructions (Android, iOS/macOS, Linux, Windows, JS/Web/Node, C++/Rust/Go/.NET/Flutter SDKs, Big Peer portal). Read this when the user needs help locating logs.
- `report-template.md` — the exact Markdown template the report renders to. Always use this; do not invent your own structure.
