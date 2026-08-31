# Cookbook: migrating a MongoDB/SQL-style model

Covers SDK **4.14.x and 5.1.x** — the join question is where these versions diverge most. All statements assume `dql_strict_mode = false` on every peer (the 5.x default; the migration target for 4.14.x meshes). Scenario: a team-portal coming from MongoDB with normalized collections asks "how do I lay this out in Ditto?"

## The input shape (three related documents)

```json
// users
{ "_id": "u-1", "name": "Ravi", "email": "ravi@example.com", "teamId": "t-9" }

// teams
{ "_id": "t-9", "name": "Field Ops", "memberIds": ["u-1", "u-2"], "settings": { "quietHours": true, "region": "us-1" } }

// tickets – the hot collection
{
  "_id": "k-100",
  "teamId": "t-9",
  "assigneeId": "u-1",
  "title": "Replace gate sensor",
  "state": "open",
  "points": 3,
  "commentsCount": 0,
  "comments": [
    { "by": "u-2", "at": "2026-08-25T09:00:00Z", "body": "Parts ordered" }
  ],
  "history": [
    { "at": "2026-08-25T09:00:00Z", "state": "open" }
  ],
  "labels": ["hardware", "urgent"]
}
```

## Findings

| Severity | ID | Path | Reason |
|---|---|---|---|
| blocker | `SPLIT_UNBOUNDED` + `ARRAY_LWW` | `tickets.comments` | Unbounded, multi-writer array — own collection, one doc per comment |
| blocker | `SPLIT_UNBOUNDED` + `ARRAY_LWW` | `tickets.history` | Same; state transitions from several devices get silently overwritten |
| blocker | `COUNTER_CANDIDATE` | `tickets.commentsCount` | Plain number bumped by many peers → `COUNTER` (4.14+) — though after splitting comments into docs, prefer counting at read time and drop this field |
| warn | `ARRAY_LWW` | `teams.memberIds` | Membership edited by multiple admins → keyed MAP |
| warn | `DECLARE_TYPES` | `teams.settings` | No declaration once peers are lenient (infers MAP). Flagged because any un-migrated 4.14.x strict peer would store it as a whole-object REGISTER and silently omit it from plain reads — migrate those peers to `dql_strict_mode = false`; declare MAP explicitly only on their statements during the transition |
| warn | `JOIN_VS_DENORMALIZE` | `teamId`, `assigneeId` lookups | 5.1+: JOIN on indexed keys; 4.14.x: denormalize display fields (`assigneeName`, `teamName`) into tickets |
| warn | `OBSERVER_SCOPE` | kanban screen | Observe `WHERE teamId = 't-9' AND state = 'open'` — not all tickets |
| info | `ATOMIC_OBJECT_REGISTER` vs MAP | `teams.settings` | fields flip independently (quietHours vs region) → MAP is right; keep per-field LWW |
| info | `ARRAY_LWW` (ok) | `tickets.labels` | Acceptable **only if** label edits are rare/single-writer; otherwise `labels MAP` keyed by label name |

## Recommended model

```sql
-- comments: one document each
INSERT INTO comments
DOCUMENTS ({
  '_id': 'c-7001',
  'ticket_id': 'k-100',
  'by': 'u-2',
  'at': '2026-08-25T09:00:00.000Z',
  'body': 'Parts ordered'
});

-- state history: timestamp-keyed MAP on the ticket (bounded for most tickets)
-- labels/state_log infer MAP under the lenient default — no declarations
INSERT INTO tickets
DOCUMENTS ({
  '_id': 'k-100',
  'team_id': 't-9',
  'assignee_id': 'u-1',
  'title': 'Replace gate sensor',
  'state': 'open',
  'points': 3,
  'labels': { 'hardware': true, 'urgent': true },
  'state_log': { '2026-08-25T09:00:00.000Z': 'open' }
});

-- teams (members/settings infer MAP — no declarations)
INSERT INTO teams
DOCUMENTS ({
  '_id': 't-9',
  'name': 'Field Ops',
  'members': { 'u-1': { 'role': 'lead' }, 'u-2': { 'role': 'member' } },
  'settings': { 'quietHours': true, 'region': 'us-1' }
});
```

If a ticket's history is long-lived and high-volume, `state_log` splits out into its own docs on the `ticket_events` pattern instead — same reasoning as comments.

## The join question

**On 5.1+** normalize freely and reassemble — but index the right side (joins require the right-side match key to be `_id` or indexed, else ADVISE tells you to add one). Joins run in `execute` and observers on Small Peers only — not in Big Peer environments and not in `registerSubscription`, so a join-backed screen must subscribe to something else:

```sql
CREATE INDEX IF NOT EXISTS idx_comments_ticket ON comments (ticket_id);

SELECT t.title, c.body, c.at
FROM tickets AS t
LEFT JOIN comments AS c ON c.ticket_id = t._id
WHERE t._id = 'k-100';
```

**On 4.14.x** there are no joins. Two patterns:

1. **Two fetches in app code** — fine for detail screens: `SELECT * FROM tickets WHERE _id = …`, then `SELECT * FROM comments WHERE ticket_id = …`.
2. **Denormalize read-time fields** into the hot document — ticket cards carry `assignee_name` and `team_name` duplicated from the source docs. Keep duplicated writes cheap and idempotent with `INSERT … ON ID CONFLICT DO UPDATE_LOCAL_DIFF` (4.12+), and treat the source collection as the system of record.

Also decide **before** launch whether 4.14.x peers will ever join the mesh: a screen built on JOINs has no fallback on LTS devices. Mixed-mesh rule: build reads to the 4.14 surface (two-fetch or denormalized) even if writers are 5.1.

## Index plan (both versions)

```sql
CREATE INDEX IF NOT EXISTS idx_tickets_team_state ON tickets (team_id, state);  -- composite: 5.1+
CREATE INDEX IF NOT EXISTS idx_tickets_team      ON tickets (team_id);            -- 4.14 fallback
CREATE INDEX IF NOT EXISTS idx_comments_ticket   ON comments (ticket_id);
```

## Budget

Ticket doc ≈ 400–800 B with comments/history externalized — fine over BLE. Comment docs ≈ 200 B each. The kanban observer watches `team_id + state` (indexed, bounded in practice) instead of the full tickets collection.
