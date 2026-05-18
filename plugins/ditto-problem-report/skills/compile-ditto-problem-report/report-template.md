# Report template

Render the report using exactly the following structure. Replace every `{{placeholder}}`. For fields the user marked unknown, write the literal word `unknown` (not the placeholder). Omit entire optional sections only if the user explicitly indicates they do not apply (e.g. omit the **Big Peer** section if the problem scope is pure small-peer; omit the **Environment** and **Transports** sections if the problem scope is pure Big Peer / portal).

```markdown
# Ditto problem report — {{one-line summary}}

**Date:** {{ISO-8601 date and time, e.g. 2026-05-18 14:30 -0400}}
**Reporter:** {{name}} ({{email or handle}})
**Reporter type:** {{internal Ditto staff | external customer}}

## Summary

{{one-sentence summary of the problem}}

**Problem scope:** {{small peer | Big Peer / portal | both}}

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
- **App ID:** {{app id, or "redacted"}}
- **Region / cluster:** {{region, or "unknown"}}
- **Portal URL** (for portal-UI issues): {{e.g. https://portal.ditto.live/apps/.../sync}}
- **Browser + version** (for portal-UI issues): {{e.g. Chrome 124.0.6367.61}}

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
```
