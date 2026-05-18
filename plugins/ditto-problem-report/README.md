# ditto-problem-report

Claude Code plugin for compiling structured bug reports about Ditto SDK and Big Peer issues.

## What it does

This plugin helps you (or your customer) produce a complete, well-structured bug report for a Ditto issue. It captures the fields a Ditto support or SDKs engineer needs to triage:

- The Ditto SDK(s) in use and their exact versions
- Operating systems and device models for every peer involved
- Whether the problem is a regression and the last-known-good SDK version
- Big Peer environment, app ID, and region (when applicable)
- Transports in use (BLE, LAN, AWDL, WebSocket)
- Reproduction steps and reproduction rate
- Impact and scope
- Ditto SDK logs, app logs, and OS logs (with truncated excerpts embedded inline and the originals bundled)

## Output

- **No attachments:** a single Markdown file `ditto-problem-report-YYYYMMDD-HHMMSS-<slug>.md` in the current directory, where `<slug>` is a short kebab-case rendering of the problem summary (e.g. `sync-stops-after-backgrounding-ios`).
- **With attachments:** a `.zip` archive `ditto-problem-report-YYYYMMDD-HHMMSS-<slug>.zip` containing `report.md` plus all attachments.
- **Internal Ditto users only:** an option at the end to file the report as a Linear issue. The Linear URL is written back into the report's header so subsequent updates can target it without re-asking.

### Updating a report

When new information arrives later (logs you couldn't capture initially, another affected device, a sharper reproduction recipe), update the existing report in place — the original filename, timestamp, and slug are preserved. Each update appends a row to an **Update log** section at the bottom of the report so the recipient can see what changed and when.

```
/ditto-problem-report update ditto-problem-report-20260518-143000-sync-stops-ios.md
```

Or just describe what to add and the skill will find the file:

> "Add the iOS logcat I just captured to my problem report"

If the original was a bare `.md` and the update adds the first attachment, the report is automatically promoted to a `.zip` bundle with the same timestamp and slug. For reports that were already filed as Linear issues (the URL is recorded in the report's `**Filed as Linear:**` header), internal users are offered the option to post the delta as a comment on the existing issue rather than refiling.

## What this plugin provides

- **Slash command `/ditto-problem-report`** — entry point users invoke explicitly. Accepts an optional initial problem statement as its argument.
- **Skill `compile-ditto-problem-report`** — auto-activates when the user mentions filing a Ditto bug report. Holds the interview flow, log-ingestion rules, output template, and Linear-issue handoff. Includes a `platform-logs.md` reference covering Android, iOS/macOS, Linux, Windows, JS/Web/Node, and all Ditto SDK variants.
- **Agent `problem-report-collector`** — subagent the main Claude can delegate to for an isolated interview context.

## Installation

```bash
# Add the marketplace
/plugin marketplace add getditto/claude-code-plugins

# Install the plugin
/plugin install ditto-problem-report
```

## Usage

Three ways to start:

1. **Slash command** — `/ditto-problem-report Sync stops after backgrounding on iOS 17`
2. **Natural language** — "I want to file a Ditto bug report" (the skill auto-activates).
3. **Delegated agent** — ask Claude to use the `problem-report-collector` agent.

In all three cases, Claude will interview you only for fields you have not already supplied, ingest any logs you provide, and write the report into your current directory.

## Audience handling

The plugin works for both external Ditto customers and internal Ditto staff. Audience is detected from `git config user.email` (an `@ditto.com` address signals internal) and the conversation context, with a single fallback question if uncertain. Internal users see an "open in Linear" option after the file is written; external users see instructions to email `support@ditto.com`.

## Links

- [Ditto Documentation](https://docs.ditto.com)
- [Ditto Support](mailto:support@ditto.com)
