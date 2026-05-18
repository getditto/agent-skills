# Report template

Render the report using exactly the following structure. Replace every `{{placeholder}}`. For fields the user marked unknown, write `unknown`; for fields the user marked as not applicable, write `n/a`. Omit entire optional sections only if the user explicitly indicates they do not apply (e.g. omit the **Big Peer** section if the problem scope is pure small-peer; omit the **Environment** and **Transports** sections if the problem scope is pure Big Peer / portal). The filename uses the form `ditto-problem-report-YYYYMMDD-HHMMSS-<slug>.{md,zip}` where `<slug>` is a short kebab-case rendering of the summary; see the skill's "Output assembly" section for the slug rules.

```markdown
# Ditto problem report — {{one-line summary}}

**Date:** {{ISO-8601 date and time, e.g. 2026-05-18 14:30 -0400}}
**Reporter:** {{name}} ({{email or handle}})
**Reporter type:** {{internal Ditto staff | external customer}}
**Customer:** {{customer / organisation name; "Ditto (internal)" if no customer is impacted; "self" / "personal project" for solo external devs}}
**Ditto Database ID (App ID):** {{one or more database IDs, comma-separated; mark online-playground databases as "<id> (online playground)"; "unknown" if not recoverable}}
**Filed as Linear:** _(not yet filed)_

## Summary

{{one-sentence summary of the problem}}

**Likely duplicate of:** {{URL of the matching report — keep this line directly under the summary so it's the first thing a triager sees; omit this line entirely if no likely duplicate was found}}

**Problem scope:** {{small peer | Big Peer / portal | both}}

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

### HTTP API failure details

(Include this sub-section only when the issue involves a Big Peer HTTP API call. Omit otherwise. One block per failing request.)

- **Request URL:** {{e.g. https://<region>.cloud.ditto.live/api/v4/store/execute}}
- **HTTP method:** {{GET | POST | PUT | DELETE | PATCH}}
- **Response status:** {{e.g. 503, 401, 504, "no response / timeout"}}
- **`x-request-id` header:** {{value if present in the response, or "unknown"}}
- **Response body (short snippet):**

```text
{{first ~30 lines of the response body, or full body if shorter — full capture goes in Attachments}}
```

- **Approximate UTC time of the failed request:** {{e.g. 2026-05-18T18:30:12Z; this enables Big Peer log lookup}}

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

(This section is **best-effort**. Omit the entire section if the user didn't provide any code and triage doesn't clearly require it. Otherwise:)

**Fidelity provided:** {{full source | reproducer repo | snippets only | none}}

(If full source or a reproducer repo was provided, record the location below and omit all snippet sub-sections.)

- **Bundled source:** {{path inside the zip, e.g. `app/`, or omit this line if n/a}}
- **Reproducer repo:** {{URL, branch, commit SHA, or omit this line if n/a}}

(If only snippets were provided, render **only** the sub-sections for snippets the user actually pasted. Do not render empty sub-sections with `{{placeholder}}` content — better to omit the sub-section entirely. Example fenced blocks below show the expected format.)

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

## Additional information

{{free-form catch-all for anything that doesn't fit the structured fields above — DQL query text, screenshots referenced inline, network conditions, business context, related deploys, customer comms history, etc. Omit this entire section if the user has nothing to add.}}

## Reporter follow-up

(Action items for the **reporter** to close gaps in this report — not for the recipient. Omit this entire section if the report has zero gaps. Otherwise list the most-valuable steps the reporter can take to fill `unknown` fields or missing attachments. Tailor each suggestion to what's already known — give concrete commands or paths, not generic advice.)

1. {{suggestion 1 — e.g. "Capture Ditto SDK debug logs on the affected Android device: `DittoLogger.setMinimumLogLevel(LogLevel.DEBUG)`, reproduce, then `adb -s <serial> logcat -d -v threadtime > ditto-android.log`. Re-run with `update` to attach."}}
2. {{suggestion 2}}
3. {{suggestion 3}}

(Cap at 5. Prioritise: logs > regression info > occurrence-time precision > device/OS specifics > impact-data refinement. Skip any field the reporter marked `n/a`.)

## Update log

(One row per revision. New reports start with a single "initial report" entry. Each later update appends a row.)

| Timestamp                         | Updated by                | Changes                                     |
| --------------------------------- | ------------------------- | ------------------------------------------- |
| {{report creation ISO timestamp}} | {{reporter name + email}} | initial report                              |
```
