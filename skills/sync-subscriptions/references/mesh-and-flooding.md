# Mesh Propagation and Document Flooding

How subscriptions determine which documents move through the peer-to-peer
mesh — and the multi-hop behavior behind most "missing documents" reports.
Worked scenarios: [../examples/mesh-scenarios.md](../examples/mesh-scenarios.md).

## Pairwise sessions

Underneath the mesh, sync is a set of **independent pairwise sessions**: each
pair of connected peers runs its own session with its own state. There is no
mesh-wide coordinator and no shared global view — global convergence emerges
from pairwise exchanges. (SDK 5.1 adds an opt-in multicast sync beta that
replicates per group instead of per pair; everything here describes the
default pairwise transports.)

When two peers connect (and again whenever either side's subscriptions
change), they exchange:

1. **Their subscription sets** — "here is what I want."
2. **Summaries of the held documents matching their own subscriptions** —
   compact version vectors per document. (The Ditto Server exchanges
   summaries on request rather than eagerly.)

Each side then computes what the other is missing *that the other wants*, and
sends exactly that.

## The two rules

### Rule 1 — sending is filtered by the recipient's subscriptions

When peer X decides what to send peer Y, X scans **its own store** and offers
every document that matches **Y's subscriptions** (subject to access
permissions). X's own subscriptions play no role in the decision.

Corollary: a peer happily serves documents it is not itself subscribed to —
documents it wrote locally, or documents it received earlier that no longer
match its current subscriptions. Holding is what matters, not interest.

### Rule 2 — holding is bounded by a peer's own subscriptions

A peer's store gains remote documents only when they match (or matched) that
peer's own subscriptions. A peer that subscribes to "blue cars only" will
never hold red cars it didn't write itself — and therefore can never serve
red cars to anyone else.

These two rules are asymmetric on purpose: **you send from what you have, you
receive what you asked for.**

## Transitive sync (flooding)

Sync is transitive: a change made on one peer can reach peers it never
connects to directly, hopping through intermediates. With well-aligned
subscriptions this is flood-fill at full efficiency — every peer that holds a
document can serve every peer that wants it, regardless of who authored it.

There is **no hop count or TTL**. Loops in the topology are harmless because
of the version-vector mechanics: a peer never sends a change the recipient
already has, so redelivery dies out instead of circulating.

## The A→B→C subset problem

Transitivity does **not** make intermediate peers transparent. Because of
Rule 2, each hop can narrow the data that flows:

For illustration, assume A holds 100 cars and 10 are blue. These counts describe
this example dataset, not a property of the topology or counts supplied by a user.

```
Peer A                        Peer B                        Peer C
subscribes: all cars          subscribes: blue cars only    subscribes: all cars
holds: 100 cars    ──────▶    holds: 10 blue cars  ──────▶  receives: 10 blue cars
                  A sends only                   B relays only
                  what matches                   what it holds
                  B's subscription               matching C's subscription
```

- A→B: A scans its store against **B's** query. Only the 10 blue cars match.
  B never holds the other 90.
- B→C: B scans its store against **C's** query. Everything B holds matches —
  but that is only the 10 blue cars.
- C ends up with 10 of 100 cars **even though A and C subscribe to exactly
  the same thing.** No error is raised anywhere; each hop behaved correctly.

This is the single most common cause of "sync works in my two-device test but
documents go missing in the field": the endpoints' subscriptions matched, but
an intermediate peer's narrower subscription silently filtered the flow.

### How C eventually gets the rest

C receives the remaining 90 cars as soon as *any* connected peer holds them
and is willing to send — most simply, a direct A↔C connection. No
configuration change is needed; the same rules deliver the missing documents
once a sufficiently-stocked path exists.

### Diagnostics checklist

When a peer is missing documents in a multi-hop deployment:

1. Map the actual topology — which peers were ever connected to which?
2. For every intermediate peer on the path, compare **its** subscriptions
   against the missing documents. Any peer whose subscriptions exclude those
   documents is a pinch point.
3. Remember that connectivity changes over time: a peer may hold documents
   from an earlier connection (holding is sticky) or may have joined after
   the data flowed.
4. If a role of device exists only to relay (e.g. a wall-mounted tablet
   bridging a back office and the floor), its subscription must cover the
   union of everything it is expected to carry — or it must not be on the
   only path.

### Aligning subscriptions for flood-fill

When peers in the same role run the same subscription, any of them can serve
any other — maximal path redundancy. Deliberately narrow subscriptions are
fine (they save bandwidth and storage) as long as every *intended* data path
is made of peers whose subscriptions cover the data expected to traverse
them. A Ditto Server (Big Peer) can provide a path around a narrow relay **if it
holds the missing documents and permissions allow it to serve them to the receiving
peer**. A cloud connection alone does not guarantee complete holdings, matching
subscriptions, or authorization. Apply the same recipient-filter rule to that path.

The receive-filter rule is described in [Managing Subscriptions](https://docs.ditto.live/sdk/latest/sync/syncing-data);
authorization is covered in [Authorizing Users](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization).

## Loop safety and efficiency, briefly

- Summaries (version vectors) are exchanged per session; a document version
  is only sent if the recipient's summary shows it missing. This makes
  flooding self-terminating in cyclic topologies.
- Changes are field-level deltas, so relaying is cheap even when a document
  hops several times.
- When a document changes so that it leaves the recipient's subscription
  scope, the sender delivers that final change anyway (via a per-document
  interest marker), so the recipient's copy converges to the new state rather
  than going stale — then updates for it stop. Nothing is auto-deleted; see
  [how-subscriptions-work.md](how-subscriptions-work.md#when-a-document-stops-matching).
