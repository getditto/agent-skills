# Cookbook: POS / e-commerce order

Worked example of the review workflow from [`../references/workflow.md`](../references/workflow.md). Covers SDK **4.14.x and 5.1.x**; version gates are tagged inline. All statements assume `dql_strict_mode = false` on every peer (the 5.x default; the migration target for 4.14.x meshes).

## The input JSON

A team migrating a POS app brings this document:

```json
{
  "_id": "order-2026-00042",
  "store": { "id": 42, "name": "Portland Pearl", "region": "us-west" },
  "cashier": "emp-991",
  "customer": { "name": "Ada Lovelace", "email": "ada@example.com", "tier": "gold" },
  "items": [
    { "sku": "SKU-100", "name": "Widget", "qty": 2, "price": 19.99, "discount": 0.10 },
    { "sku": "SKU-205", "name": "Gadget", "qty": 1, "price": 4.99 }
  ],
  "subtotal": 44.97,
  "tax": 3.60,
  "total": 48.57,
  "status": "placed",
  "statusHistory": ["placed"],
  "receiptPdfBase64": "JVBERi0xLjQKJ...<~380 KB truncated>",
  "createdAt": "2026-08-25T10:30:45.891Z",
  "updatedAt": "2026-08-25T10:30:45.891Z"
}
```

## Findings

| Severity | ID | Path | Reason |
|---|---|---|---|
| blocker | `ARRAY_LWW` | `items` | Two devices adding items offline lose one item — whole-array LWW, no error. Severity drops to OK only if items are written exactly once at creation and never edited |
| blocker | `ARRAY_LWW` | `statusHistory` | Append-log in an array: concurrent status transitions drop. Also grows unbounded over a long-lived order |
| blocker | `ATTACHMENT_CANDIDATE` | `receiptPdfBase64` | ~380 KB inline blows the 256 KiB soft limit and every order edit re-syncs the blob's register |
| warn | `COUNTER_CANDIDATE` | (implied) inventory side | `qty` decremented from *product* stock by many devices — that's a counter on the `products` collection, not a field here |
| blocker | `COMPOSITE_ID` | `_id` | Flat string `_id` on a document that is scoped by store. Permission rules can only see `_id`, so a per-store sync rule is impossible to express — and `_id` is immutable, so fixing it later means rewriting every order under a new ID |
| warn | `DECLARE_TYPES` | `store`, `customer` | No declarations on the 5.1.x tablets — the lenient default infers MAP. But the 4.14.x registers under the strict `true` default silently store these as whole-object REGISTERs and drop them from plain reads. Migrate the registers to `dql_strict_mode = false` before the v5 rollout (recommended); declare `MAP` explicitly only on statements still-strict peers execute during the transition |
| warn | `SPLIT_UNBOUNDED` | design-level | If items/history can grow or are edited post-creation, they belong out of the hot order doc |
| info | `FLOAT_MONEY` | `price`, `total` | use integer cents everywhere |
| info | `TIMESTAMP_SKEW` | `statusHistory` keys | device clocks skew; key history entries with high-res ISO-8601 and never exact-match |

## Recommended model — items stay embedded, as a keyed MAP

Most-realistic POS constraint: items are finalized at checkout; disputes edit **quantity or void flags per item** from one register at a time. Keyed MAP handles that with clean merges:

```sql
-- store/customer/items/status_log infer MAP under the lenient default —
-- no MAP/REGISTER declarations on writes or reads. ATTACHMENT is declared:
-- inference can't guess it from a token-shaped object.
INSERT INTO COLLECTION orders (receipt ATTACHMENT)
DOCUMENTS ({
  -- composite object _id: store_id is the permission scope, so it must live
  -- inside _id — that is the only field permission rules and the auth webhook
  -- can see. Immutable, so this is decided now or never.
  '_id':      { 'store_id': 42, 'order_id': 'order-2026-00042' },
  'store':    { 'name': 'Portland Pearl', 'region': 'us-west' },
  'cashier':  'emp-991',
  'customer': { 'name': 'Ada Lovelace', 'email': 'ada@example.com', 'tier': 'gold' },
  'items': {
    'SKU-100': { 'name': 'Widget', 'qty': 2, 'price_cents': 1999, 'discount_bps': 1000 },
    'SKU-205': { 'name': 'Gadget', 'qty': 1, 'price_cents':  499 }
  },
  'subtotal_cents': 4497, 'tax_cents': 360, 'total_cents': 4857,
  'status': 'placed',
  'status_log': { '2026-08-25T10:30:45.891Z': 'placed' },
  'receipt': :receipt,   -- bind ditto.store.newAttachment(pdfPath, { mime: 'application/pdf' })
  'createdAt': '2026-08-25T10:30:45.891Z'
});
```

**Why `store_id` moved into `_id`.** A POS deployment always ends up needing "this store's registers see this store's orders" — enforced by Big Peer sync permissions or an auth webhook, both of which are queries that can see `_id` and nothing else. With a flat `'order-2026-00042'` the scope simply isn't available to them. With the composite object it is, and the subfield is queryable and indexable like any other path:

```sql
SELECT * FROM orders WHERE _id.store_id = 42;
CREATE INDEX IF NOT EXISTS idx_orders_store ON orders (_id.store_id);
```

`store_id` lives in `_id` and nowhere else — there is no second copy in the body. `_id.store_id` is an ordinary path, so predicates, indexes, and JOIN keys all work against it directly; a body copy would only add per-document CRDT metadata and a second value that can drift from the first. The remaining `store` map keeps just the descriptive fields (name, region), which no rule needs to filter on. Verified on 4.14.4, 5.0.0, and 5.1.0. Full rule: [`../references/workflow.md`](../references/workflow.md) §2 `COMPOSITE_ID`.

Inventory side (the actual counter):

```sql
-- Seeding the counter's opening value happens in the INSERT itself. No second
-- statement, no transaction: the COUNTER declaration on the INSERT makes the
-- field a counter, and the value in the document is its starting value.
INSERT INTO COLLECTION products (stock COUNTER)
VALUES ({ '_id': 'SKU-100', 'stock': 500 });

UPDATE COLLECTION products (stock COUNTER)
APPLY stock INCREMENT BY -2          -- sale of qty 2 -> 498
WHERE _id = 'SKU-100';               -- COUNTER requires 4.14+
```

Three things to know about that seed (all executed on 4.14.4, 5.0.0, and 5.1.0):

- **The declaration on the INSERT is what makes it a counter, and it is not optional.** Insert `{'stock': 500}` with no `(stock COUNTER)` and you get a REGISTER holding `500`. A later `APPLY stock INCREMENT BY 3` on that document then reads **3**, not 503 — the counter starts from zero and the register's value is discarded, silently. Same result on both SDK lines. If a field is ever going to be a counter, declare it on the statement that creates the document.
- **A seed is an assignment, not an increment.** Two peers that each seed `stock` to 500 offline converge on 500, not 1000 — normal LWW. That's what you want for an opening balance and wrong for anything else, so seed once, from one authority, and never replay the seed while live increments matter. `ON ID CONFLICT DO NOTHING` is the safe idiom for a seed that might be re-run; `DO UPDATE` re-asserts the baseline every time.
- **Later re-baselining has its own verb.** Use `APPLY stock RESTART WITH 500` (COUNTER only, 4.14+) for a stock recount, rather than re-inserting the document.

## When to split instead

If the intake answers "shoppers build carts for days across devices, and cart edits pour in from phone + web simultaneously", promote items to a child collection (and drop the embedded `items` map entirely):

```sql
INSERT INTO order_items
DOCUMENTS ({
  -- Composite object _id, not 'order-2026-00042:SKU-100'. It carries the same
  -- store scope as the parent order, so the same per-store permission rule
  -- covers both collections.
  '_id': { 'store_id': 42, 'order_id': 'order-2026-00042', 'sku': 'SKU-100' },
  'order_id': 'order-2026-00042',   -- back-reference to the parent: a real field,
  'qty': 2, 'price_cents': 1999     -- indexed below and used as the join key
});

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items (order_id);
```

**Don't reach for a delimiter-joined string `_id` here** (`'order-2026-00042:SKU-100'`). It is the reflex when migrating a relational schema whose primary key was `(order_id, sku)` — the composite key flattened to fit a string-keyed system. Ditto isn't one. The string form breaks as soon as a SKU contains the delimiter, has to be re-parsed at every read, can't be indexed per-component, and hides the store scope from permissions. The object form has none of those problems and reads correctly in the portal and HTTP API. See [`../references/workflow.md`](../references/workflow.md) §2 `COMPOSITE_ID`.

Reads across the split:

- **5.1+**: `SELECT * FROM orders INNER JOIN order_items ON order_items.order_id = orders._id.order_id` — the left side reaches straight into the parent's composite `_id`; the right side is the child's back-reference, which is why that field carries the index above. (The JOIN right side must be `_id` or indexed, and the child's `_id` here is the three-part object, not the order id.)
- **4.14.x**: two fetches — `SELECT * FROM orders WHERE _id = { 'store_id': 42, 'order_id': 'order-2026-00042' }` plus `SELECT * FROM order_items WHERE order_id = …`.

## Budget

Order doc ≈ 2–4 KiB after moving the PDF to an ATTACHMENT — safe on every transport including BLE. Receipt blob syncs lazily via `fetchAttachment` only when a user actually views the receipt.
