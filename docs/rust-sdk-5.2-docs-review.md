# Ditto Rust SDK 5.2.0 — documentation and packaging review

Findings from building the `rust-sdk` skill (DA-386). Scope: the published API reference
(<https://software.ditto.live/rust/Ditto/5.2.0/x86_64-unknown-linux-gnu/docs/dittolive_ditto/index.html>,
generated from the `dittolive-ditto` 5.2.0 crate's doc comments), the Rust pages on
<https://docs.ditto.live>, and the crate's build behaviour.

**Evidence levels.** *Executed* — reproduced by a test in `tests/rust-sdk/` (5.0.4, 5.1.0
and 5.2.0 on macOS arm64 unless stated; 5.2.0 also on Linux x86_64 and aarch64).
*Source* — read from the published crate or `github.com/getditto/ditto` at
`sdk-release-5.2.0`. *Docs* — read from the docs site on 2026-11-15. Paths like
`src/store/mod.rs:103` refer to the published `dittolive-ditto` 5.2.0 crate.

Severity: **high** leads to wrong code, a failed build or a crash; **medium** misleads or
omits something a Rust developer needs; **low** is cosmetic.

## Contents

- [Summary](#summary)
- [Build and packaging](#build-and-packaging)
- [API reference (rustdoc): high](#api-reference-rustdoc-high)
- [API reference (rustdoc): medium](#api-reference-rustdoc-medium)
- [API reference (rustdoc): low](#api-reference-rustdoc-low)
- [SDK behaviour worth a fix or a release note](#sdk-behaviour-worth-a-fix-or-a-release-note)
- [docs.ditto.live Rust pages](#docsdittolive-rust-pages)
- [Checked and correct](#checked-and-correct)

## Summary

| # | Finding | Severity | Evidence |
|---|---|---|---|
| B1 | No Rust binary links on Linux without `-Wl,--allow-multiple-definition` | high | executed |
| B2 | `dittolive-ditto-sys` fails to compile on rustc 1.98+ (E0690) | high | executed |
| B3 | Install guide says toolchain 1.81; compatibility page has a 5.0.x row only | high | docs |
| R1 | Rustdoc says dropping a `StoreObserver` cancels it; it does not | high | executed |
| R2 | `Ditto::open` and `transaction` futures are not cancel-safe; undocumented | high | executed |
| R3 | `Store::execute` is `async` but runs synchronously in the first poll; undocumented | high | executed |
| R4 | `TransportConfig::default()` differs from `new()`; `new()` documented as "default settings" | high | executed |
| R5 | Any panic after `Ditto::open` aborts the process; undocumented | high | executed |
| R6 | Attachment-token docs name a type/method combination that does not exist; `ATTACHMENT` declaration not documented | high | source |
| R7 | `open`/`open_sync` examples use a URL as the private key | medium | source |
| S1 | 5.1.0: a second `open` of a locked directory hangs | high | executed |
| S2 | 5.1.0: a JSON `null` system parameter makes `open` hang | medium | executed |
| D1 | rust-dql guide and 5.0 release notes show pre-v5 `execute`/`execute_v2` forms | high | docs |

## Build and packaging

**B1 — Linux linking fails by default (high, executed).** `libdittoffi.a` contains its
own compiled copy of Rust's `std`. On Linux every binary depending on `dittolive-ditto`
fails to link, debug and release, even with the library's own compiler (rustc 1.91.0):

- x86_64 (rust-lld, the default linker): `rust-lld: error: duplicate symbol: __rustc::rust_panic`,
  plus `std::process::abort`, `std::alloc::rust_oom` and others.
- aarch64 (GNU ld): 857 lines of `multiple definition of 'std::io::error::Error::new'`.
- `-fuse-ld=lld` does not help; `-C link-arg=-Wl,--allow-multiple-definition` does.
  Ditto's own CI uses that flag (`.github/workflows/dtp-artifacts-build.yml:528` at
  `sdk-release-5.2.0`). No public page mentions it.
- macOS links without it.

Fix: document the flag in the install guide (a `.cargo/config.toml` with
`[target.'cfg(target_os = "linux")'] rustflags = ["-C", "link-arg=-Wl,--allow-multiple-definition"]`),
or have `dittolive-ditto-sys`'s build script emit `cargo:rustc-link-arg` for Linux targets,
or stop bundling `std` in the static archive.

**B2 — rustc 1.98+ cannot compile `dittolive-ditto-sys` (high, executed).** 4.14.7, 5.0.4,
5.1.0 and 5.2.0 all fail on 1.98.0 and 1.99.1 with
`error[E0690]: transparent struct needs at most one non-trivial field, but has 2` at
`dittoffi.rs:396` (`FfiStoreObservationHandlerWithSignalNext`) and `:769` (`FfiCborData`).
1.91.0, 1.94.0, 1.96.0 and 1.97.0 build; 1.97 emits a future-incompatibility warning. A
developer on current stable sees this on their first `cargo build`. Fix the `#[repr(transparent)]`
structs in the sys crate; until then, document the working window and the need for a
`rust-toolchain.toml`.

**B3 — Toolchain guidance is inconsistent (high, docs).** `/sdk/latest/install-guides/rust`
tells users to put `1.81` in a `rust-toolchain` file next to `dittolive-ditto = "=5.2.0"`;
5.x declares `rust-version = "1.91"`, so that cannot build. `/sdk/latest/compatibility/rust`
has a single row (`"=5.0.x"` → `1.91.0`) and none for 5.1 or 5.2. The rust-v4 migration
prompt says `channel = "1.91"`. The compatibility page also says "you must use the exact
matching Rust toolchain version", which is stricter than reality (1.91–1.97 work) but
does not mention the 1.98 ceiling.

**B4 — Other build notes (low).** The build script's mismatch warning misspells "libarary".
The install guide's table of contents lists "Cross-Compiling with the Ditto SDK", but the
section is missing. `DITTOFFI_SEARCH_PATH`, `DITTO_LOCAL_BUILD` and `LIBDITTO_STATIC`
appear only in the crate README, not on any docs page.

## API reference (rustdoc): high

**R1 — Observer drop semantics are wrong (executed).** `Store::register_observer` and
`register_observer_with_signal_next` (`src/store/mod.rs:103-107`, `:176-180`) say the
observer remains active until "the `StoreObserver` handle gets dropped". It does not stop:
`let _ = store.register_observer(..)` keeps firing, and `store.observers()` still lists it.
`StoreObserver` has no `Drop` impl. The `Ditto::presence` example says "The observer is
cancelled when dropped" (`src/ditto/mod.rs:367`), and `PresenceObserver` has no `Drop`
impl either (source). `register_subscription` correctly says dropping does not cancel.
Fix the text, or add `Drop` impls (a behaviour change; the subscription docs would then
need the same).

**R2 — Cancelling `Ditto::open` or a transaction is unsafe (executed).** `make_continuation`
(`src/utils/mod.rs:42-50`) panics when the completion callback finds its receiver
dropped. Observed: `tokio::time::timeout(.., Ditto::open(config))` firing early leads to
SIGABRT when the open completes; a `Store::transaction` future dropped by `timeout` while
its closure awaits leaves every later transaction hanging. Nothing in the docs mentions
cancel safety, and dropped request futures (axum, tonic) trigger it in ordinary servers.
Fix: use `.send(..).ok()` as `DittoLogger::export_to_file` does, and roll back an
abandoned transaction; meanwhile add `# Cancel safety` sections.

**R3 — `Store::execute` blocks the polling thread (executed).** It is an `async fn` with no
await point around a synchronous FFI call (`src/store/mod.rs:280-294`); the future is
`Ready` on its first poll. `new_attachment` and `new_attachment_from_bytes` behave the same.
On a `current_thread` runtime, or for a large scan, this stalls other tasks. Document it,
and recommend `spawn_blocking` for heavy work.

**R4 — `TransportConfig::default()` is not `new()` (executed).** `new()` is documented as
"default settings" (`src/transport/transport_config.rs:50`), but `Default` is derived:
mDNS and multicast discovery off, `retry_interval` 0, TCP listen port 0 and an empty
interface. `#[serde(default)]` makes partially specified configs inherit those zeros.
Implement `Default` by hand to match `new()`, or document the difference.

**R5 — Panics abort the process once Ditto is open (executed).** Ditto installs a
process-wide panic hook that logs and calls `abort()`. After `Ditto::open`, a panic in a
`tokio::spawn` task is SIGABRT instead of a `JoinError`, and a failing `assert!` in a
test aborts the whole test binary. Before `open` the same panic unwinds normally; an app
hook installed after `open` restores unwinding, except for panics inside Ditto callbacks.
This is a significant departure from normal Rust semantics and appears nowhere in the
crate docs.

**R6 — Attachment token docs do not match the API (source).** `Store::fetch_attachment`
(`src/store/mod.rs:324-326`) says the token may be "the output of a
[`QueryResultItem::value()`] once casted [`.as_object()`]", but `value()` returns
`Arc<HashMap<Box<str>, CborValue>>`, which has no `.as_object()`. The working form is
`item.value().get("field")?.as_object()`. No rustdoc page says the field must be declared
`COLLECTION photos (image ATTACHMENT)` in DQL. Without the declaration nothing fails
(executed), which makes the omission hard to notice. Port the tested snippet in
`tests/attachment_doc_snippet.rs` into the module docs.

## API reference (rustdoc): medium

- **R7 — URL used as a private key.** The `Ditto::open`/`open_sync` examples
  (`src/ditto/init/mod.rs:45-47`, `:131-133`) pass
  `"https://example.com/your-server-url".bytes().collect()` as `private_key`. The key's
  format is not documented anywhere in the crate.
- **R8 — `Store::observers()` docs describe a lock that does not exist** (`src/store/mod.rs:210-215`).
  The function returns a snapshot; its return type exposes the `#[doc(hidden)]` `SetArc`
  with a public `hashbrown` field.
- **R9 — Callback threads are undocumented.** Executed: store observer callbacks run on
  Ditto threads named `live query callback N` with no Tokio context, so `tokio::spawn`
  inside them panics, which aborts the process. The expiration handler runs on a Ditto
  thread in a temporary runtime on 5.1.0+, but on an app runtime worker on 5.0.4. Only
  "never called concurrently" is documented.
- **R10 — Stateful expiration handlers.** An `async move` closure that captures state
  does not compile ("async closure does not implement `Fn`…", executed). The trait-impl
  form is the answer; the rustdoc lists it as option 3 with no hint that it is the only
  form that can hold a token client.
- **R11 — README quickstarts sync nothing.** Both quickstarts return from `main` right
  after `sync().start()`, so the `Ditto` is dropped and shut down immediately. The offline
  quickstart's visible `set_offline_only_license_token` call is wrapped in a hidden
  `if false`.
- **R12 — Default persistence directory is never stated.** It is
  `<executable's directory>/ditto-<database id>` (`src/ditto/init/mod.rs:226-230`); under
  `cargo run` that is inside `target/`, which `cargo clean` deletes.
- **R13 — Undocumented panics:** `set_transport_config` (core rejection),
  `(query, args)` argument serialisation (`serde_cbor::to_vec(..).unwrap()`,
  `src/dql/query.rs:93`, contradicting "This conversion may be fallible"),
  `new_attachment` with a non-UTF-8 path, `DittoAttachment::path()` after shutdown.
- **R14 — Error messages use stale names (executed).** `NotActivated` says "a successful
  call to `set_license_token`" (the method is `set_offline_only_license_token`).
  Server-mode `set_offline_only_license_token` returns `ErrorKind::Internal` naming v4
  identity types. A non-UUID database ID in Server mode fails with "Provided App ID was
  not a valid UUID".
- **R15 — Encryption helpers without encryption.** `DittoError::is_encryption_error()` and
  `encryption_error_kind()` are documented in detail, but the Rust SDK has no public way
  to configure encryption at rest. Say so.
- **R16 — Preview APIs are missing from the hosted docs.** `Ditto::datastreams()` and the
  `preview` module are behind `preview-datastreams` and do not appear on the published
  pages. Build docs with the feature and `doc(cfg)`.
- **R17 — Stale module text.** The `store` module still describes the removed "Query
  Builder" API (`src/store/mod.rs:3-5`). `QueryResult`'s note says "affected document IDs
  … will be provided in the near future" (`src/dql/query_result.rs:18-19`), but
  `mutated_document_ids()` and `commit_id()` exist.
- **R18 — FFI internals in the prelude:** `BoxedDitto`, `CLogLevel` and
  `StringPrimitiveFormat` are re-exported undocumented. The deprecated `identity` module
  and the consumer-less `DittoAuthenticationEventHandler` are also in the prelude.
  `#[macro_export]`ed tracing wrappers appear at the crate root.

## API reference (rustdoc): low

- `DittoSmallPeerInfoSyncScope`: a broken intra-doc link renders literally, and the
  variants are undocumented.
- `Global::sync_group` says "App ID"; `PeerToPeer` says "Configure Bluetooth and LAN"
  (omitting AWDL, Wi-Fi Aware and multicast).
- `DittoAttachmentFetcher` defaults its type parameter to the removed `FetcherVersion::V1`.
- `DocumentId::new` documents a panic but returns `Result`.
- `IntoQuery` claims support for "String types (`String`, `&str`, etc.)"; `Cow<str>`,
  `Box<str>` and `Arc<str>` are not implemented.
- `DittoError` has no `source()`, so `anyhow`/`eyre` chains lose the cause.
- Typos: "garbage a collection" (`src/ditto/mod.rs:465`), "given an option debugging
  `hint`" (`src/store/transactions/api.rs:50`).
- Every doctest depends on the private `__internal-testing` feature, so
  `cargo test --doc` fails for users.

## SDK behaviour worth a fix or a release note

- **S1 — 5.1.0 hangs on a second `open` of the same directory (high, executed).**
  5.0.4 and 5.2.0 fail with `LockedDittoWorkingDirectory` after about a second; 5.1.0
  never returns (watchdog at 20 s). Worth a known-issue note for 5.1.x.
- **S2 — 5.1.0 hangs on a JSON `null` system parameter (medium, executed).** 5.2.0
  rejects it up front with `InvalidInput`.
- **S3 — The duplicate-`_id` error kind changed (low, executed).** 5.0.4 reports
  `CoreApi(StoreDatabase)`; 5.1.0 and 5.2.0 report `CoreApi(DqlEvaluationError)`. Code that
  matched the kind breaks on upgrade. Worth a release-note line.
- **S4 — The expiration handler moved threads (low, executed).** On 5.0.4 it ran on a
  worker of the app's runtime; on 5.1.0+ it runs on a Ditto thread. Not documented.

## docs.ditto.live Rust pages

- **D1 — Pre-v5 API forms on v5 pages (high).** The rust-dql migration guide and its
  "AI Agent Prompt" use `execute(query, Some(HashMap))?` (two arguments, no `.await`),
  `result.items`, `observer.stop()` and a three-argument `register_observer`. None of
  these exist in 5.x. The 5.0.0 release notes say `Store::execute()` was *removed in
  favour of* `execute_v2()`, which is the reverse of what happened, and their samples use
  `execute_v2`.
- **D2 — Four incompatible v5 initialisation shapes.** The migration guide (`Ditto::open(..).await?`,
  `auth()` → `Option`, trait handler), the troubleshooting page (`open_sync`, closure
  handler), the transports page (`Ditto::open(config)?` without `.await`, callback-style
  `login`) and the cloud-auth page (a builder `DittoConfig::default().database_id()` and
  `ditto.start_sync()`). Only the first compiles against 5.2.0.
- **D3 — The rust-v4 prompt says the `auth` module "does not exist in v5"** and imports
  `identity::get_development_provider`. `auth` is public since 5.1.0, and `identity` is
  deprecated there.
- **D4 — `disable_sync_with_v3` is listed as "removed without replacement" in v5.** It
  exists and works in 5.0.x and 5.1.x, and is a hidden no-op in 5.2.0.
- **D5 — Platform claims conflict.** The Rust console quickstart claims Windows support;
  the compatibility page lists Linux x64/arm64 and macOS arm64 only (confirmed: no
  Windows or macOS x86_64 library is published for 5.x).
- **D6 — Broken or missing pages.** The quickstart links `/sdk/latest/release-notes/rust`
  (the page is `/sdk/latest/release-notes-hub/rust`). `/sdk/latest/api-reference/rust` has
  no body.
- **D7 — Code that does not compile.** On the CRUD pages: `Car` lacks
  `#[derive(Serialize)]` in an update sample, a missing `;` after `args` on
  observing-data-changes, and a missing comma and `;` in the attachments sample. The
  install guide fences TOML as `rust`.
- **D8 — Missing Rust coverage.** No Rust sample for device-storage management, data
  authorization or certificate-based security, and no Rust code on the support-bundles
  page (the Rust form is `item.value().get("file")?.as_object()` and then
  `fetch_attachment`; tested in this repository's `tests/rust-sdk`). The Rust tabs for
  retrieving and cancelling subscriptions hold only comments. No page mentions Tokio,
  callback threads, cancel safety, the panic hook or the Linux link flag.

## Checked and correct

- `SyncSubscription`'s "dropping won't cancel" docs match behaviour (executed).
- `DiskUsageObserverHandle` drop-to-stop matches the code.
- The README expiration-handler closure signature matches `DittoAuthExpirationHandler`.
- The support-bundles page matches behaviour: entries, rate limit (3 per 10 minutes, with
  the exact error text), and the 60-second dial9 segment rule (executed: no `dial9/`
  entry before 60 s, a 517 KB `dial9/dial9.bin.gz` after 75 s).
- All `ditto.com/link/*` redirects in the crate resolve.
