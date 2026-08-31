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
  '_id': 'order-2026-00042',
  'store':    { 'id': 42, 'name': 'Portland Pearl', 'region': 'us-west' },
  'cashier':  'emp-991',
  'customer': { 'name': 'Ada Lovelace', 'email': 'ada@example.com', 'tier': 'gold' },
  'items': {
    'SKU-100': { 'name': 'Widget', 'qty': 2, 'price_cents': 1999, 'discount_bps': 1000 },
    'SKU-205': { 'name': 'Gadget', 'qty': 1, 'price_cents':  499 }
  },
  'subtotal_cents': 4497, 'tax_cents': 360, 'total_cents': 4857,
  'status': 'placed',
  'status_log': { '2026-08-25T10:30:45.891Z': 'placed' },
  'receipt': { 'id': '<attachment-token>', 'len': 389112, 'metadata': { 'mime': 'application/pdf' } },
  'createdAt': '2026-08-25T10:30:45.891Z'
});
```

Inventory side (the actual counter):

```sql
INSERT INTO COLLECTION products (stock COUNTER)
VALUES ({ '_id': 'SKU-100', 'stock': 500 });

UPDATE COLLECTION products (stock COUNTER)
APPLY stock INCREMENT BY -2          -- sale of qty 2
WHERE _id = 'SKU-100';               -- COUNTER requires 4.14+
```

## When to split instead

If the intake answers "shoppers build carts for days across devices, and cart edits pour in from phone + web simultaneously", promote items to a child collection (and drop the embedded `items` map entirely):

```sql
INSERT INTO order_items
DOCUMENTS ({
  '_id': 'order-2026-00042:SKU-100',   -- composite string id: parent + line
  'order_id': 'order-2026-00042',
  'sku': 'SKU-100', 'qty': 2, 'price_cents': 1999
});
```

- **5.1+**: `SELECT * FROM orders INNER JOIN order_items ON orders._id = order_items.order_id` — create an index on `order_items.order_id` first (JOIN right side must be `_id` or indexed).
- **4.14.x**: two fetches — `SELECT * FROM orders WHERE _id = …` plus `SELECT * FROM order_items WHERE order_id = …`.

## Budget

Order doc ≈ 2–4 KiB after moving the PDF to an ATTACHMENT — safe on every transport including BLE. Receipt blob syncs lazily via `fetchAttachment` only when a user actually views the receipt.
