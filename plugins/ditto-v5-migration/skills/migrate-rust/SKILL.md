---
name: migrate-rust
description: Use when migrating Ditto Rust SDK applications from v4.14 to v5.0. Covers Ditto::open() replacing DittoBuilder, AppId→DatabaseId rename, _v2 suffix removal from all methods, DiskUsageChild→DiskUsageItem, DittoConfigConnect variants, and DQL migration from legacy query_builder module.
---

# Ditto Rust SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Init | `Ditto::builder()...build()` | `Ditto::open(DittoConfig)` or `Ditto::open_sync(DittoConfig)` |
| App ID type | `AppId` | `DatabaseId` |
| Sync | `ditto.start_sync()` / `stop_sync()` | `ditto.sync().start()` / `.stop()` |
| DQL execute | `store.execute_v2(query, args)?` | `store.execute(query, args)?` |
| Observers | `store.register_observer_v2(...)` | `store.register_observer(...)` |
| Disk usage | `DiskUsageChild` | `DiskUsageItem` |
| Version | `ditto.sdk_version()` | `ditto.version()` |
| Peer key | `Peer.peer_key_string` + `Peer.peer_key: Vec<u8>` | `Peer.peer_key: String` |
| Cloud | `Peer.is_connected_to_ditto_cloud` | `Peer.is_connected_to_ditto_server` |

---

## 1. Initialization — Builder → `Ditto::open()`

**v4.14 (DittoBuilder):**
```rust
use ditto::*;

let ditto = Ditto::builder()
    .with_temp_dir()
    .with_identity(|ditto_root| {
        identity::OfflinePlayground::new(ditto_root, AppId::from_str(APP_ID)?)
    })?
    .with_minimum_log_level(LogLevel::Debug)
    .with_transport_config(|_| {
        let mut config = TransportConfig::default();
        config.peer_to_peer.lan.enabled = true;
        config
    })?
    .build()?;

ditto.set_license_from_env("DITTO_LICENSE")?;
ditto.sync().start()?;
```

**v5.0 (DittoConfig):**
```rust
use ditto::*;

let ditto = Ditto::open(
    DittoConfig::new(
        DatabaseId::from_str(APP_ID)?,
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory("/path/to/data"),
)?;

ditto.auth().set_expiration_handler(|dittoAuth, _seconds_remaining| {
    dittoAuth.auth().login("your-token", "__playgroundProvider", |_client_info, error| {
        if let Some(e) = error {
            println!("Auth failed: {}", e);
        }
    });
});

DittoLogger::set_minimum_log_level(LogLevel::Debug);

ditto.update_transport_config(|tc| {
    tc.peer_to_peer.lan.enabled = true;
    tc.peer_to_peer.lan.mdns_enabled = true;
});

ditto.sync().start()?;
```

### `DittoConfigConnect` Variants

| v4.14 Identity | v5.0 DittoConfigConnect |
|----------------|------------------------|
| `identity::OnlinePlayground::new(root, app_id, token, ...)` | `DittoConfigConnect::Server { url: "https://...".to_string() }` |
| `identity::OnlineWithAuthentication::new(root, app_id, ...)` | `DittoConfigConnect::Server { url: "...".to_string() }` + auth handler |
| `identity::OfflinePlayground::new(root, app_id)` | `DittoConfigConnect::SmallPeersOnly { private_key: None }` |
| `identity::SharedKey::new(root, app_id, shared_key)` | `DittoConfigConnect::SmallPeersOnly { private_key: Some(key) }` |

---

## 2. `AppId` → `DatabaseId`

```rust
// v4.14
use ditto::AppId;
let app_id = AppId::from_str("my-app-id")?;

// v5.0
use ditto::DatabaseId;
let database_id = DatabaseId::from_str("my-app-id")?;
```

Update all `AppId` references to `DatabaseId` throughout the codebase.

---

## 3. Sync API

```rust
// v4.14
ditto.start_sync()?;
ditto.stop_sync();
let active = ditto.is_sync_active();

// v5.0
ditto.sync().start()?;
ditto.sync().stop();
let active = ditto.sync().is_active();
```

---

## 4. `_v2` Suffix Removal — ALL Methods

All `_v2` variants are now the canonical API. Drop the suffix everywhere.

```rust
// v4.14
let result = store.execute_v2("SELECT * FROM cars", None)?;
let observer = store.register_observer_v2("SELECT * FROM cars", None, |result| {
    // handle result
})?;

// v5.0 — same methods, no _v2 suffix
let result = store.execute("SELECT * FROM cars", None)?;
let observer = store.register_observer("SELECT * FROM cars", None, |result| {
    // handle result
})?;
```

**All affected methods** (drop `_v2` suffix):
- `execute_v2` → `execute`
- `register_observer_v2` → `register_observer`
- Any other `_v2` methods in your codebase

---

## 5. Back Pressure (register_observer_with_signal_next)

Standard `register_observer` auto-calls `signal_next` after your closure returns, and callbacks are never concurrent. Use `register_observer_with_signal_next` to call `signal_next` manually when your handler is ready for the next update.

**Coalescing**: changes that occur while your handler executes are coalesced — you get the latest state, not every intermediate change.

```rust
// Standard (auto-signal, non-concurrent)
let _observer = store.register_observer(
    "SELECT * FROM cars",
    move |query_result| {
        for item in query_result.iter() {
            process(item);
        }
    },
)?;

// Back-pressure (manual signal)
let _observer = store.register_observer_with_signal_next(
    "SELECT * FROM cars",
    move |query_result, signal_next| {
        for item in query_result.iter() {
            expensive_process(item);
        }
        signal_next();  // Call when ready for the next callback
    },
)?;
```

Types:
- `SignalNext` — `FnOnce() + 'static + Send`
- `ChangeHandlerWithSignalNext` — `FnMut(QueryResult, Box<dyn SignalNext>) + 'static + Send + Sync`

---

## 6. Version Method

```rust
// v4.14
let version = ditto.sdk_version();

// v5.0
let version = ditto.version();
```

---

## 7. `DiskUsageChild` → `DiskUsageItem`

```rust
// v4.14
let child: DiskUsageChild = disk_usage.children[0];

// v5.0
let item: DiskUsageItem = disk_usage.items[0];
```

---

## 8. Peer Key

```rust
// v4.14
let key_string: String = peer.peer_key_string;
let key_bytes: Vec<u8> = peer.peer_key;

// v5.0 — unified String field
let key: String = peer.peer_key;
```

---

## 9. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

```rust
// If maintaining v4 behavior, set BEFORE sync start:
let ditto = Ditto::open(config)?;
ditto.store().execute(
    "ALTER SYSTEM SET DQL_STRICT_MODE = true",
    None
)?;
ditto.sync().start()?;
```

---

## 10. DQL Migration — Legacy Query Builder → DQL

For help with migrations to DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations - it's recommended to use the [DQL plugin](../ditto-dql).

The entire `query_builder` module is removed. Use `store.execute()` and `store.register_observer()`.

### Query

```rust
// v4.14
let cars = store.collection("cars")?.find_all().exec()?;
let car = store.collection("cars")?.find_by_id(&id)?.exec()?;
let filtered = store.collection("cars")?.find("color == 'blue'")?.exec()?;

// v5.0
let result = store.execute("SELECT * FROM cars", None)?;
let result = store.execute(
    "SELECT * FROM cars WHERE _id = :id",
    Some(serde_json::json!({"id": id})))?;
let result = store.execute(
    "SELECT * FROM cars WHERE color = :color",
    Some(serde_json::json!({"color": "blue"})))?;
```

### Insert

```rust
// v4.14
store.collection("cars")?.upsert(serde_json::json!({
    "_id": id, "color": "blue"
}), None)?;

// v5.0
store.execute(
    "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    Some(serde_json::json!({"doc": {"_id": id, "color": "blue"}})))?;
```

### Update

```rust
// v4.14
store.collection("cars")?.find_by_id(&id)?.update(|doc| {
    doc["color"] = json!("green");
})?;

// v5.0
store.execute(
    "UPDATE cars SET color = :color WHERE _id = :id",
    Some(serde_json::json!({"color": "green", "id": id})))?;
```

### Delete

```rust
// v4.14
store.collection("cars")?.find_by_id(&id)?.remove()?;

// v5.0
store.execute(
    "DELETE FROM cars WHERE _id = :id",
    Some(serde_json::json!({"id": id})))?;
```

### Evict

```rust
// v4.14
store.collection("cars")?.find_by_id(&id)?.evict()?;

// v5.0
store.execute(
    "EVICT FROM cars WHERE _id = :id",
    Some(serde_json::json!({"id": id})))?;
```

### Observers

```rust
// v4.14
let observer = store.collection("cars")?
    .find("color == 'blue'")?
    .observe_local(|docs, event| {
        for doc in &docs { /* process */ }
    })?;

// v5.0
let observer = store.register_observer(
    "SELECT * FROM cars WHERE color = :color",
    Some(serde_json::json!({"color": "blue"})),
    |result| {
        for item in result.items() { /* process */ }
    })?;
// Cancel with: observer.cancel();
```

### Sync Subscriptions

```rust
// v4.14
let sub = store.collection("cars")?
    .find("color == 'red'")?
    .subscribe()?;

// v5.0
let sub = ditto.sync().register_subscription(
    "SELECT * FROM cars WHERE color = :color",
    Some(serde_json::json!({"color": "red"})))?;
```

---

## 11. APIs Removed With No Replacement

- `disable_sync_with_v3()` — v3 protocol fully dropped
- `DittoLogger::set_emoji_log_heading(...)` — emoji log headings removed
- `WriteStrategy` enum — DQL insert/update semantics replace this


## 12. New APIs in v5

- **`Ditto::open(DittoConfig)`** — static factory replacing `DittoBuilder`
- **`Ditto::open_sync(DittoConfig)`** — synchronous variant
- **`DatabaseId`** — replaces `AppId`
- **`DittoConfig::new(database_id, connect)`** — unified config with `system_parameters` support
- **`DittoConfigConnect::Server { url }`** / **`DittoConfigConnect::SmallPeersOnly { private_key }`** — connect mode variants
- **`ditto.version()`** — replaces `sdk_version()`
- **`DiskUsageItem`** — replaces `DiskUsageChild`
- **`DittoLogger::set_custom_log_callback()`** — custom log callback support
- `store.execute()` and `store.register_observer()` as canonical DQL API (no more `_v2` suffix)
---

## 13. Migration Checklist

### Types
- [ ] Replace all `AppId` with `DatabaseId`
- [ ] Replace all `DiskUsageChild` with `DiskUsageItem`

### Initialization
- [ ] Replace `Ditto::builder()...build()` with `Ditto::open(DittoConfig::new(database_id, connect))`
- [ ] Remove `set_license_from_env` if no longer needed (check v5 licensing model)
- [ ] Move log level config to `DittoLogger::set_minimum_log_level()`
- [ ] Move transport config to `ditto.update_transport_config(|tc| { ... })`
- [ ] Set `DQL_STRICT_MODE=true` BEFORE `sync().start()` if maintaining v4 behavior

### Sync
- [ ] Update `ditto.start_sync()` → `ditto.sync().start()`
- [ ] Update `ditto.stop_sync()` → `ditto.sync().stop()`

### Methods
- [ ] Remove all `_v2` suffixes: `execute_v2` → `execute`, `register_observer_v2` → `register_observer`
- [ ] Update `ditto.sdk_version()` → `ditto.version()`

### Data Operations
- [ ] Replace all `store.collection("x")...` chains with `store.execute()` DQL
- [ ] Replace `.upsert()` with `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Replace update closures with `UPDATE SET`
- [ ] Replace `.remove()` with `DELETE FROM`
- [ ] Replace `.evict()` with `EVICT FROM`
- [ ] Replace `.observe_local()` with `store.register_observer()`
- [ ] Replace `.subscribe()` with `ditto.sync().register_subscription()`

### Peer Info
- [ ] Update `peer.peer_key_string` + `peer.peer_key: Vec<u8>` → `peer.peer_key: String`
- [ ] Update `peer.is_connected_to_ditto_cloud` → `peer.is_connected_to_ditto_server`

---

## Common Pitfalls

1. **`_v2` cleanup**: Easy to miss in large codebases. Search for `_v2` and remove the suffix from all occurrences.

2. **`AppId` → `DatabaseId`**: `AppId` type won't compile. Search for `AppId` and update to `DatabaseId`.

3. **Builder to config**: `DittoBuilder` is gone. The new `DittoConfig::new(database_id, connect)` pattern is simpler but the argument order and types differ.

4. **DQL_STRICT_MODE silent change**: Default flipped from true→false. Objects may merge instead of replace without this setting.

5. **Transport config moved**: In v4, transport was configured in the builder. In v5, use `ditto.update_transport_config()` after `Ditto::open()`.

---

## Official Documentation

- Rust V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/rust-v4
- Rust DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/rust-dql
- DQL Reference: https://docs.ditto.live/dql/dql
