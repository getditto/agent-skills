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

- **No attachments:** a single Markdown file `ditto-problem-report-YYYYMMDD-HHMMSS.md` in the current directory.
- **With attachments:** a `.zip` archive `ditto-problem-report-YYYYMMDD-HHMMSS.zip` containing `report.md` plus all attachments.
- **Internal Ditto users only:** an option at the end to file the report as a Linear issue.

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
