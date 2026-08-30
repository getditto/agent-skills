# Cookbook: chat with media

Covers SDK **4.14.x and 5.1.x**; version gates tagged inline. Chat is the canonical case where "put it all in one doc" collapses: messages are unbounded, multi-writer, and include binaries.

## The input JSON

```json
{
  "_id": "channel-7",
  "name": "field-ops",
  "members": ["u-1", "u-2", "u-3"],
  "messageCount": 0,
  "messages": [
    {
      "id": "m-9001",
      "from": "u-1",
      "text": "Gate B is open",
      "sentAt": "2026-08-25T10:31:00Z",
      "readBy": ["u-2"],
      "imageBase64": "/9j/4AAQSkZJRgAB...<~1.2 MB>"
    }
  ]
}
```

## Findings

| Severity | ID | Path | Reason |
|---|---|---|---|
| blocker | `SPLIT_UNBOUNDED` + `ARRAY_LWW` | `messages` | Unbounded, multi-writer, embedded array — the trifecta. Concurrent sends silently overwrite; the doc would hit the 5 MiB ceiling in a busy channel |
| blocker | `ATTACHMENT_CANDIDATE` | `messages[].imageBase64` | ~1.2 MB inline; doc blows the soft limit with one photo |
| blocker | `ARRAY_LWW` | `readBy` | Two readers marking read concurrently lose one receipt |
| blocker | `COUNTER_CANDIDATE` | `messageCount` | Incremented by many writers as a plain number — lost increments on merge; must be `COUNTER` (4.14+) or dropped |
| warn | `ARRAY_LWW` | `members` | Membership changes from multiple admins + LWW array = lost invites. OK only if membership changes are rare and human-resolved — still recommend keyed MAP |
| info | `DECLARE_TYPES` | nested objects | 5.1.x-only fleet: lenient defaults already infer MAP — no declaration needed. Would only matter if 4.14.x strict peers joined later (then: flip them to `false`, or declare during the transition) |
| warn | `OBSERVER_SCOPE` | implied "latest messages" screen | Must observe a bounded window (`WHERE sentAt >= … ORDER BY sentAt DESC LIMIT 50`), never the whole collection |

## Recommended model

One document per message; channel doc holds only metadata. Binary to ATTACHMENT.

```sql
-- channel: small, warm
INSERT INTO COLLECTION channels (members MAP)
DOCUMENTS ({
  '_id': 'channel-7',
  'name': 'field-ops',
  'members': { 'u-1': { 'role': 'admin' }, 'u-2': { 'role': 'member' }, 'u-3': { 'role': 'member' } }
});

-- message: immutable body, append-friendly receipts
INSERT INTO COLLECTION messages (
  readers MAP,
  image   ATTACHMENT
)
DOCUMENTS ({
  '_id': 'm-9001',
  'channel_id': 'channel-7',
  'from': 'u-1',
  'text': 'Gate B is open',
  'sentAt': '2026-08-25T10:31:00.000Z',
  'readers': { 'u-2': '2026-08-25T10:40:11.112Z' },
  'image': { 'id': '<attachment-token>', 'len': 1258291, 'metadata': { 'mime': 'image/jpeg' } }
});

CREATE INDEX IF NOT EXISTS idx_messages_channel_sent
  ON messages (channel_id, sentAt);   -- composite index: 5.1+ only
```

On **4.14.x** use a single-column index on `(channel_id)` and sort in memory, or page with `channel_id` + `sentAt` range predicates instead — composite indexes are 5.1+.

Unread badges: keep a per-user, per-channel counter — `INSERT INTO COLLECTION channel_state (unread COUNTER) VALUES ({...})` — rather than counting at runtime over a hot collection. `messageCount` on the channel itself: prefer dropping it; if you keep it, `COUNTER` only.

## Reads

```sql
-- channel view: latest 50 messages (any version)
SELECT * FROM messages
WHERE channel_id = 'channel-7'
ORDER BY sentAt DESC
LIMIT 50;
```

Joins aren't needed: messages are consumed without channel fields, and the member list is small and lives in the channel doc.

## Budget

Channel doc ≈ 1 KiB. Message doc without image ≈ 300 B — fine even over BLE. Images arrive via the attachment protocol on demand (`fetchAttachment` when the bubble scrolls into view), never inline, so a photo-heavy channel doesn't strangle BLE peers.
