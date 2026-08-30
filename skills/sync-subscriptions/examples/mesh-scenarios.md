# Mesh Scenarios, Worked

Each scenario uses the same data: a `cars` collection with 100 documents, 10
of which have `color = 'blue'`. Rules referenced below are defined in
[../references/mesh-and-flooding.md](../references/mesh-and-flooding.md).

## Scenario 1 — two peers, matching subscriptions

```
Peer A                          Peer B
subscribes: SELECT * FROM cars  subscribes: SELECT * FROM cars
holds: 100 cars      ◀──────▶   holds: 0 cars (fresh install)
```

- B connects to A and announces its subscription.
- A scans its store against B's query: all 100 cars match. A sends them.
- B now holds all 100. Subsequent edits on either side flow as field-level
  deltas, both directions.

The simple case everything else builds on.

## Scenario 2 — three peers, narrow middle (the classic trap)

```
Peer A                          Peer B                           Peer C
subscribes: all cars            subscribes: blue cars only       subscribes: all cars
holds: 100 cars      ──────▶    holds: ???            ──────▶    holds: 0 cars
```

1. A→B: B's subscription matches only the 10 blue cars. A sends those.
   **B holds 10 cars.**
2. B→C: C's subscription matches everything B holds. B sends all of it.
   **C holds 10 cars.**
3. C is missing 90 cars and will stay missing: the only path to A runs
   through B, and B cannot forward what it never received (Rule 2).

No component malfunctioned. Each hop applied the rules correctly; the
topology plus B's narrow subscription produced a partial replica at C.

**Fix options:** widen B's subscription to cover what it is expected to
carry; connect C to a fully-stocked peer; or ensure the Ditto Server (which
typically holds everything) is reachable from C.

## Scenario 3 — late direct connection heals C

Continuing Scenario 2, C later connects directly to A:

```
Peer A (100 cars)  ◀──────▶  Peer C (10 cars)
```

- A and C exchange summaries. A sees C is missing 90 matching documents and
  sends only those — no re-send of the 10 C already has (version-vector
  descent makes the delta exact).
- C now holds all 100.

Takeaway: mesh sync is self-healing as soon as a sufficiently-stocked path
exists. "Missing documents" is a statement about *current paths and their
subscriptions*, not permanent loss.

## Scenario 4 — the relay serves data it isn't subscribed to

```
Peer B                          Peer C
subscribes: blue cars only      subscribes: all cars
holds: 10 blue cars
```

B **locally creates** a red car (local writes don't consult subscriptions —
B's store accepts it):

- B→C: B scans its store against **C's** subscription. The red car matches
  "all cars". B sends it, even though the red car does not match B's own
  subscription.
- C receives the red car. **B holds 11 cars, C holds 11 cars** (10 blue + 1
  red).

Rule 1 in action: sending is filtered by the recipient's subscriptions, never
the sender's. A peer is not a passive replica of its own subscription set.

## Scenario 5 — a document leaves the subscription scope

B subscribes to blue cars and holds car `abc` (blue). Someone — anywhere the
document can reach — repaints `abc` red:

1. The red update **is delivered to B**, even though red no longer matches
   B's subscription. Ditto keeps per-document interest for exactly this case,
   so held documents never go stale.
2. B's copy of `abc` becomes red. B's subscription is unaffected — the
   document is simply no longer in scope for *future* updates.
3. Nothing is deleted. If B should forget `abc`, the app must `EVICT` it
   (local; re-syncs if it ever matches again) or `TOMBSTONE` it (mesh-wide
   delete).

## Scenario 6 — same role, same subscription (flood-fill at full efficiency)

Five kiosks all subscribe to `SELECT * FROM menu WHERE location = :store`:

- Any kiosk that receives a menu update — from the cloud, from a manager's
  device, from another kiosk — can serve it to every other kiosk.
- Every connection is a complete path for this data; there is no pinch point.
  Devices can join, leave, and pair arbitrarily and the set still converges.

This is the design target from
[best-practices.md](../best-practices.md): within a role, align subscription
shapes so flood-fill works for you instead of against you.
