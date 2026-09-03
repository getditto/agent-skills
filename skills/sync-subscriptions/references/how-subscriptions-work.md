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

- **The subscription is in memory — the documents it syncs usually are not.**
  Only the subscription *registration* lives in memory on the running Ditto
  instance. On the disk-backed SDKs everything it pulls in is written to the
  local store and persists on disk (in the persistence directory) across
  restarts. So after an app restart the previously synced documents are still
  queryable, but nothing is subscribed until the app registers its
  subscriptions again — make registration part of startup, right after
  starting sync.
  - **Browser exception.** In the browser, the JS SDK's store is
    **in-memory only** — the persistence directory string is just a
    namespace, nothing is written to IndexedDB / localStorage /
    sessionStorage, and all synced data is gone on reload or tab close. A web
    peer therefore re-syncs its whole subscription set from scratch every
    session; size subscriptions accordingly.
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
   still matches) or `DELETE` (mesh-wide — it writes a tombstone that
   replicates, so the document goes away everywhere).

## Attachments

By default, subscriptions sync documents, not attachment payloads. A document
containing an attachment arrives with an *attachment token*; the binary is
fetched explicitly, on demand, and can come from any peer that has it. Design
bulk data as attachments (or a separately-subscribed collection) rather than
embedding it in subscribed documents.

**Auto-fetch.** If you want attachment bytes to flow with the documents
instead of waiting for an SDK request, set the `attachments_auto_fetch` system
parameter. It is a boolean, defaults to `false`, and is settable via DQL on
4.14.x, 5.0.x, and 5.1.x:

```sql
ALTER SYSTEM SET attachments_auto_fetch = true;
SHOW attachments_auto_fetch;  -- { "attachments_auto_fetch": true }
```

When `true`, this peer automatically fetches attachments belonging to
documents that match its own subscriptions, with no `fetchAttachment` call.
That is convenient but unbounded: every attachment on every matching document
is pulled to this device, so weigh it against device storage and transport
budget (BLE especially) before enabling it fleet-wide. Leave it `false` and
fetch on demand when only a subset of attachments is ever displayed.

## Observing vs subscribing

Two APIs are easy to confuse. The shortest way to keep them straight is where
each one's results end up:

- **Subscription → results in the store.** It controls what the mesh sends to
  this device, and matching documents are written into the local store, where
  they persist across restarts (except in the browser — see above). No
  callback fires locally; there is nothing to "handle".
- **Observer → results in memory.** It runs a query against the local store
  and hands the result set to a change callback. It stores nothing, persists
  nothing, and syncs nothing.

Corollary: an observer alone never causes data to arrive from other peers,
and a subscription alone never gives the app anything to render. Production
apps need both.

Typical pattern: a broad, stable subscription brings the data in; observers
with narrower, changing queries present slices of it to the user.
