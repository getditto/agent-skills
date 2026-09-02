# Cookbook: chat with media

Covers SDK **4.14.x and 5.1.x**; version gates tagged inline. All statements assume `dql_strict_mode = false` on every peer (the 5.x default; the migration target for 4.14.x meshes). Chat is the canonical case where "put it all in one doc" collapses: messages are unbounded, multi-writer, and include binaries.

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
| info | `DECLARE_TYPES` | nested objects | 5.1.x-only fleet: lenient defaults infer MAP — no declarations on writes or reads. Would matter only if un-migrated 4.14.x strict peers joined later (then: migrate them to `dql_strict_mode = false`; declare MAP explicitly only on statements those peers execute during the transition) |
| warn | `OBSERVER_SCOPE` | implied "latest messages" screen | Must observe a bounded window (`WHERE sentAt >= … ORDER BY sentAt DESC LIMIT 50`), never the whole collection |

## Recommended model

One document per message; channel doc holds only metadata. Binary to ATTACHMENT.

```sql
-- channel: small, warm; members infers MAP — no declaration
INSERT INTO channels
DOCUMENTS ({
  '_id': 'channel-7',
  'name': 'field-ops',
  'members': { 'u-1': { 'role': 'admin' }, 'u-2': { 'role': 'member' }, 'u-3': { 'role': 'member' } }
});

-- message: immutable body, append-friendly receipts
-- readers infers MAP; ATTACHMENT is declared (inference can't guess it)
INSERT INTO COLLECTION messages (image ATTACHMENT)
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

### Unread badges and message counts

The intuitive model is to count from the observer you already have on the channel — `SELECT COUNT(*) FROM messages WHERE channel_id = 'channel-7' AND sentAt > :lastRead`, or count unread rows in the result set the message list is already receiving. That is genuinely the right answer for the channel you are *looking at*, and you should do it there: the messages are local, the query is bounded, and no extra state can drift.

It stops working for the **channel list** — the screen showing 40 channels each with a badge. Counting there means one observer per channel over the messages collection, each re-running its query and re-delivering its full result set on every fire ([`../references/performance.md`](../references/performance.md)). Forty observers over the hottest collection in the app, to render forty integers, is the standard way this design gets slow. There is also no aggregate observer to lean on: a `GROUP BY channel_id` count is a query you can `execute`, but subscriptions and observers over an aggregate don't give you a per-channel live badge for free.

So the counter is a **materialized badge**: one small document per (user, channel), holding the number the badge renders, so the channel list observes one narrow collection instead of the message stream.

```sql
-- One doc per user+channel. _id carries the user: sync permissions can only
-- see _id, and a user's read state should sync to that user's devices only.
INSERT INTO COLLECTION channel_state (unread COUNTER)
VALUES ({
  '_id':       { 'user_id': 'u-2', 'channel_id': 'channel-7' },
  'unread':    0,
  'last_read': '2026-08-25T10:40:11.112Z'
})
ON ID CONFLICT DO NOTHING;          -- seeding is an assignment; never replay it live

-- Sender's device, in the same transaction as the message INSERT:
-- one increment per recipient.
UPDATE COLLECTION channel_state (unread COUNTER)
APPLY unread INCREMENT BY 1
WHERE _id.channel_id = 'channel-7' AND _id.user_id != 'u-1';

-- Reader opens the channel: zero the badge and record the watermark.
UPDATE COLLECTION channel_state (unread COUNTER)
APPLY unread RESTART WITH 0             -- APPLY must precede SET; the parser
SET   last_read = '2026-08-25T10:41:00.000Z'   -- rejects the other order
WHERE _id = { 'user_id': 'u-2', 'channel_id': 'channel-7' };

-- The channel list: one observer, one narrow collection, no message rows.
-- _id subfields are ordinary queryable paths — no body copies needed.
SELECT * FROM channel_state WHERE _id.user_id = 'u-2' AND unread > 0;
CREATE INDEX IF NOT EXISTS idx_channel_state_user ON channel_state (_id.user_id);
```

Why each piece is what it is:

- **`COUNTER`, not a number.** Two senders posting to the same channel while partitioned each increment; both survive the merge. A `SET unread = unread + 1` on a REGISTER loses one, silently.
- **`RESTART WITH 0`, not `INCREMENT BY -n`.** Marking-as-read is "the count is now zero", not "subtract what I think I read" — a decrement racing a concurrent increment leaves the badge negative. `RESTART` is COUNTER-only and needs 4.14+.
- **`last_read` is the reconciliation key.** The counter can drift — a sender goes offline mid-write, or a message arrives from a peer that never incremented anyone. When the user opens the channel you are counting locally anyway, so `RESTART WITH` the exact count from `WHERE sentAt > last_read` and the drift is gone. Treat the counter as a cached hint that self-heals on open, not as a ledger.
- **Increment on the sender.** Recipients may be offline, and an offline device can't count messages it hasn't received. The sender knows the member list from the channel doc and writes one increment per other member.

**Trade-off, stated plainly:** this is denormalized state that can be wrong between reconciliations, and it costs one extra document per user per channel. Accept that for the channel list; don't build it for a single channel view that can just count what it already has.

**`messageCount` on the channel doc:** drop it. Every message in a busy channel would write the channel document, turning the small warm doc every peer subscribes to into the hottest write target in the mesh — and no screen needs a lifetime total. If a product requirement genuinely needs one, it is a `COUNTER` on the channel (never a plain number), and it should be a separate document from the channel metadata so message traffic doesn't churn the doc everyone reads.

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
