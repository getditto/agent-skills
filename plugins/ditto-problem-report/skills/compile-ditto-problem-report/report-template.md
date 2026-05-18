# Report template

Render the report using exactly the following structure. Replace every `{{placeholder}}`. For fields the user marked unknown, write the literal word `unknown` (not the placeholder). Omit entire optional sections only if the user explicitly indicates they do not apply (e.g. omit the **Big Peer** section if the problem scope is pure small-peer; omit the **Environment** and **Transports** sections if the problem scope is pure Big Peer / portal).

```markdown
# Ditto problem report — {{one-line summary}}

**Date:** {{ISO-8601 date and time, e.g. 2026-05-18 14:30 -0400}}
**Reporter:** {{name}} ({{email or handle}})
**Reporter type:** {{internal Ditto staff | external customer}}
**Customer:** {{customer / organisation name; or "Ditto (internal)" if no customer is impacted}}
**Ditto Database ID (App ID):** {{one or more database IDs, comma-separated; mark online-playground databases as "<id> (online playground)"; "unknown" only if genuinely unrecoverable}}

## Summary

{{one-sentence summary of the problem}}

**Problem scope:** {{small peer | Big Peer / portal | both}}

**Likely duplicate of:** {{URL of the matching report, or omit this line entirely if no likely duplicate was found}}

## Related reports

(Internal users only. Omit this section for external reporters or if the duplicate search found nothing — in which case use the literal text below instead of a table.)

| Source | URL | One-line summary | Classification |
| ------ | --- | ---------------- | -------------- |
| {{Linear / GitHub / Inkeep / Notion}} | {{URL}} | {{one-line summary}} | {{likely duplicate \| related \| reference}} |

(If no matches were found: `No similar reports found in Linear, GitHub, Inkeep, or Notion as of {{ISO-8601 timestamp}}.`)

(If a source was unavailable: add a line `Search skipped: {{source}} unavailable.`)

## Description

**Observed behaviour:**
{{what the user sees happening}}

**Expected behaviour:**
{{what the user expects to happen instead}}

## Environment

| Role | SDK + version | OS + version | Device / host |
| ---- | ------------- | ------------ | ------------- |
| {{e.g. peer A}} | {{e.g. Swift 4.14.2}} | {{e.g. iOS 17.4}} | {{e.g. iPhone 15 Pro}} |
| {{e.g. peer B}} | {{e.g. Kotlin 4.14.2}} | {{e.g. Android 14}} | {{e.g. Pixel 7}} |

Add one row per device, server, or container involved.

## Big Peer / portal

(Required if problem scope is "Big Peer / portal" or "both". Omit if pure small-peer.)

- **Environment:** {{production | staging | on-prem | unknown}}
- **Region / cluster:** {{region, or "unknown"}}
- **Portal URL** (for portal-UI issues): {{e.g. https://portal.ditto.live/apps/.../sync}}
- **Browser + version** (for portal-UI issues): {{e.g. Chrome 124.0.6367.61}}

(Ditto Database ID(s) are recorded at the top of the report — not repeated here.)

## Transports in use

{{e.g. BLE, LAN, AWDL, WebSocket to Big Peer, or "unknown"}}

## Regression

- **Is this a regression?** {{yes | no | unknown}}
- **Last-known-good SDK version:** {{version, or "unknown"}}
- **First broken SDK version:** {{version, or "unknown"}}
- **Notes:** {{anything specific the user observed when upgrading; omit if none}}

## Reproduction steps

1. {{step 1}}
2. {{step 2}}
3. {{step 3}}

**Reproduction rate:** {{always | often | sometimes | once}}

## Occurrence times

(Use ISO-8601 with explicit timezone offset. Add one row per incident window. For ongoing problems, write the start time and `ongoing` in the end column.)

| Start                          | End                            | Notes                          |
| ------------------------------ | ------------------------------ | ------------------------------ |
| {{2026-05-18T14:30:00-04:00}}  | {{2026-05-18T14:45:00-04:00}}  | {{e.g. peer A app foregrounded; first noticed}} |

**Reporter timezone:** {{e.g. America/New_York (UTC-04:00)}}

## Impact

- **Severity:** {{data loss | sync stalled | degraded performance | annoyance | unknown}}
- **Scope:** {{number of users/devices affected; production vs. development}}

## Workarounds tried

- {{workaround 1 — result}}
- {{workaround 2 — result}}

(Write "none tried" if applicable.)

## Application code

**Fidelity provided:** {{full source | reproducer repo | snippets only}}

(If full source or a reproducer repo was provided, record the location below. Then omit the snippets sub-sections.)

- **Bundled source:** {{path inside the zip, e.g. `app/`, or "n/a"}}
- **Reproducer repo:** {{URL, branch, commit SHA, or "n/a"}}

(If only snippets were provided, fill in the relevant sub-sections below. Omit any sub-section the user didn't provide.)

### SDK initialization

\`\`\`{{language}}
{{init code — identity, auth, app ID, sync URL, persistence directory, log level}}
\`\`\`

### Sync subscriptions

\`\`\`{{language}}
{{registerSubscription / sync.registerSubscription calls and the DQL strings}}
\`\`\`

### Observers / live queries

\`\`\`{{language}}
{{store observer or live-query registration}}
\`\`\`

### DQL statements issued by the app

\`\`\`sql
{{SELECT / INSERT / UPDATE / DELETE / EVICT statements; include parameter binding patterns}}
\`\`\`

### Transactions / batch operations

\`\`\`{{language}}
{{transaction usage, if any}}
\`\`\`

### Attachments / custom transports / other config

\`\`\`{{language}}
{{attachment fetch/put, transport overrides, device name, role config — whichever is relevant}}
\`\`\`

## Attachments

| File | Description |
| ---- | ----------- |
| {{filename in zip}} | {{e.g. Ditto SDK debug log from peer A, captured 2026-05-18 14:25 UTC}} |

(Omit this section if no attachments. Note "logs unavailable" if the user could not capture any.)

## Log excerpts

### {{attachment filename}} (lines {{start}}–{{end}})

\`\`\`text
{{truncated log excerpt, ~200 lines max}}
\`\`\`

(Repeat per attached log. Note the full file is bundled in the zip.)

## Additional notes

{{anything else the user wants to add — DQL query text, screenshots referenced inline, network conditions, etc. Omit if nothing.}}

## Suggested next steps

(Omit this entire section if the report has zero gaps. Otherwise list the most-valuable suggestions the user can take to fill `unknown` fields or missing attachments. Tailor each suggestion to what's already known — give concrete commands or paths, not generic advice.)

1. {{suggestion 1 — e.g. "Capture Ditto SDK debug logs on the affected Android device: `DittoLogger.setMinimumLogLevel(LogLevel.DEBUG)`, reproduce, then `adb -s <serial> logcat -d -v threadtime > ditto-android.log`. Re-run with `update` to attach."}}
2. {{suggestion 2}}
3. {{suggestion 3}}

(Cap at 5. Prioritise: logs > regression info > occurrence-time precision > device/OS specifics > impact-data refinement.)

## Update log

(One row per revision. New reports start with a single "initial report" entry. Each later update appends a row.)

| Timestamp                         | Updated by                | Changes                                     |
| --------------------------------- | ------------------------- | ------------------------------------------- |
| {{report creation ISO timestamp}} | {{reporter name + email}} | initial report                              |
```
