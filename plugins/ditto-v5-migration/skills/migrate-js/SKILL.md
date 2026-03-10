---
name: migrate-js
description: Use when migrating Ditto JavaScript/TypeScript SDK applications from v4.14 to v5.0. Covers Ditto.open() factory (constructor made private), Store.transaction() replacing Store.write(), attachment token changes, bigint DQL support, single type parameter observer, DQLQueryArguments rename, and DQL migration. Applies to Node.js, React Native, and browser environments.
---

# Ditto JavaScript/TypeScript SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Init | `new Ditto(identity, path)` | `await Ditto.open(config)` or `Ditto.openSync(config)` |
| Identity | `OnlinePlaygroundIdentity`, etc. | `DittoConfig` / `DittoConfigConnect*` |
| Sync | `ditto.startSync()` / `stopSync()` | `ditto.sync.start()` / `sync.stop()` |
| Write tx | `store.write()` | `store.transaction()` |
| Observer | `registerObserver<T,U>()` (2 type params) | `registerObserver<T>()` (1 type param) |
| Subscription | `registerSubscription<T>()` (typed) | `registerSubscription()` (no type param) |
| Attachment | `fetchAttachment(AttachmentToken)` | `fetchAttachment(plain object)` |
| Query args | `QueryArguments` | `DQLQueryArguments` (adds `bigint`) |
| Sort direction | `SortDirection` export | Removed — use `ASC`/`DESC` in DQL |
| Write strategy | `WriteStrategy` export | Removed — use `ON ID CONFLICT` in DQL |

---

## 1. Initialization — Constructor Is Private

**v4.14:**
```typescript
import { Ditto, OnlinePlaygroundIdentity } from "@dittolive/ditto";

const identity = new OnlinePlaygroundIdentity({
    appID: "my-app-id",
    token: "my-token",
    customAuthURL: "https://my-app-id.cloud.ditto.live"
});

const ditto = new Ditto(identity, "/path/to/persistence");
ditto.startSync();
```

**v5.0:**
```typescript
import { Ditto, DittoConfig } from "@dittolive/ditto";

const config = new DittoConfig(
    "my-app-id",
    { mode: 'server', url: "https://my-app-id.cloud.ditto.live" }
);

const ditto = await Ditto.open(config);
// OR synchronous:
// const ditto = Ditto.openSync(config);

ditto.sync.start();
```

### Identity → DittoConfig Mapping

| v4.14 | v5.0 |
|-------|------|
| `new OnlinePlaygroundIdentity({ appID, token, customAuthURL })` | `new DittoConfig(databaseID, { mode: 'server', url })` |
| `new OnlineWithAuthenticationIdentity({ appID, customAuthURL })` | `new DittoConfig(databaseID, { mode: 'server', url })` + auth handler |
| `new OfflinePlaygroundIdentity({ appID })` | `new DittoConfig(databaseID, { type: 'smallPeersOnly', privateKey: undefined })` |
| `makeIdentityConfig(...)` | `new DittoConfig(...)` |

---

## 2. Sync API

```typescript
// v4.14
ditto.startSync();
ditto.stopSync();
const active = ditto.isSyncActive;

// v5.0
ditto.sync.start();
ditto.sync.stop();
const active = ditto.sync.isActive;
```

---

## 3. Authentication Handler

```typescript
// v5.0
await ditto.auth.setExpirationHandler(async (dittoAuth, secondsRemaining) => {
    if (secondsRemaining === 0) {
        // Initial auth or expired
        const token = await fetchTokenFromServer();
        await dittoAuth.login(token, "my-provider");
    } else {
        // Token expiring soon
        const newToken = await refreshToken();
        await dittoAuth.login(newToken, "my-provider");
    }
});
```

---

## 4. Write Transactions — `write()` → `transaction()`

```typescript
// v4.14
await ditto.store.write(async (tx) => {
    await tx.collection("cars").upsert({ _id: "car-1", color: "blue" });
});

// v5.0
await ditto.store.transaction(async (tx) => {
    await tx.execute(
        "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
        { doc: { _id: "car-1", color: "blue" } }
    );
});
```

---

## 5. Observer — Single Type Parameter

```typescript
// v4.14 — two type params
const observer = ditto.store.registerObserver<Car, CarExtra>(
    "SELECT * FROM cars",
    {},
    (result) => { /* ... */ }
);

// v5.0 — one type param, untyped StoreObserver returned
const observer = ditto.store.registerObserver<Car>(
    "SELECT * FROM cars",
    {},
    (result) => {
        const cars = result.items.map(item => item.value as Car);
        updateUI(cars);
    }
);

// Cancel observer
observer.cancel();
```

---

## 6. Sync Subscription — No Type Parameter

```typescript
// v4.14
const sub = ditto.sync.registerSubscription<Car>(
    "SELECT * FROM cars WHERE color = :color",
    { color: "blue" }
);

// v5.0 — no type param
const sub = ditto.sync.registerSubscription(
    "SELECT * FROM cars WHERE color = :color",
    { color: "blue" }
);
sub.cancel();
```

---

## 7. Attachment — Plain Object Instead of Token

```typescript
// v4.14
const token: AttachmentToken = doc.attachment;
const fetchResult = await ditto.store.fetchAttachment(token, (event) => {
    // progress
});

// v5.0 — pass plain object, not AttachmentToken instance
const token = item.value["attachment"]; // plain object from query result
const fetchResult = await ditto.store.fetchAttachment(token, (event) => {
    if (event.type === "progress") {
        console.log(`${event.downloadedBytes} / ${event.totalBytes}`);
    }
});
```

---

## 8. DQL Query Arguments

```typescript
// v4.14
import { QueryArguments } from "@dittolive/ditto";
const args: QueryArguments = { color: "blue" };

// v5.0 — renamed, adds bigint support
import { DQLQueryArguments } from "@dittolive/ditto";
const args: DQLQueryArguments = {
    color: "blue",
    count: 42n  // bigint now supported
};
```

---

## 9. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

```typescript
const ditto = await Ditto.open(config);
// MUST set BEFORE sync.start() if maintaining v4 behavior
await ditto.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = true");
ditto.sync.start();
```

---

## 10. DQL Migration — Legacy Collection API → DQL

### Query

```typescript
// v4.14
const cars = await ditto.store.collection("cars").find("color == 'blue'").exec();
const car = await ditto.store.collection("cars").findByID("car-1").exec();

// v5.0
const result = await ditto.store.execute(
    "SELECT * FROM cars WHERE color = :color",
    { color: "blue" });
const result = await ditto.store.execute(
    "SELECT * FROM cars WHERE _id = :id",
    { id: "car-1" });
```

### Insert

```typescript
// v4.14
await ditto.store.collection("cars").upsert({ _id: "car-1", color: "blue" });

// v5.0
await ditto.store.execute(
    "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    { doc: { _id: "car-1", color: "blue" } });
```

### Update

```typescript
// v4.14
await ditto.store.collection("cars").findByID("car-1").update((doc) => {
    doc["color"].set("green");
});

// v5.0
await ditto.store.execute(
    "UPDATE cars SET color = :color WHERE _id = :id",
    { color: "green", id: "car-1" });
```

### Delete

```typescript
// v4.14
await ditto.store.collection("cars").findByID("car-1").remove();

// v5.0
await ditto.store.execute(
    "DELETE FROM cars WHERE _id = :id",
    { id: "car-1" });
```

### Evict

```typescript
// v4.14
await ditto.store.collection("cars").findByID("car-1").evict();

// v5.0
await ditto.store.execute(
    "EVICT FROM cars WHERE _id = :id",
    { id: "car-1" });
```

### Observers

```typescript
// v4.14
const liveQuery = ditto.store.collection("cars")
    .find(`_id.locationId == '${locationId}'`)
    .observeLocal((docs, event) => {
        if (event.isInitial || event.insertions.length > 0) {
            updateUI(docs);
        }
    });

// v5.0
const observer = ditto.store.registerObserver(
    "SELECT * FROM cars WHERE _id.locationId = :locationId",
    { locationId },
    (result) => {
        const cars = result.items.map(item => item.value);
        updateUI(cars);
    });
observer.cancel(); // when done
```

### Subscriptions

```typescript
// v4.14
const sub = ditto.store.collection("cars")
    .find("color == 'red'").subscribe();

// v5.0
const sub = ditto.sync.registerSubscription(
    "SELECT * FROM cars WHERE color = :color",
    { color: "red" });
sub.cancel();
```

### Counters

```typescript
// v4.14
await ditto.store.collection("cars").findByID(id).update((doc) => {
    doc["viewCount"].counter.increment(1);
});

// v5.0
await ditto.store.execute(
    "UPDATE cars APPLY viewCount PN_INCREMENT BY :n WHERE _id = :id",
    { n: 1, id });
```

---

## 11. Back Pressure (registerObserverWithSignalNext)

Use `registerObserverWithSignalNext` when your handler needs time to process results before receiving the next update. The standard `registerObserver` auto-calls `signalNext()` in a `finally` block after each invocation.

**Coalescing**: changes that occur while your handler executes are coalesced — you get the latest state.

```typescript
// Standard (auto-signal)
const observer = ditto.store.registerObserver(
    "SELECT * FROM cars",
    (result) => {
        updateUI(result.items);
    }
);

// Back-pressure (manual signal)
const observer = ditto.store.registerObserverWithSignalNext(
    "SELECT * FROM cars",
    async (result, signalNext) => {
        await expensiveRender(result.items);
        signalNext();  // Call when ready for next update
    }
);
observer.cancel();
```

Types:
- `StoreObservationHandlerWithSignalNext<T> = (queryResult: QueryResult<T>, signalNext: () => any) => void`

---

## 12. New APIs in v5

- **`Ditto.open(config)`** / **`Ditto.openSync(config)`** — static factory methods (constructor is now private)
- **`DittoConfig`** / **`DittoConfigConnect*`** — new configuration hierarchy replacing all `Identity` types
- **`Store.transaction(callback)`** — replaces `Store.write()`
- **`DQLQueryArguments`** / **`DQLQueryArgumentValue`** — typed DQL params with `bigint` support
- **`StoreObserver`** — unified untyped observer (one type param instead of two)
- **`SyncSubscription`** — unified subscription (no type param)

## 13. Removed Exports

These types were exported in v4 but removed in v5:

| Removed | Reason |
|---------|--------|
| `SortDirection` | Use `ASC`/`DESC` directly in DQL `ORDER BY` |
| `WriteStrategy` | Use `ON ID CONFLICT DO UPDATE/NOTHING/FAIL` in DQL |
| `Counter` / `MutableCounter` | DQL CRDT types |
| `Register` / `MutableRegister` | DQL CRDT types |
| `DocumentID` / `DocumentIDValue` | DQL string IDs |
| `Collection` / `CollectionInterface` | DQL |
| `LiveQuery` / `LiveQueryEvent` | `StoreObserver` |
| `PendingCursorOperation` | DQL |
| `WriteTransaction` / `WriteTransactionResult` | `store.transaction()` |

---

## 14. Migration Checklist

### Initialization
- [ ] Replace `new Ditto(identity, path)` with `await Ditto.open(config)` or `Ditto.openSync(config)`
- [ ] Create `DittoConfig` replacing all `*Identity` types
- [ ] Set `DQL_STRICT_MODE=true` BEFORE `sync.start()` if maintaining v4 behavior
- [ ] Update `startSync()` → `sync.start()`

### Authentication
- [ ] Call `await ditto.auth.setExpirationHandler(...)` after open
- [ ] Make handler async if calling `dittoAuth.login()`

### Store Operations
- [ ] Replace `store.write()` → `store.transaction()`
- [ ] Replace all `collection("x").find(...)` chains with `store.execute()` DQL
- [ ] Replace `.upsert()` → `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Replace update closures → `UPDATE SET`
- [ ] Replace `.remove()` → `DELETE FROM`
- [ ] Replace `.evict()` → `EVICT FROM`
- [ ] Replace `.observeLocal()` → `store.registerObserver()`
- [ ] Replace `.subscribe()` → `sync.registerSubscription()`

### Types
- [ ] Update `registerObserver<T,U>()` → `registerObserver<T>()`
- [ ] Update `registerSubscription<T>()` → `registerSubscription()`
- [ ] Rename `QueryArguments` → `DQLQueryArguments`
- [ ] Update `fetchAttachment(AttachmentToken)` → `fetchAttachment(plain object)`
- [ ] Remove imports of `SortDirection`, `WriteStrategy`, removed types

### Query Safety
- [ ] Never use string interpolation in DQL — use `{ paramName: value }` arguments
- [ ] Add `ON ID CONFLICT DO UPDATE` to all INSERT statements meant as upserts

---

## Common Pitfalls

1. **Constructor is private**: `new Ditto(...)` is a compile error in v5. Use `Ditto.open()` or `Ditto.openSync()`.

2. **`store.write()` → `store.transaction()`**: Easy rename but note the callback now uses DQL `tx.execute()` not collection methods.

3. **Attachment token type**: Passing an `AttachmentToken` instance to `fetchAttachment()` throws. Extract as plain value from query result.

4. **DQL_STRICT_MODE silent change**: Default flipped. Use parameterized queries, never string interpolation.

5. **Two-type observer**: `registerObserver<T,U>()` won't compile. Remove the second type parameter.

---

## Official Documentation

- Node.js V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/node-js-v4
- Web JS V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/web-js-v4
- Node.js DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/node-js-dql
- DQL Reference: https://docs.ditto.live/dql/dql
