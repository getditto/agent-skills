# Anti-patterns — Ditto Rust SDK

## Contents

- [Build](#build)
- [Panics](#panics)
- [Lifetimes](#lifetimes)
- [Async and Tokio](#async-and-tokio)
- [Store and DQL](#store-and-dql)
- [Configuration](#configuration)

Each entry: the symptom you will see, the wrong form, the right form. Executed on
5.0.4, 5.1.0 and 5.2.0 unless marked otherwise.

## Build

**rustc 1.98 or newer.**
Symptom (4.14.7, 5.0.4, 5.1.0 and 5.2.0 alike):
`error[E0690]: transparent struct needs at most one non-trivial field, but has 2` at
`dittoffi.rs:396` and `:769` in `dittolive-ditto-sys`. 1.97 warns "packages contain code
that will be rejected by a future version of Rust". Right: a `rust-toolchain.toml` with
`channel = "1.91.0"` (any of 1.91.0–1.97.x builds). Changing `safer-ffi` versions does
not help. Details: [setup.md](setup.md#the-toolchain-pin).

**Homebrew or distro `cargo` ahead of rustup on `PATH`.**
Symptom: the pin above is ignored and E0690 persists; the build log shows
`app_rustc_version: rustc 1.99.1 … (Homebrew)`. Right: put `~/.cargo/bin` first, or run
`rustup run 1.91.0 cargo build`.

**Building for a target with no prebuilt library** (Windows, iOS, Android, musl, and
`x86_64-apple-darwin` on 5.x). Symptom: `Failed to download Ditto SDK binary component`
during the `dittolive-ditto-sys` build script. Right: build on a supported target
([setup.md](setup.md#supported-targets)), or supply your own `libdittoffi` with
`DITTOFFI_SEARCH_PATH`.

## Panics

**Panicking anywhere after `Ditto::open`.** Symptom: `ERROR tracing_config: Panic: …`,
then `Process aborting due to panic`, exit by SIGABRT. This includes `unwrap()` in a
`tokio::spawn` task that you expected to surface as `JoinError`, and a failing `assert!`
in a `#[tokio::test]`. Right: return `Result`s; see
[concurrency.md](concurrency.md#panics-abort-the-process) and
[testing.md](testing.md#a-failing-assertion-aborts-the-binary).

**Panicking inside a callback.** Always aborts, even with your own panic hook. Wrong:

```rust
store.register_observer(q, |r| {
    let car: Car = r.get_item(0).unwrap().deserialize_value().unwrap(); // abort on empty result
})?;
```

Right: handle `None`/`Err` (`let Some(item) = r.get_item(0) else { return };`).

## Lifetimes

**Relying on drop to cancel an observer or subscription.** Symptom: callbacks keep
arriving after the owner was dropped; `subscriptions().len()` grows. Wrong:
`let _ = store.register_observer(..)?;` or letting the `Arc` fall out of scope. Right:
`observer.cancel()` at teardown, or `Cancelling::new(observer)`
([tokio.md](tokio.md#cancel-on-drop-guard)).

**Dropping `signal_next` without calling it.** Symptom: one delivery, then silence; no
error or log. Wrong: an early `return` before `signal_next()` in a
`register_observer_with_signal_next` callback. Right: wrap it in a type that calls it in
`Drop` ([tokio.md](tokio.md#observer-to-async-consumer-with-back-pressure)).

**Returning from `main` right after `sync().start()`.** Symptom: nothing syncs; the
process exits. Right: keep the `Ditto` alive until a shutdown signal.

## Async and Tokio

**`tokio::spawn` (or `Handle::current()`) inside a callback.** Symptom: panic "there is
no reactor running, must be called from the context of a Tokio 1.x runtime", which
aborts the process. Right: send on a channel, or capture
`tokio::runtime::Handle::current()` before registering and call `handle.spawn(..)`.

**Wrapping `Ditto::open` in `timeout`/`select!`.** Symptom: SIGABRT when the open later
completes. Right: await it unconditionally at start-up.

**Wrapping a `transaction` in `timeout`/`select!`** (including a request handler whose
future is dropped on disconnect). Symptom: every later transaction hangs. Right: bound
the work inside the closure; run request-scoped transactions in `tokio::spawn`.

**`ditto.store().execute` inside a transaction closure.** Symptom: the task hangs
forever. Wrong:

```rust
store.transaction(async |_txn| {
    store.execute(("UPDATE cars SET sold = true WHERE _id = :id", args)).await?; // deadlock
    Ok::<_, DittoError>(TransactionCompletionAction::Commit)
}).await?;
```

Right: `txn.execute(..)`.

**Large `execute` on a latency-sensitive runtime.** Symptom: timers and other tasks on
that worker stall for the query's duration (`execute` completes inside its first poll).
Right: `spawn_blocking` ([tokio.md](tokio.md#heavy-queries-off-the-async-workers)).

**`blocking_send`, `std::thread::sleep` or a contended `Mutex` in a callback.** Symptom:
that observer's deliveries lag, and a Ditto thread is held. Right: `try_send`,
`send_replace`, or an unbounded channel.

## Store and DQL

**Plain `INSERT` of an existing `_id`.** Symptom:
`DqlEvaluationError: … Identifier conflict on document "dup": using FAIL conflict
policy` (5.0.x reports it as `StoreDatabase`). Right: `INSERT … ON ID CONFLICT DO UPDATE`, or `UPDATE`. Which one merges
correctly is a data-modeling question (`data-modeling` skill).

**Non-`SELECT` observer.** Symptom: `register_observer` returns
`DqlUnsupported: <dql> Unsupported feature: non-SELECT statement in store observer`.

**Attachment field not declared.** Symptom: no error — the token is stored as an
ordinary map field, which the documentation says is not an attachment reference
(executed: the insert and a local `fetch_attachment` both succeed, so nothing warns you;
peer behaviour not verified). Right:
`INSERT INTO COLLECTION files (blob ATTACHMENT) DOCUMENTS (:doc)` and the same
`COLLECTION … (blob ATTACHMENT)` clause on `SELECT` ([attachments.md](attachments.md)).
Omitting `COLLECTION` is `DqlQueryCompilation`.

**`Ok(&TransactionCompletionAction::Rollback)`.** Symptom: the transaction commits. The
SDK downcasts `T` through `Any`; only an owned `TransactionCompletionAction` is
recognised (source: `src/store/transactions/impls.rs`). Return the value, not a reference.

**Argument types that do not serialize.** `(query, args)` encodes `args` with
`serde_cbor::to_vec(..).unwrap()` (`src/dql/query.rs`): a `Serialize` impl that errors
panics — and that panic aborts. Use plain data (`json!`, derived structs).

## Configuration

**`sync().start()` before a license.** Symptom: `ErrorKind::NotActivated`, "Sync could
not be started because Ditto has not yet been activated. This can be achieved with a
successful call to `set_license_token`." The method is `set_offline_only_license_token`
(or `set_license_from_env`); small-peers-only mode only.

**Struct-literal `DittoConfig { .. }`.** Symptom: `error[E0639]: cannot create
non-exhaustive struct using struct expression`. Right: `DittoConfig::new(..)`, then
`.with_persistence_directory(..)` or field assignment.

**`TransportConfig::default()` as a starting point.** Symptom: LAN enabled but no peers
found (mDNS and multicast discovery off), zero retry interval, listeners on port 0.
`Default` is derived and differs from `TransportConfig::new()`. Right:
`ditto.update_transport_config(|config| { … })`, which starts from the live config.

**Server mode with a non-UUID database ID.** Symptom: `Ditto::open` fails
`ValidationInvalidDittoConfig: Invalid DittoConfig: Provided App ID was not a valid
UUID`. Use the database ID from the Ditto portal. Small-peers-only mode accepts any
string.

**`SmallPeersOnly { private_key: None }` in production.** Sync traffic is unencrypted.
Provide a key ([connect.md](connect.md#small-peers-only-mode)).
