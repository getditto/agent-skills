# Cookbook: IoT device telemetry

Covers SDK **4.14.x and 5.1.x**. Time-series telemetry is the fastest way to hit the hard size limit: readings arrive every few seconds, forever.

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
| info | `SOFT_DELETE`/`EVICT` | readings retention | Decide retention up front: Big-Peer-kept history + small-peer `EVICT` of old readings keeps edge storage flat |

## Recommended model

The device doc holds only the *latest* state (single-writer by the device itself, so plain registers). Each reading is its own document — tiny, immutable, eviction-friendly.

```sql
-- device: warm, ~200 B
INSERT INTO COLLECTION devices (lastReading REGISTER)
DOCUMENTS ({
  '_id': 'sensor-4471',
  'site': 'warehouse-3',
  'firmware': '2.7.1',
  'battery': 87,
  'lastSeen': '2026-08-25T10:30:10.000Z',
  'lastReading': { 't': '2026-08-25T10:30:10.000Z', 'temp_c': 21.5, 'humidity': 44 }
});

-- reading: one doc per sample
INSERT INTO readings
DOCUMENTS ({
  '_id': 'sensor-4471:2026-08-25T10:30:10.000Z',  -- device id + timestamp: idempotent re-sends
  'device_id': 'sensor-4471',
  't': '2026-08-25T10:30:10.000Z',
  'temp_c': 21.5,
  'humidity': 44
})
ON ID CONFLICT DO NOTHING;                       -- re-transmitted readings no-op

INSERT INTO COLLECTION devices (connection_count COUNTER)
VALUES ({ '_id': 'sensor-4471', 'connection_count': 1340 })
ON ID CONFLICT DO UPDATE;                     -- 4.14+; idempotent re-seed
```

Notes on the model:

- The composite string `_id` makes re-transmitted readings idempotent (`ON ID CONFLICT DO NOTHING` or `DO UPDATE_LOCAL_DIFF`, 4.12+).
- Duplicate `lastReading` inside the device doc deliberately: dashboards read one doc per device instead of querying the readings stream. That redundancy is the *right* trade — the readings collection is write-mostly, the device doc is read-mostly.
- Rollups (hourly avg per device) are documents of their own (`rollups` collection keyed `device_id:hour`), computed by whichever node has the mandate — never accumulated into the device doc.

## Retention

- Prefer **Big-Peer-managed retention**: readings sync to the Big Peer first, then edge devices evict. Small-Peer-local eviction risks evict/resync loops when subscriptions still match — cancel affected subscriptions first, or flag docs for eviction instead.
- Eviction on a mass scale triggers resync churn with connected peers — schedule eviction passes (e.g. nightly, off-peak) rather than evicting per-reading during the day.
- Be deliberate with hard deletes: tombstones live 7 days on Small Peers (30 on Big Peer). A sensor that re-appears after a month can resurrect old readings — that's usually *desirable* for telemetry, but know it.

## Budget

Reading doc ≈ 120 B; at 10 s cadence a device emits ~1 MB/day of tiny docs — syncs fine even over BLE in steady state (they trickle as deltas, not as one big document). The device doc stays ~200 B forever. Edge storage stays flat with `EVICT`; historical depth lives on the Big Peer.
