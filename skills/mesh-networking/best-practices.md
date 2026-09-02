# Designing Data and Transports Together

Ditto's data-modeling advice is **not transport-neutral**. The schema that performs
perfectly on a LAN can make an app feel broken on Bluetooth LE. This file connects the two
decisions.

For DQL syntax, CRDT type semantics, and general schema-versioning guidance, use the
`write-dql` skill — this file covers only what changes *because of the transport mix*.

---

## 1. The mechanism: why transport choice reaches into your schema

Three facts, and everything else follows from them.

**Fact 1 — Bandwidth differs by three orders of magnitude.** Bluetooth LE gives roughly
**20 KB/s** of effective throughput in a Ditto mesh. LAN and peer-to-peer Wi-Fi give tens
to hundreds of megabits per second. This is not a tuning difference; it is a different
category of link.

**Fact 2 — Sync is delta-based, but merge and arrival are whole-document.** Ditto sends
only the fields that changed, so a small edit produces a small update on the wire. But:

- **Merging costs the whole document.** Ditto clones, merges, re-serializes and re-indexes
  the full document on every update, even a one-field change. (The CRDT merge itself
  descends only into changed keys; it is the surrounding write path that pays full size.) A
  one-byte edit to a 5 MiB document costs 5 MiB of work on every peer that reconciles it.
- **Arrival is all-or-nothing.** A document does not appear in query results on the
  receiving peer until every part of it has arrived. Partial documents are never visible.
- **A peer that has never seen a document receives all of it.** Delta sync is computed
  against the *receiver's* known version, so it only helps peers that already hold one.
  Every new peer, and every peer subscribing to a document for the first time, pays full
  size. (Re-subscribing does not: a peer that already holds the document does not re-receive
  it.)

**Fact 3 — Documents have size thresholds.** Defaults, and they must match on every peer in
the mesh, cloud peers included:

| Threshold | Size | Behavior | Set with |
|---|---|---|---|
| Soft | **256 KiB** | Write succeeds; logs a `warn` | `document_size_soft_limit_bytes` |
| Hard | **5 MiB** | **Local write rejected with an error** on current SDKs (older builds logged and accepted). Gates local writes only — oversized documents already in the mesh still replicate in | `document_size_hard_limit_bytes` |

Put those together and the cost of a large document is paid on **every merge and every peer
seeing it for the first time** — and on BLE it is paid at 20 KB/s.

---

## 2. The rule

> **The slower your slowest depended-on transport, the smaller your documents should be.**

Concretely, replication time over BLE:

| Document size | BLE replication | Visible to queries |
|---|---|---|
| 2 KB | sub-second | immediately, effectively |
| 25 KB | ~1 second | after ~1 second |
| 256 KiB (soft limit) | 10+ seconds | **only after 10+ seconds** |
| 5 MiB (hard limit) | minutes | **only after minutes** |

The middle column is bandwidth; the right column is user experience. Ten 25 KB documents
and one 250 KB document move the same bytes, but the ten become individually useful as they
land, while the one shows nothing until the whole transfer completes. On a warehouse floor
with only BLE, that's the difference between a list that fills in progressively and a screen
that appears frozen.

**But do not apply this rule where it doesn't earn its keep.** Ditto's default advice is to
**embed related data in one document** — typically as a map keyed by ID — because that gives
you atomic single-document writes and add-wins map merge for concurrent edits to different
sub-entities. On LAN or cloud-only deployments the size difference is imperceptible, and
splitting documents to chase BLE performance you don't need trades a real benefit
(atomicity, clean merges) for none.

---

## 3. Decision table

| Your transport reality | Model this way |
|---|---|
| **BLE is a transport you depend on** (mixed iOS/Android fleet, unreliable Wi-Fi, hostile RF) | Many small documents. Split anything that grows unbounded. Target well under the 256 KiB soft limit — think tens of KB. Push binary into `ATTACHMENT`. |
| **P2P Wi-Fi (AWDL / Wi-Fi Aware) is your fast path, BLE is fallback** | Model for BLE anyway if BLE is the *only* path in your worst case. If BLE only ever carries presence and small deltas, moderate embedding is fine. |
| **LAN or cloud only; BLE is off or genuinely never used** | Standard Ditto modeling: embed related data, use maps keyed by ID, split only for permission scope, independent access at scale, or the size limits. |
| **Browsers / Wasm** | WebSocket only. Size matters far less; latency and subscription scope matter more. |

---

## 4. Practical techniques

### Attachments for anything binary

The `ATTACHMENT` type stores blobs out-of-band. Three properties matter here:

1. **Attachment bytes do not count toward document size limits.** A document with a 40 MB
   video attachment is still a small document.
2. **Peers fetch attachments explicitly rather than receiving them automatically.** This is
   the important one for BLE: a large image never sits in front of the document updates
   queued behind it. The document — with its attachment token — arrives fast; the bytes come
   later, on demand, only for peers that actually want them.
3. **The document field holds a token, not the data.** It merges last-write-wins; the blob
   itself is content-addressed and atomic (no partial update — replace or remove).

Rule of thumb: **if it isn't queryable, it shouldn't be in the document.** Images, PDFs,
audio, video, serialized payloads — attachment.

### Split on the axis that actually grows

When you split, split where growth is unbounded rather than by tidiness. A `team` document
with three members embedded is fine forever. A `conversation` document with an embedded
message list is a time bomb — every new message re-merges the whole history.

Ask: *"what does this document look like after a year of use?"* If the answer is
"unbounded", that sub-entity belongs in its own collection with a foreign key back to
the parent.

### Scope subscriptions, not just documents

Document size is one lever; **how much data a peer subscribes to** is the other, and on BLE
it is often the bigger one. A peer that subscribes to everything pays full replication cost
for the entire dataset over a 20 KB/s link on first sync.

Narrow subscriptions to what the device actually needs — by location, by status, by recency.
This costs nothing on LAN and is decisive on BLE.

### Use sync groups to keep irrelevant peers out of the radio budget

If two sets of devices never need each other's data, putting them in different sync groups
stops them spending discovery and connection budget on each other. On BLE, where a peer has
only 2–3 outgoing connection slots, keeping the wrong peers out of those slots directly
improves convergence for the right ones.

Sync groups are an optimization, not a security control — see
[`references/mesh-formation.md`](references/mesh-formation.md#7-sync-groups).

### Keep peer metadata tiny

Peer metadata syncs across the mesh **on every new connection**. Large metadata slows or
disrupts connection establishment for everybody, and does so worst on BLE. The hard limit is
**4 KB** when JSON-encoded, but the target should be *bytes to low kilobytes*. (The 128 KB
figure sometimes quoted belongs to the separate *Small Peer Info* metadata API.) It is also visible to every peer
in the mesh — keep it non-sensitive.

### Prefer counters and maps over rewrite-everything patterns

Read-modify-write of a whole nested object produces a larger delta than mutating the
specific field. Use the CRDT types that express the intent — `COUNTER` for tallies, maps
for keyed collections — so the delta stays proportional to the change. See the `write-dql`
skill for the type semantics.

---

## 5. Monitoring and remediation

**Watch for the soft-limit warning.** A `warn` about `document_size_soft_limit_bytes` is
the earliest signal that a document is growing unbounded. Treat it as a defect, not noise —
by the time you see the 5 MiB `error`, the document is already causing minutes-long BLE
transfers and expensive merges.

**Keep the limits identical across the fleet.** Both size parameters must be the same on
every peer, including cloud peers. Mismatched limits mean peers disagree about what is
acceptable.

**Remediating a document that is already too large:**

1. Split nested data into a separate collection keyed by the parent's `_id`.
2. Move binary payloads to `ATTACHMENT` — this alone often drops a document below the soft
   limit immediately.
3. For critically oversized documents, write fresh documents under new `_id` values rather
   than trying to shrink the existing one in place; the old version's history travels with it.

---

## 6. Checklist

Before shipping a schema, confirm:

- [ ] I know which transports this deployment actually depends on **in its worst case**, not
      its best case.
- [ ] If BLE is in that set, no document is expected to exceed tens of KB in normal use.
- [ ] No document contains raw binary. All blobs are `ATTACHMENT`.
- [ ] Every embedded collection has a bounded size, or has been split out.
- [ ] Subscriptions are scoped to what each device needs, not to everything.
- [ ] Peer metadata is bytes-to-kilobytes and contains nothing sensitive.
- [ ] `document_size_soft_limit_bytes` and `document_size_hard_limit_bytes` are identical
      on every peer, cloud included.
- [ ] Soft-limit warnings are surfaced in monitoring, not swallowed.
