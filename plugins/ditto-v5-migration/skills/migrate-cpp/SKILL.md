---
name: migrate-cpp
description: Use when migrating Ditto C++ SDK applications from v4.14 to v5.0. Covers DittoConfig initialization replacing Identity class hierarchy, Ditto::open() factory, header reduction (83→50), Log→Logger rename, std::function callback types, StoreObservationHandlerWithSignalNext rename, and DQL migration from legacy Collection API.
---

# Ditto C++ SDK: v4.14 → v5.0 Migration Reference

## Quick Summary of Changes

| Area | v4.14 | v5.0 |
|------|-------|------|
| Init | `Ditto(identity, persistence_dir)` | `Ditto::open(DittoConfig)` |
| Sync | `ditto->start_sync()` / `stop_sync()` | `ditto->get_sync().start()` / `.stop()` |
| Sync active | `ditto->get_is_sync_active()` | `ditto->get_sync().is_active()` |
| Version | `Ditto::get_sdk_version()` | `Ditto::get_version()` |
| Logger | `Log` class | `Logger` class |
| Log callback | `void(*)(LogLevel, std::string)` raw fn ptr | `std::function<void(LogLevel, const std::string&)>` |
| Observer handler | `StoreObservationHandlerWithNextSignal` / `NextSignal` | `StoreObservationHandlerWithSignalNext` / `SignalNext` |
| Lifetime | `ditto->close()` | `shared_ptr` scope management |
| Headers | 83 header files | 50 header files |

---

## 1. Initialization

**v4.14:**
```cpp
auto identity = Identity::OnlinePlayground(
    "my-app-id",
    "my-token",
    true  // enable_ditto_cloud_sync
);
auto ditto = std::make_shared<Ditto>(identity, "/path/to/persistence");
ditto->start_sync();
```

**v5.0:**
```cpp
auto config = DittoConfig::default_config()
    .set_database_id("my-app-id")
    .set_connect(DittoConfig::Connect::server("https://my-app-id.cloud.ditto.live"));

auto ditto = Ditto::open(config);

ditto->auth().set_expiration_handler([](auto& ditto, int64_t seconds_remaining) {
    ditto.auth().login(
        "your-token",
        Authenticator::get_development_provider(),
        [](auto client_info, auto error) {
            if (error) {
                std::cout << "Authentication failed: " << error->message() << std::endl;
            } else {
                std::cout << "Authentication successful" << std::endl;
            }
        }
    );
});

ditto->get_sync().start();
```

### Identity → DittoConfig Mapping

| v4.14 Identity | v5.0 DittoConfig |
|----------------|-----------------|
| `Identity::OnlinePlayground(app_id, token, ...)` | `DittoConfig::default_config().set_database_id(uuid).set_connect(Connect::server(url))` |
| `Identity::OnlineWithAuthentication(app_id, callback, ...)` | `DittoConfig::default_config().set_database_id(uuid).set_server_connect(url)` + auth handler |
| `Identity::OfflinePlayground(app_id)` | `DittoConfig::default_config().set_database_id(uuid)` with `Connect::small_peers_only()` |
| `Identity::SharedKey(app_id, shared_key)` | `DittoConfig::default_config().set_database_id(uuid).set_small_peers_only_connect(private_key)` |
| `Identity::Manual(certificate_config)` | **No replacement** — removed in v5 |

### Remove These v4 Workarounds
```cpp
// DELETE ALL OF THESE — not needed in v5:
ditto->update_transport_config([](auto& config) {
    config.connect.websocket_urls.insert("wss://...");
});
ditto->disable_sync_with_v3();
ditto->get_store().execute("ALTER SYSTEM SET DQL_STRICT_MODE = false", {});
```

---

## 2. Sync API

```cpp
// v4.14
ditto->start_sync();                  // now private
ditto->stop_sync();                   // now private
bool active = ditto->get_is_sync_active();  // now private

// v5.0
ditto->get_sync().start();
ditto->get_sync().stop();
bool active = ditto->get_sync().is_active();
```

---

## 3. Lifetime Management — `close()` Removed

```cpp
// v4.14
ditto->close();  // explicit close

// v5.0 — NO close() method
// Use shared_ptr scope instead:
{
    auto ditto = Ditto::open(config);  // returns shared_ptr<Ditto>
    ditto->get_sync().start();
    // ... use ditto ...
}  // ditto destroyed when shared_ptr goes out of scope or is reset()
```

---

## 4. Logger — `Log` → `Logger`

```cpp
// v4.14
Log::set_minimum_log_level(LogLevel::Debug);
Log::Callback cb = my_log_fn;  // raw function pointer

// v5.0
Logger::set_minimum_log_level(LogLevel::Debug);
Logger::Callback cb = [](LogLevel level, const std::string& msg) {
    // std::function — can capture state
    std::cout << msg << std::endl;
};
Logger::set_custom_log_callback(cb);
```

**Removed from `Logger`** (no replacement):
- `get_emoji_log_level_headings_enabled()` / `set_emoji_log_level_headings_enabled(bool)`
- `set_log_file(path)` / `disable_log_file()` — use `Logger::export_to_file()` instead

---

## 5. Observer Handler Rename

```cpp
// v4.14
StoreObservationHandlerWithNextSignal handler = [](QueryResult result, NextSignal next) {
    // process result
    next();  // signal ready for next
};

// v5.0 — same signature, renamed types
StoreObservationHandlerWithSignalNext handler = [](QueryResult result, SignalNext next) {
    // process result
    next();  // same semantics
};
```

---

## 6. Store Observers — New Helper Types

v5 changes `store.observers` from `std::set` to `std::unordered_set` with helper types:

```cpp
// v4.14
std::set<std::shared_ptr<StoreObserver>> obs = store.observers;  // public field

// v5.0
std::unordered_set<
    std::shared_ptr<StoreObserver>,
    StoreObserverHash,
    StoreObserverEq
> obs = store.get_observers();  // method, not field
```

Similarly for sync subscriptions:
```cpp
// v4.14
std::set<std::shared_ptr<SyncSubscription>> subs = sync.subscriptions;

// v5.0
SyncSubscriptionSet subs = sync.get_subscriptions();  // unordered_set
```

---

## 7. Back Pressure (SignalNext)

Use the `StoreObservationHandlerWithSignalNext` overload to manually control when the next callback fires. The standard `StoreObservationHandler` overload auto-calls `signal_next` after your handler returns.

**Coalescing**: changes that occur while your handler is executing are coalesced — you get one callback with the latest state.

```cpp
// Standard (auto-signal)
auto obs = ditto->get_store().register_observer(
    "SELECT * FROM cars",
    nlohmann::json{},
    [](QueryResult result) {
        process_results(result);
    }
);

// Back-pressure (manual signal)
StoreObservationHandlerWithSignalNext handler = [](QueryResult result, SignalNext signal_next) {
    // Expensive processing...
    expensive_render(result);
    signal_next();  // Call when ready for the next update
};

auto obs = ditto->get_store().register_observer(
    "SELECT * FROM cars",
    nlohmann::json{},
    handler
);
```

Types:
- `SignalNext` = `std::function<void()>`
- `StoreObservationHandlerWithSignalNext` = `std::function<void(QueryResult, SignalNext)>`

---

## 9. DQL Strict Mode — CRITICAL BREAKING CHANGE

⚠️ **Silent data behavior change**: v5 defaults to `DQL_STRICT_MODE=false`. v4 default was `true`.

| Mode | Object behavior |
|------|----------------|
| `strict=true` (v4 default) | Objects treated as REGISTER (whole-object replacement) |
| `strict=false` (v5 default) | Objects auto-inferred as MAP (field-level merging) |

```cpp
// If maintaining v4 behavior, set BEFORE get_sync().start():
auto ditto = Ditto::open(config);
ditto->get_store().execute("ALTER SYSTEM SET DQL_STRICT_MODE = true", {});
ditto->get_sync().start();
```

---

## 10. DQL Migration — Legacy Collection API → DQL

For help with migrations to DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations - it's recommended to use the [DQL plugin](../ditto-dql).

All `Collection`, `PendingCursorOperation`, `PendingIDSpecificOperation`, `Document`, `MutableDocument` classes are **removed**.

### Query

```cpp
// v4.14
auto docs = ditto->get_store().collection("cars").find_all().exec();
auto doc = ditto->get_store().collection("cars").find_by_id(id).exec();
auto filtered = ditto->get_store().collection("cars").find("color == 'blue'").exec();

// v5.0
auto result = ditto->get_store().execute("SELECT * FROM cars", {});
auto result = ditto->get_store().execute(
    "SELECT * FROM cars WHERE _id = :id",
    {{"id", id}});
auto result = ditto->get_store().execute(
    "SELECT * FROM cars WHERE color = :color",
    {{"color", "blue"}});
```

### Insert

```cpp
// v4.14
ditto->get_store().collection("cars").upsert({{"_id", id}, {"color", "blue"}});

// v5.0
ditto->get_store().execute(
    "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    {{"doc", {{"_id", id}, {"color", "blue"}}}});
```

### Update

```cpp
// v4.14
ditto->get_store().collection("cars").find_by_id(id).update([](MutableDocument& doc) {
    doc["color"] = "green";
});

// v5.0
ditto->get_store().execute(
    "UPDATE cars SET color = :color WHERE _id = :id",
    {{"color", "green"}, {"id", id}});
```

### Delete

```cpp
// v4.14
ditto->get_store().collection("cars").find_by_id(id).remove();

// v5.0
ditto->get_store().execute(
    "DELETE FROM cars WHERE _id = :id",
    {{"id", id}});
```

### Evict

```cpp
// v4.14
ditto->get_store().collection("cars").find_by_id(id).evict();

// v5.0
ditto->get_store().execute(
    "EVICT FROM cars WHERE _id = :id",
    {{"id", id}});
```

### Observers

```cpp
// v4.14
auto obs = ditto->get_store().collection("cars")
    .find("color == 'blue'")
    .observe_local([](QueryResult result, LiveQueryEvent event) {
        for (auto& doc : result.items()) {
            // process doc
        }
    });

// v5.0
auto obs = ditto->get_store().register_observer(
    "SELECT * FROM cars WHERE color = :color",
    {{"color", "blue"}},
    [](QueryResult result) {
        for (auto& item : result.items()) {
            // process item
        }
    });
```

### With Signal Next (back-pressure)

```cpp
// v4.14
auto obs = store.collection("cars").find_all()
    .observe_local_with_next_signal([](QueryResult result, NextSignal next) {
        processAsync(result, [next]() { next(); });
    });

// v5.0 — renamed types
StoreObservationHandlerWithSignalNext handler = [](QueryResult result, SignalNext next) {
    processAsync(result, [next]() { next(); });
};
auto obs = ditto->get_store().register_observer(
    "SELECT * FROM cars",
    {},
    handler);
```

### Sync Subscriptions

```cpp
// v4.14
auto sub = ditto->get_store().collection("cars")
    .find("color == 'red'").subscribe();

// v5.0
auto sub = ditto->get_sync().register_subscription(
    "SELECT * FROM cars WHERE color = :color",
    {{"color", "red"}});
```

### Write Transactions

```cpp
// v4.14
ditto->get_store().write([](WriteTransaction& tx) {
    tx.scoped("cars").upsert({{"_id", id}, {"color", "blue"}});
});

// v5.0
ditto->get_store().execute_transaction([](Transaction& tx) {
    tx.execute("INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
               {{"doc", {{"_id", id}, {"color", "blue"}}}});
});
```

---

## 11. APIs Removed With No Replacement

- `Ditto::close()` — use `shared_ptr` lifetime
- `disable_sync_with_v3()` — v3 protocol fully dropped
- `Log::get_emoji_log_level_headings_enabled()` / `set_emoji_log_level_headings_enabled()`
- `Log::set_log_file(path)` / `disable_log_file()` — use `Logger::export_to_file()`
- `Identity::Manual(certificate_config)` — manual certificate identity
- `ditto_semver_version()` global — moved to `ditto::internal::ditto_semver_version()`


## 12. New APIs in v5

- **`Ditto::get_version()`** — replaces `get_sdk_version()`
- **`Logger` class** — replaces `Log`; callback type is now `std::function`
- **`Logger::export_to_file(path)`** — export accumulated logs to disk
- **`ditto->get_sync().start()` / `.stop()` / `.is_active()`** — sync lifecycle on `Sync` object
- **`StoreObservationHandlerWithSignalNext`** / **`SignalNext`** — renamed from `NextSignal` variants
- **`StoreObserverHash`** / **`StoreObserverEq`** — new hash/eq helpers for observer unordered_set
- **`SyncSubscriptionHash`** / **`SyncSubscriptionEq`** — new hash/eq helpers for subscription unordered_set
- **`SyncSubscriptionSet`** type alias — `unordered_set` of `SyncSubscription` shared_ptrs
- **`StoreObserver::get_query()`** / **`get_query_arguments()`** / **`get_query_arguments_cbor_data()`** — introspect registered observer
- **`SyncSubscription::get_query()`** / **`get_query_arguments()`** / **`get_query_arguments_cbor_data()`** — introspect registered subscription

---

## 13. Migration Checklist

### Initialization
- [ ] Replace `Ditto(identity, path)` constructor with `Ditto::open(DittoConfig)`
- [ ] Build `DittoConfig` with `default_config()` builder chain
- [ ] Remove `update_transport_config`, `disable_sync_with_v3()` calls
- [ ] Set `DQL_STRICT_MODE=true` BEFORE `get_sync().start()` if maintaining v4 behavior

### Sync
- [ ] Update `ditto->start_sync()` → `ditto->get_sync().start()`
- [ ] Update `ditto->stop_sync()` → `ditto->get_sync().stop()`
- [ ] Update `ditto->get_is_sync_active()` → `ditto->get_sync().is_active()`

### Logger
- [ ] Replace `Log::` calls with `Logger::`
- [ ] Update `Log::Callback` variable types from raw fn pointers to `std::function`
- [ ] Remove `set_log_file()` / `disable_log_file()` calls

### Observer Handlers
- [ ] Rename `StoreObservationHandlerWithNextSignal` → `StoreObservationHandlerWithSignalNext`
- [ ] Rename `NextSignal` → `SignalNext` in handler signatures

### Lifetime
- [ ] Remove `ditto->close()` calls
- [ ] Ensure `shared_ptr<Ditto>` scope matches desired lifetime

### Data Operations
- [ ] Replace all `collection("x").find(...)` chains with `get_store().execute()` DQL
- [ ] Replace `collection().upsert()` → `INSERT INTO ... ON ID CONFLICT DO UPDATE`
- [ ] Replace `find_by_id().update()` → `UPDATE SET`
- [ ] Replace `.remove()` → `DELETE FROM`
- [ ] Replace `.evict()` → `EVICT FROM`
- [ ] Replace `.observe_local()` → `register_observer()` with `StoreObservationHandlerWithSignalNext`
- [ ] Replace `.subscribe()` → `get_sync().register_subscription()`
- [ ] Replace `write()` → `execute_transaction()`

---

## Common Pitfalls

1. **`shared_ptr` lifetime**: `Ditto::open()` returns `shared_ptr<Ditto>`. If you store it in a local variable without a persistent owner, the instance will be destroyed immediately.

2. **`Log::Callback` type mismatch**: Old code may store callbacks in `void (*)(LogLevel, std::string)` typed variables. These won't compile — must use `std::function<void(LogLevel, const std::string&)>`.

3. **Handler rename**: `StoreObservationHandlerWithNextSignal` / `NextSignal` → `StoreObservationHandlerWithSignalNext` / `SignalNext`. Both renamed — update both the type and the alias.

4. **DQL_STRICT_MODE silent change**: Default flipped. Objects that were replaced whole in v4 will merge field-by-field in v5 unless strict mode is set.

5. **Using `store.observers` field**: Now a method `get_observers()` returning `unordered_set` with helper types — direct field access removed.

---

## Official Documentation

- C++ V4→V5 Guide: https://docs.ditto.live/sdk/latest/migration-guides/cpp-v4
- C++ DQL Migration: https://docs.ditto.live/sdk/latest/migration-guides/cpp-dql
- DQL Reference: https://docs.ditto.live/dql/dql
