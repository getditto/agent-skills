# How Sync Subscriptions Work

The end-to-end lifecycle of a subscription, from registration to steady-state
sync. Language-agnostic; for call syntax see the Ditto SDK docs
([Managing Subscriptions](https://docs.ditto.live/sdk/latest/sync/syncing-data)).

## Lifecycle

1. **Start sync.** Subscriptions only replicate while sync is running. Start
   it once, high in the app's lifecycle, and keep it running. Stopping sync
   disconnects all peers and pauses all subscriptions (they resume when sync
   restarts).
2. **Register a subscription.** The app hands Ditto a DQL `SELECT` query
   (optionally with `:argument` placeholders). Ditto validates it immediately
   — invalid queries are rejected at registration, not later. See
   [query-limitations.md](query-limitations.md).
3. **The query is shared with connected peers.** Every connected peer learns
   this peer's subscription set, and learns about changes as they happen.
4. **Initial sync.** Each connected peer scans its own store for documents
   matching the new subscription and sends them.
5. **Incremental sync.** From then on, every matching change — local writes on
   the remote, or changes the remote itself received from elsewhere — flows to
   the subscriber automatically. No polling.
6. **Cancel.** Cancelling a subscription stops future updates. It does not
   delete data already received.

## Subscriptions are receive-side filters

A subscription answers exactly one question: "which documents should other
peers send me?" It has no effect on:

- **Local writes.** A peer can always write any document locally, whether or
  not it matches a subscription.
- **Local reads.** Local queries and observers see the entire local store,
  regardless of subscriptions.
- **What the peer sends.** Sending is filtered by the *recipient's*
  subscriptions, not the sender's (see
  [mesh-and-flooding.md](mesh-and-flooding.md)).

A subscription is also not a view: it does not transform, trim, or aggregate
documents. Matching documents arrive whole.

## Delta sync

Steady-state sync sends **changes, not documents**. Ditto tracks causal
history with per-document version vectors (summaries of which peer changed
what, and when). Before sending, a peer compares its version of a document
against what the recipient is known to have, and transmits only the changed
CRDT state. Delta granularity follows the document's CRDT structure: entries
in a `MAP`, including nested `MAP` entries, can sync independently, while a
`REGISTER` is atomic and its whole value ships when it changes. Under 4.14.x's
default strict mode, a nested object without an explicit `MAP` declaration is
a single register, so editing one nested property syncs the whole object.

Consequences:

- Sync is cheap on constrained transports (BLE especially) and on battery.
- Reconnecting peers converge by exchanging summaries first, then only the
  missing deltas — there is no full re-sync after a disconnect.
- Version vectors also suppress redundant deliveries: a peer never sends a
  change the recipient already has, which is what lets updates flood a mesh
  with loops in it without circulating forever.

Conflicts between concurrent edits are resolved deterministically by CRDT
merge rules (last-write-wins registers, add-wins maps) — no app code is
involved. See the `write-dql` skill for CRDT data types and
[Conflict Resolution](https://docs.ditto.live/key-concepts/syncing-data#conflict-resolution).

## In-memory, deduplicated, refcounted

- **Not persisted.** Subscriptions live in memory on the running Ditto
  instance. After an app restart, nothing is subscribed until the app
  registers its subscriptions again — make registration part of startup,
  right after starting sync.
- **Deduplicated.** Registering the exact same query twice shares one
  underlying subscription; the sync engine does not do the work twice.
- **Cancelled explicitly.** A subscription stays active until cancelled (or
  until the Ditto instance is destroyed). Dynamically created subscriptions
  that are never cancelled accumulate and degrade sync performance.
- **C++/Rust warning:** in these SDKs the subscription object is owned by the
  caller and dropping it does **not** cancel the subscription — it keeps
  replicating invisibly. Always cancel explicitly.

## When a document stops matching

If a held document is updated so that it no longer matches a peer's
subscription (e.g. a subscribed-to `color = 'blue'` car is repainted red):

1. The update itself is still delivered — Ditto keeps a lightweight
   per-document interest marker precisely so out-of-scope changes reach
   peers that already hold the document. The peer's local copy is updated to
   the new (non-matching) version.
2. Interest is then withdrawn, and future changes to that document stop
   flowing.
3. **The document is not deleted.** Subscriptions never evict. Removal is
   always explicit: `EVICT` (local only — other peers will re-sync it if it
   still matches) or `TOMBSTONE` (mesh-wide delete).

## Attachments

Subscriptions sync documents, not attachment payloads. A document containing
an attachment arrives with an *attachment token*; the binary is fetched
explicitly, on demand, and can come from any peer that has it. Design bulk
data as attachments (or a separately-subscribed collection) rather than
embedding it in subscribed documents.

## Observing vs subscribing

Two APIs are easy to confuse:

- **Subscription** — controls what the mesh sends to this device. No callback
  fires locally; there is nothing to "handle".
- **Observer / local query** — controls what the app sees from the local
  store, with change callbacks.

Typical pattern: a broad, stable subscription brings the data in; observers
with narrower, changing queries present slices of it to the user.
