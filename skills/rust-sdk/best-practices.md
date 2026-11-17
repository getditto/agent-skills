# Best practices — Ditto Rust SDK

## Contents

- [Instance ownership](#instance-ownership)
- [Structuring async work](#structuring-async-work)
- [Observers](#observers)
- [Writes](#writes)
- [Panics](#panics)
- [Errors](#errors)
- [Operations](#operations)

Architectural judgement with no single right answer. The rules that change code by
default are in `SKILL.md` § *Anti-patterns*; this file is for design decisions.

## Instance ownership

- **One `Arc<Ditto>` per process**, created in `main` (or your service's start-up) and
  passed down as part of an application state struct. Do not hide it in a `static` or a
  `OnceLock` unless the program truly has no structured owner: tests then need a fresh
  instance per directory, which a global prevents.
- **Wrap Ditto in a domain service** (`OrdersRepo { store: Store }`) that exposes typed
  async methods and owns its observer/subscription guards. The rest of the program sees
  `Result<Vec<Order>, RepoError>`, not DQL strings or `QueryResult`s.
- **Configure from data.** `DittoConfig` is `Deserialize`; load database ID, connect mode
  and persistence directory from your config file, and the license or token from a
  secret store.
- **Make the persistence directory explicit and durable** (`/var/lib/<app>/ditto`, a
  Kubernetes `PersistentVolume`), never the default next to the binary.

## Structuring async work

- **Callbacks produce, tasks consume.** Every Ditto callback should be a few lines that
  push into a channel; the real work runs in a task you own and can cancel. This keeps
  Ditto's threads free and gives you structured shutdown.
- **Prefer `watch` for state, `mpsc` with an acked `signal_next` for streams of work**
  ([references/tokio.md](references/tokio.md)). Unbounded channels from an observer are
  acceptable only for low-rate data: each delivery is a full result set.
- **Tie lifetimes to owners.** Hold `Cancelling<StoreObserver>` and
  `Cancelling<SyncSubscription>` in the struct whose lifetime matches the need. A
  per-request subscription is almost always wrong; a per-feature or per-session one is
  usual.
- **Keep the runtime responsive.** Small `execute` calls on the async workers are fine;
  bulk imports, large scans and attachment creation from big files go to
  `spawn_blocking`.
- **Never put SDK futures inside `select!`/`timeout`** — not `open`, not `transaction`.
  Put the timeout around your own I/O instead.

## Observers

- **Few broad observers beat many narrow ones.** Each observer re-evaluates its query when
  matching documents change; hundreds of per-item observers multiply that work. Observe a
  collection slice and fan out in your own code.
- **Pair observers with subscriptions deliberately.** The subscription decides what
  arrives from peers; the observer decides what you react to. They usually share a query,
  but the subscription can be broader (prefetch) and the observer narrower (UI).
- **Decode in the callback, send owned values.** It bounds memory to what you use and
  surfaces schema drift at one place.
- **Use `Differ` only for list UIs.** For services, recompute from the full result: it is
  simpler and has no state to get wrong.

## Writes

- **Model with merges in mind.** Upserts with `ON ID CONFLICT DO UPDATE`, counters as PN
  counters (`APPLY … PN_INCREMENT`), and field-level `UPDATE … SET` rather than
  replacing whole documents. The `data-modeling` skill owns the reasoning
  (<https://docs.ditto.live/key-concepts/document-model>).
- **Use a transaction when several statements must commit together**, or when a decision
  reads then writes. Keep it short: it serialises every local writer.
- **Batch.** One `INSERT … DOCUMENTS (:a), (:b), …` or one transaction beats a loop of
  single-document `execute` calls, each of which is a synchronous FFI round trip.
- **Bind arguments, never `format!` DQL.**

## Panics

Once Ditto is open, every panic in the process aborts it
([references/concurrency.md](references/concurrency.md#panics-abort-the-process)). Two
defensible policies:

1. **Accept abort semantics (recommended).** Treat the binary as `panic = "abort"`: no
   `unwrap()` on runtime data, `Result` everywhere, a supervisor (systemd, Kubernetes)
   to restart the process. You keep Ditto's crash logging, and its `CRASH` support
   bundles.
2. **Restore unwinding for your own code** with `std::panic::set_hook` after
   `Ditto::open` — for example when a web framework's panic-catching middleware must keep
   serving. You lose Ditto's crash log, panics inside Ditto callbacks still abort, and
   you must log panics yourself in the hook. Decide this once, in `main`, and document it.

Either way, a panic inside a Ditto callback is a process abort: wrap any callback body
that calls fallible code in explicit error handling.

## Errors

- **Convert at the boundary.** Map `DittoError` into your domain error once, in the
  repository layer: `kind()` decides the variant, `to_string()` is kept for logs.
- **Fail fast on start-up errors** (open, license, config). They do not recover.
- **Do not string-match whole messages**; match `ErrorKind`/`CoreApiErrorKind` and, where
  needed, one stable fragment.

## Operations

- **Logs:** set `DittoLogger::set_minimum_log_level(LogLevel::Warning)` for services, and
  forward into `tracing` through the custom callback so Ditto lines carry your
  subscriber's format and sinks.
- **Support bundles (5.2.0+):** expose an admin-only way to generate one (CLI subcommand,
  authenticated endpoint) and document where the file lands. Leave dial9 at its default.
- **Health:** report `ditto.sync().is_active()`, the presence graph's peer count and the
  last observer delivery time; alert on a flat line, not on single misses.
- **Upgrades:** pin exact versions in `Cargo.toml` (`=5.2.0`), commit `Cargo.lock`, and
  move the toolchain pin and the Ditto version together after running your tests.
