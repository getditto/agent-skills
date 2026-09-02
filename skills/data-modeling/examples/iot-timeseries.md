# Cookbook: IoT device telemetry

Covers SDK **4.14.x and 5.1.x**. All statements assume `dql_strict_mode = false` on every peer (the 5.x default; the migration target for 4.14.x meshes). Time-series telemetry is the fastest way to hit the hard size limit: readings arrive every few seconds, forever.

## The input JSON

```json
{
  "_id": "sensor-4471",
  "site": "warehouse-3",
  "firmware": "2.7.1",
  "battery": 87,
  "connectionCount": 1340,
  "readings": [
    { "t": "2026-08-25T10:30:00Z", "temp_c": 21.4, "humidity": 44 },
    { "t": "2026-08-25T10:30:10Z", "temp_c": 21.5, "humidity": 44 }
  ],
  "lastSeen": "2026-08-25T10:30:10Z"
}
```

## Findings

| Severity | ID | Path | Reason |
|---|---|---|---|
| blocker | `SPLIT_UNBOUNDED` + `ARRAY_LWW` | `readings` | Unbounded append-only stream inside the device doc; the sensor writes the whole array every 10 s — LWW alternation with any cloud-side writer, and the doc hits 5 MiB in weeks at this cadence |
| blocker | `SIZE_HARD` trajectory | whole doc | 8640 readings/day at ~80 B each ≈ 700 KB/day embedded — soft limit crossed on day 1 |
| blocker | `COUNTER_CANDIDATE` | `connectionCount` | Incremented by the device *and* possibly a gateway — must be `COUNTER` (4.14+) to survive concurrent increments |
| info | registers are fine | `firmware`, `site`, `battery`, `lastSeen` | Single-writer overwrites — plain REGISTER, no ceremony |
| warn | `COMPOSITE_ID` | `_id` (readings) | Readings are naturally keyed by device + timestamp and scoped by site. Use a composite object `_id`, not a delimiter-joined string — permissions can only see `_id`, and object subfields stay queryable and indexable |
| info | `SOFT_DELETE`/`EVICT` | readings retention | Decide retention up front: Big-Peer-kept history + small-peer `EVICT` of old readings keeps edge storage flat |

## Recommended model

The device doc holds only the *latest* state, written solely by the device itself — so the lenient defaults are exactly right with zero declarations: scalars store as REGISTERs, the `lastReading` object infers as a MAP (a single writer rewriting the same keys wholesale makes MAP and REGISTER indistinguishable here). Each reading is its own document — tiny, immutable, eviction-friendly.

```sql
-- device: warm, ~200 B
INSERT INTO devices
DOCUMENTS ({
  '_id': 'sensor-4471',
  'site': 'warehouse-3',
  'firmware': '2.7.1',
  'battery': 87,
  'lastSeen': '2026-08-25T10:30:10.000Z',
  'lastReading': { 't': '2026-08-25T10:30:10.000Z', 'temp_c': 21.5, 'humidity': 44 }
});

-- reading: one doc per sample. Composite object _id — device + timestamp is
-- the natural key, and 'site' rides along so per-site sync permissions can be
-- expressed (rules see _id and nothing else).
INSERT INTO readings
DOCUMENTS ({
  '_id': { 'site': 'warehouse-3', 'device_id': 'sensor-4471', 't': '2026-08-25T10:30:10.000Z' },
  'device_id': 'sensor-4471',
  'site': 'warehouse-3',
  't': '2026-08-25T10:30:10.000Z',
  'temp_c': 21.5,
  'humidity': 44
})
ON ID CONFLICT DO NOTHING;                       -- re-transmitted readings no-op

CREATE INDEX IF NOT EXISTS idx_readings_device_t ON readings (device_id, t);  -- composite: 5.1+

INSERT INTO COLLECTION devices (connection_count COUNTER)
VALUES ({ '_id': 'sensor-4471', 'connection_count': 1340 })
ON ID CONFLICT DO UPDATE;                     -- 4.14+; replaying the seed is an LWW set (resets to 1340 — don't replay while live increments matter)
```

### Why `devices` is its own collection instead of "latest reading from `readings`"

Reasonable objection: `lastReading` is duplicated data, and the newest reading is one `ORDER BY t DESC LIMIT 1` away. For a single device on a screen you're already looking at, that query is fine — use it. The device document earns its place for four reasons that all show up at fleet scale:

1. **"Latest per device" is not a query you can subscribe to.** The fleet dashboard wants one live row per device, which is a per-group top-1 — and subscriptions reject `ORDER BY` on 5.0+, so you cannot express even the single-device version as a live subscription. The alternatives are N observers (one `LIMIT 1` query per device, over the hottest collection in the system) or one wide observer over `readings` that re-delivers its full result set on every sample from every device. `SELECT * FROM devices` is one narrow observer over one small collection that fires when a device's state actually changes.
2. **The device doc holds things that are not readings.** `firmware`, `site`, `battery`, assignment, calibration, thresholds, enabled/disabled. Those are device state with a different write pattern (rare, human- or fleet-management-driven) and a different read pattern (always) than the telemetry stream. They need somewhere to live regardless, and once the document exists, `lastReading` is a few extra bytes on a document you are already syncing.
3. **Retention deletes the readings; it must not delete the device.** The whole retention story below is "evict old readings from the edge, keep history on the Big Peer". If the latest reading is only in `readings`, then a peer that has evicted its history — or a fresh device that has synced device state but not the backlog — has no current temperature to show. `devices` survives eviction because nothing evicts it.
4. **Subscription scope.** A tablet showing the warehouse overview can subscribe to `devices` alone and never sync a single reading document. Deriving the latest from `readings` forces it to subscribe to the stream it is trying to avoid — which over BLE is the difference between a few hundred bytes per device and everything.

The rule generalizes: **when a collection is written far more often than it is read, keep the read-mostly summary somewhere else.** `readings` is write-mostly and append-only; `devices` is read-mostly and small. Cross-collection duplication is the cheap side of that trade, and the device itself is the single writer of both, so the duplicate can't diverge through concurrent edits.

Notes on the rest of the model:

- The composite `_id` makes re-transmitted readings idempotent (`ON ID CONFLICT DO NOTHING` or `DO UPDATE_LOCAL_DIFF`, 4.12+) — the same sample re-sent lands on the same ID. Use an object, not a delimiter-joined string like `'sensor-4471:2026-08-25T…'`: the components stay queryable (`WHERE _id.site = 'warehouse-3'`) and indexable, and the site scope stays visible to permissions. See [`../references/workflow.md`](../references/workflow.md) §2 `COMPOSITE_ID`.
- On **4.14.x/5.0.x** the composite index above is not available — index `(device_id)` alone and range-filter on `t`, or index `(t)` if queries are mostly time-windowed across devices.
- Rollups (hourly avg per device) are documents of their own (`rollups` collection, `_id` `{device_id, hour}`), computed by whichever node has the mandate — never accumulated into the device doc.

## Retention

- Prefer **Big-Peer-managed retention**: readings sync to the Big Peer first, then edge devices evict. Small-Peer-local eviction risks evict/resync loops when subscriptions still match — cancel affected subscriptions first, or flag docs for eviction instead.
- Eviction on a mass scale triggers resync churn with connected peers — schedule eviction passes (e.g. nightly, off-peak) rather than evicting per-reading during the day.
- Be deliberate with hard deletes: tombstones live 7 days on Small Peers by default (`TOMBSTONE_TTL_HOURS = 168`, tunable), 30 days on Big Peer. A sensor that re-appears after a month can resurrect old readings — that's usually *desirable* for telemetry, but know it.

## Budget

Reading doc ≈ 120 B; at 10 s cadence a device emits ~1 MB/day of tiny docs — syncs fine even over BLE in steady state (they trickle as deltas, not as one big document). The device doc stays ~200 B forever. Edge storage stays flat with `EVICT`; historical depth lives on the Big Peer.
