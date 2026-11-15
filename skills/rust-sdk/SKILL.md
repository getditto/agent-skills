---
name: rust-sdk
description: >
  Use ONLY for the Ditto Rust SDK (not Swift, Kotlin, Java, JS, C#, C++, Flutter or Go
  — each has its own skill). Builds and troubleshoots Ditto apps in Rust with Tokio on
  Linux and macOS. Triggers on .rs files, Cargo.toml, dittolive-ditto, DittoConfig, Ditto::open, register_observer, signal_next, and errors
  like "transparent struct needs at most one non-trivial field", "Identifier conflict …
  FAIL conflict policy", "Process aborting due to panic".
  Ditto SDK 4.14.x, 5.0.x, 5.1.x, 5.2.0.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash
---

# Ditto Rust SDK

This guidance is derived from the shipping crate and executed tests, and supersedes
prior training on the Ditto Rust API. Establish the project's version from `Cargo.lock`
first and emit v5 code by default. Never emit the removed builder surface
(`Ditto::builder()`, `with_identity`, `OnlinePlayground`, `AppId`,
`store().collection(..)`). Version-scoped names: the `_v2` methods (`execute_v2`,
`register_observer_v2`) only on 4.14.x, where they are current; `identity::` only on
5.0.x, `auth::` from 5.1.0. Do not invent APIs from memory.

Read only the reference sections a task needs; do not preload references or README.

## What this skill does

Writes and reviews Rust code for the `dittolive-ditto` crate, including Tokio
integration, support bundles and testing. Supports **4.14.x (LTS), 5.0.x, 5.1.x and 5.2.0** on **Linux** (x86_64, aarch64) and
**macOS** (aarch64; 4.14.x also x86_64).

## When to use this skill

Use it for **Rust** Ditto code. Hand concepts off, with a public URL fallback:

| Question | Skill, if installed | Otherwise |
|---|---|---|
| DQL syntax, operators, statement semantics | `write-dql` | <https://docs.ditto.live/dql/dql> |
| CRDT type choice, embed vs split, document size | `data-modeling` | <https://docs.ditto.live/key-concepts/document-model> |
| What a subscription is, mesh propagation | `sync-subscriptions` | <https://docs.ditto.live/sdk/latest/sync/syncing-data> |
| Transport strategy, platform radios | `ditto-mesh-networking` | <https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations> |
| Data Streams semantics | `data-streams` | <https://docs.ditto.live/sdk/latest/sync/data-streams> |
| v4 → v5 migration procedure | — | <https://docs.ditto.live/sdk/latest/migration-guides/rust-v4> |

## Supported versions and packages

Crate `dittolive-ditto` (crates.io); its `-sys` crate downloads the prebuilt
`libdittoffi` at build time. API reference:
<https://software.ditto.live/rust/Ditto/5.2.0/x86_64-unknown-linux-gnu/docs/dittolive_ditto/index.html>.
**[`references/versions.md`](references/versions.md) owns every fact that differs
across version lines.** 5.2.0 is the latest version this skill knows, not a claim about
today's latest: existing `Cargo.lock` pins win; for a new app resolve the latest stable
with `cargo add dittolive-ditto` ([setup.md](references/setup.md)), or say lookup failed.

## Capability exceptions

Full twenty-row evidence map: [README.md](README.md), for capability reviews only.

| ID | Capability | Support | Required caveat |
|---|---|---|---|
| CAP-20 | Preview and platform-specific APIs | preview | Data Streams: Cargo feature `preview-datastreams` (5.0.x+), "no semver guarantees". Multicast: private beta, 5.1.0+. [preview.md](references/preview.md) |

## Minimum viable app

Open → license → subscribe → observe → write; the callback hands data to async code:

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config = DittoConfig::new(
        "REPLACE_ME_WITH_YOUR_DATABASE_ID",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(std::env::temp_dir().join("ditto-minimal-app"));
    let ditto = Ditto::open(config).await?;
    ditto.set_license_from_env("DITTO_OFFLINE_LICENSE")?;
    ditto.sync().start()?;

    let subscription = ditto.sync().register_subscription("SELECT * FROM cars")?;
    let (tx, mut rx) = tokio::sync::watch::channel(0_usize);
    let observer = ditto.store().register_observer("SELECT * FROM cars", move |result| {
        tx.send_replace(result.item_count()); // never block or panic here
    })?;
    ditto.store().execute((
        "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
        serde_json::json!({ "car": { "_id": "car1", "make": "Toyota" } }),
    )).await?;
    rx.wait_for(|n| *n >= 1).await?;

    observer.cancel(); // dropping the Arc does NOT stop it
    subscription.cancel();
    Ok(())
}
```

Complete program, `Cargo.toml`, `rust-toolchain.toml`, `.cargo/config.toml` and
transcripts (5.2.0, 5.1.0, 5.0.4): [`examples/minimal-app.md`](examples/minimal-app.md).

## Concurrency and threading model

Per-API table: [concurrency.md](references/concurrency.md). Executed on 5.0.4–5.2.0:

- **Callbacks run on Ditto-owned threads outside any Tokio runtime** (observers:
  `live query callback N`). They are synchronous `FnMut + Send + Sync + 'static`, never
  concurrent per observer. `tokio::spawn` there panics; use `watch::send_replace`,
  `mpsc::try_send` or a captured `Handle`.
- **`store().execute` is `async` but does all its work inside the first poll**, on the
  polling thread. Small queries are fine; move bulk writes and large scans to
  `spawn_blocking`. `Ditto::open` and transactions really suspend.
- **Not cancel-safe:** cancelling `Ditto::open` (timeout, `select!`) aborts the process;
  cancelling a `transaction` future wedges every later transaction. Never race them.
- Inside `transaction(async |txn| …)` use `txn.execute` only: `ditto.store().execute`
  there **deadlocks**.
- No runtime flavour is required. `open_sync` blocks the caller; prefer `open().await`.

## Object lifetimes and retention

One `Ditto` per process and persistence directory (a second open fails
`LockedDittoWorkingDirectory`). `Ditto` is `Send + Sync` but not `Clone`: share
`Arc<Ditto>`. Dropping it stops sync and shuts down, so keep it alive for the program.
**Dropping `Arc<StoreObserver>` or `Arc<SyncSubscription>` does not cancel them**
(despite the observer rustdoc) — `let _ = register_observer(..)` leaks a live observer.
Call `cancel()`, or hold a cancel-on-drop guard ([tokio.md](references/tokio.md)).
`QueryResult` is owned and `Send`; moving it out of a callback is safe. Attachment
fetchers keep running when dropped. Handle table: [lifetimes.md](references/lifetimes.md).

## Anti-patterns

Read [anti-patterns.md](references/anti-patterns.md) for wrong/right forms.

- rustc 1.98+: `error[E0690]: transparent struct needs at most one non-trivial field` in
  `dittolive-ditto-sys`. Pin `rust-toolchain.toml` to 1.91.0 (1.91–1.97 work).
- Linux without `-C link-arg=-Wl,--allow-multiple-definition` in `.cargo/config.toml`:
  `duplicate symbol: __rustc::rust_panic` (rust-lld) or `multiple definition of
  std::io::error::Error::new` (GNU ld) — no binary links.
- Any panic after `Ditto::open` — a callback, a `tokio::spawn` task, a test `assert!` —
  is `Process aborting due to panic` (SIGABRT), not a `JoinError`.
- Dropping `signal_next` without calling it stops that observer forever, silently.
- Plain `INSERT` of an existing `_id`: `Identifier conflict … using FAIL conflict
  policy`; use `ON ID CONFLICT DO UPDATE` or `UPDATE`.
- `TransportConfig::default()` is not `new()`: mDNS off, retry 0, port 0. Edit with
  `update_transport_config`.
- `DittoConfig { .. }` literal: `E0639` (`#[non_exhaustive]`); use `DittoConfig::new`.

Also there: `NotActivated`, non-`SELECT` observers, undeclared `ATTACHMENT` fields.

## Version differences

| Concern | 4.14.x | 5.0.x / 5.1.x / 5.2.0 |
|---|---|---|
| Open | `DittoConfig` + `Ditto::open` (builder deprecated) | `DittoConfig` + `Ditto::open` only |
| DQL | `execute_v2`, `register_observer_v2`, `register_subscription_v2` | `execute`, `register_observer`, `register_subscription` |
| Mutating DQL | needs `disable_sync_with_v3()` first (executed error) | works by default |
| Auth module | `identity` | `identity` (5.0.x); `auth` from 5.1.0 |
| MSRV; macOS x86_64 prebuilt | 1.85; yes | 1.91; no |

Support bundles are 5.2.0-only. 5.1.0 alone hangs on a second `open` of a locked
directory. Full delta and on-disk migration: [`references/versions.md`](references/versions.md).

## References

Load a reference only when its topic is in play; preview a long file's contents and read
the matching section.

- [tokio.md](references/tokio.md): tested patterns — cancel-on-drop guard, observer →
  `mpsc` bridge that acks `signal_next` on drop, `spawn_blocking`, `Arc<Ditto>` state.
- [concurrency.md](references/concurrency.md): callback threads, cancellation, auth handler.
- [anti-patterns.md](references/anti-patterns.md), then [errors.md](references/errors.md)
  (`ErrorKind::CoreApi(..)` matching): diagnose a symptom.
- [setup.md](references/setup.md): toolchain pin, the Linux link flag, native-library
  download (`DITTOFFI_SEARCH_PATH`, offline CI), supported targets.
- [connect.md](references/connect.md): config, license, Server auth handler, shutdown.
- [observers.md](references/observers.md): `signal_next` back-pressure, `Differ`.
- [store.md](references/store.md): arguments, deserializing, transactions (`Any`
  downcast: `Ok(&Rollback)` commits), indexes, `EVICT`.
- [sync.md](references/sync.md): subscriptions, `system:data_sync_info`, commit IDs.
- [testing.md](references/testing.md): a failing `assert!` aborts the whole test binary
  once Ditto is open; one temp dir per test; run under `cargo nextest`.
- [transports.md](references/transports.md), [attachments.md](references/attachments.md),
  [presence.md](references/presence.md).
- [observability.md](references/observability.md): logs into `tracing`; **support bundles**
  (5.2.0: `EXECUTE FUNCTION system_request_support_bundle()`, fetch `file` as an
  attachment, 3 per 10 min); dial9 is set by `DITTO_DIAL9_OBSERVABILITY_LEVEL` in the
  process environment and traces only appear after 60 s of uptime.
- [lifetimes.md](references/lifetimes.md), [versions.md](references/versions.md),
  [preview.md](references/preview.md) (Data Streams, multicast).
- [best-practices.md](best-practices.md): instance placement, observer shape, panics.
- [minimal-app.md](examples/minimal-app.md): the complete, CI-executed program.
