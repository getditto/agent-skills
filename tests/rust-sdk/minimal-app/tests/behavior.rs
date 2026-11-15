//! Executed evidence for the rust-sdk skill's concurrency, lifetime and error claims.
//!
//! Each test asserts the behaviour the skill documents, so an SDK release that changes
//! it fails CI instead of silently invalidating the skill. Requires DITTO_OFFLINE_LICENSE.

use std::{
    path::Path,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
    time::Duration,
};

use dittolive_ditto::{
    dql::QueryResult,
    error::{CoreApiErrorKind, ErrorKind},
    prelude::*,
    store::StoreObserver,
};
use serde_json::json;
use tokio::sync::{mpsc, watch};

fn license() -> String {
    std::env::var("DITTO_OFFLINE_LICENSE").expect("set DITTO_OFFLINE_LICENSE")
}

fn config(dir: &Path) -> DittoConfig {
    DittoConfig::new(
        "rust-skill-tests",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(dir)
}

async fn open(dir: &Path) -> Ditto {
    let ditto = Ditto::open(config(dir)).await.expect("open");
    ditto
        .set_offline_only_license_token(&license())
        .expect("license");
    ditto
}

async fn insert(ditto: &Ditto, id: &str) {
    ditto
        .store()
        .execute((
            "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
            json!({ "car": { "_id": id, "make": "Toyota" } }),
        ))
        .await
        .expect("insert");
}

fn assert_send_sync<T: Send + Sync>() {}
fn assert_send<T: Send>() {}

#[test]
fn handles_and_results_are_thread_safe() {
    assert_send_sync::<Ditto>();
    assert_send_sync::<Store>();
    assert_send_sync::<StoreObserver>();
    assert_send_sync::<dittolive_ditto::sync::SyncSubscription>();
    assert_send_sync::<DittoError>();
    assert_send::<QueryResult>();
}

/// The observer handler is called on a Ditto-owned thread with no Tokio runtime context.
#[tokio::test(flavor = "multi_thread")]
async fn observer_handler_runs_outside_the_tokio_runtime() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let (tx, mut rx) = mpsc::unbounded_channel();
    let _observer = ditto
        .store()
        .register_observer("SELECT * FROM cars", move |_result| {
            let in_runtime = tokio::runtime::Handle::try_current().is_ok();
            let name = std::thread::current().name().map(str::to_owned);
            let _ = tx.send((in_runtime, name));
        })
        .unwrap();
    let (in_runtime, name) = tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .unwrap()
        .unwrap();
    println!("observer thread name: {name:?}, inside tokio runtime: {in_runtime}");
    assert!(
        !in_runtime,
        "handler unexpectedly ran inside a Tokio runtime"
    );
}

/// The first callback arrives without any write, carrying the current (here empty) result.
#[tokio::test]
async fn observer_delivers_an_initial_result() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let (tx, mut rx) = watch::channel(None);
    let _observer = ditto
        .store()
        .register_observer("SELECT * FROM cars", move |result| {
            tx.send_replace(Some(result.item_count()));
        })
        .unwrap();
    rx.wait_for(Option::is_some).await.unwrap();
    assert_eq!(*rx.borrow(), Some(0));
}

/// Dropping the last `Arc<StoreObserver>` does NOT stop delivery (5.0.4-5.2.0, executed):
/// the observer stays registered and keeps firing until `cancel()` or Ditto shutdown.
#[tokio::test]
async fn dropping_the_observer_handle_does_not_cancel_it() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let calls = Arc::new(AtomicUsize::new(0));
    {
        let calls = calls.clone();
        // `let _ =` drops the returned Arc at the end of the statement.
        let _ = ditto
            .store()
            .register_observer("SELECT * FROM cars", move |_| {
                calls.fetch_add(1, Ordering::SeqCst);
            })
            .unwrap();
    }
    insert(&ditto, "after-drop").await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    let registered = ditto.store().observers().keys.len();
    println!(
        "after drop: callbacks={} registered={registered}",
        calls.load(Ordering::SeqCst)
    );
    assert_eq!(
        calls.load(Ordering::SeqCst),
        2,
        "initial + insert, despite the drop"
    );
    assert_eq!(registered, 1);
}

/// `cancel()` is what stops an observer.
#[tokio::test]
async fn cancel_stops_the_observer() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let calls = Arc::new(AtomicUsize::new(0));
    let observer = {
        let calls = calls.clone();
        ditto
            .store()
            .register_observer("SELECT * FROM cars", move |_| {
                calls.fetch_add(1, Ordering::SeqCst);
            })
            .unwrap()
    };
    tokio::time::sleep(Duration::from_millis(300)).await;
    observer.cancel();
    insert(&ditto, "after-cancel").await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(observer.is_cancelled());
    assert_eq!(ditto.store().observers().keys.len(), 0);
}

/// Listing observers returns a snapshot; dropping it does not cancel the live observer.
#[tokio::test]
async fn listing_observers_does_not_cancel_them() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let calls = Arc::new(AtomicUsize::new(0));
    let observer = {
        let calls = calls.clone();
        ditto
            .store()
            .register_observer("SELECT * FROM cars", move |_| {
                calls.fetch_add(1, Ordering::SeqCst);
            })
            .unwrap()
    };
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(ditto.store().observers().keys.len(), 1);
    insert(&ditto, "car1").await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    assert!(!observer.is_cancelled());
}

/// Dropping the last `Arc<SyncSubscription>` does NOT cancel it; `cancel()` does.
#[tokio::test]
async fn dropping_the_subscription_handle_does_not_cancel_it() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    drop(
        ditto
            .sync()
            .register_subscription("SELECT * FROM cars")
            .unwrap(),
    );
    let after_drop = ditto.sync().subscriptions().len();
    println!("subscriptions after drop: {after_drop}");
    assert_eq!(after_drop, 1);
    let subscription = ditto
        .sync()
        .register_subscription("SELECT * FROM boats")
        .unwrap();
    subscription.cancel();
    assert!(subscription.is_cancelled());
    assert_eq!(
        ditto.sync().subscriptions().len(),
        1,
        "only the dropped one remains"
    );
}

/// With signal_next held, changes coalesce; one callback with the latest result follows.
#[tokio::test(flavor = "multi_thread")]
async fn signal_next_coalesces_pending_changes() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let (tx, mut rx) = mpsc::unbounded_channel::<(usize, Box<dyn FnOnce() + Send>)>();
    let _observer = ditto
        .store()
        .register_observer_with_signal_next("SELECT * FROM cars", move |result, signal_next| {
            let _ = tx.send((result.item_count(), signal_next));
        })
        .unwrap();
    let (initial, signal_next) = rx.recv().await.unwrap();
    assert_eq!(initial, 0);
    for i in 0..20 {
        insert(&ditto, &format!("car{i}")).await;
    }
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert!(
        rx.try_recv().is_err(),
        "no callback while signal_next is held"
    );
    signal_next();
    let (latest, _signal) = tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .unwrap()
        .unwrap();
    println!("first callback after signal_next saw {latest} items");
    assert_eq!(latest, 20);
}

/// A plain INSERT of an existing `_id` fails; the message names the conflict policy.
#[tokio::test]
async fn plain_insert_of_existing_id_fails() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let query = (
        "INSERT INTO cars DOCUMENTS (:car)",
        json!({ "car": { "_id": "dup" } }),
    );
    ditto.store().execute(query.clone()).await.unwrap();
    let error = ditto
        .store()
        .execute(query)
        .await
        .err()
        .expect("duplicate must fail");
    println!("duplicate insert: kind={:?} display={error}", error.kind());
    assert!(error.to_string().contains("conflict"), "{error}");
}

/// Observers accept only SELECT.
#[tokio::test]
async fn observer_rejects_non_select() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let error = ditto
        .store()
        .register_observer("DELETE FROM cars", |_| {})
        .err()
        .expect("non-SELECT observer must fail");
    println!(
        "non-SELECT observer: kind={:?} display={error}",
        error.kind()
    );
}

/// sync().start() before a license is set fails with NotActivated.
#[tokio::test]
async fn sync_start_without_license_fails() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = Ditto::open(config(dir.path())).await.unwrap();
    let error = ditto.sync().start().unwrap_err();
    println!(
        "start without license: kind={:?} display={error}",
        error.kind()
    );
    assert_eq!(error.kind(), ErrorKind::NotActivated);
}

/// `open_sync` and `execute` work from inside a current-thread runtime (no nested block_on panic).
#[tokio::test(flavor = "current_thread")]
async fn sdk_calls_work_on_a_current_thread_runtime() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = Ditto::open_sync(config(dir.path())).unwrap();
    ditto.set_offline_only_license_token(&license()).unwrap();
    insert(&ditto, "car1").await;
    let result = ditto.store().execute("SELECT * FROM cars").await.unwrap();
    assert_eq!(result.item_count(), 1);
}

/// Returning Rollback (or an Err) leaves the store unchanged; Commit persists.
#[tokio::test]
async fn transaction_rollback_and_error_discard_writes() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let store = ditto.store();

    let action = store
        .transaction(async |txn| {
            txn.execute((
                "INSERT INTO cars DOCUMENTS (:c)",
                json!({ "c": { "_id": "rb" } }),
            ))
            .await?;
            Ok::<_, DittoError>(TransactionCompletionAction::Rollback)
        })
        .await
        .unwrap();
    println!("rollback returned: {action:?}");

    let failed: Result<(), anyhow::Error> = store
        .transaction(async |txn| {
            txn.execute((
                "INSERT INTO cars DOCUMENTS (:c)",
                json!({ "c": { "_id": "err" } }),
            ))
            .await?;
            anyhow::bail!("abort")
        })
        .await;
    assert!(failed.is_err());

    let _committed = store
        .transaction(async |txn| {
            txn.execute((
                "INSERT INTO cars DOCUMENTS (:c)",
                json!({ "c": { "_id": "ok" } }),
            ))
            .await?;
            Ok::<_, DittoError>(TransactionCompletionAction::Commit)
        })
        .await
        .unwrap();

    let ids: Vec<String> = store
        .execute("SELECT * FROM cars ORDER BY _id")
        .await
        .unwrap()
        .iter()
        .map(|item| item.deserialize_value::<serde_json::Value>().unwrap()["_id"].to_string())
        .collect();
    assert_eq!(ids, vec!["\"ok\"".to_string()]);
}

/// Integers written from Rust come back as JSON integers, not floats.
#[tokio::test]
async fn integers_round_trip_as_integers() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    ditto
        .store()
        .execute((
            "INSERT INTO n DOCUMENTS (:d)",
            json!({ "d": { "_id": "a", "count": 3 } }),
        ))
        .await
        .unwrap();
    let result = ditto.store().execute("SELECT * FROM n").await.unwrap();
    let item = result.get_item(0).unwrap();
    println!("json_string: {}", item.json_string());
    let value: serde_json::Value = item.deserialize_value().unwrap();
    assert!(value["count"].is_u64(), "{value}");
}

/// Indexes and EVICT are plain DQL through `execute`.
#[tokio::test]
async fn index_and_evict_are_dql() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    insert(&ditto, "car1").await;
    let store = ditto.store();
    store
        .execute("CREATE INDEX IF NOT EXISTS make_idx ON cars (make)")
        .await
        .unwrap();
    let evicted = store
        .execute(("EVICT FROM cars WHERE _id = :id", json!({ "id": "car1" })))
        .await
        .unwrap();
    assert_eq!(evicted.mutated_document_ids().len(), 1);
    let left = store
        .execute("SELECT * FROM cars")
        .await
        .unwrap()
        .item_count();
    assert_eq!(left, 0);
}

/// Sync status is observable through the `system:data_sync_info` virtual collection.
#[tokio::test]
async fn data_sync_info_is_queryable() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    ditto.sync().start().unwrap();
    let result = ditto
        .store()
        .execute("SELECT * FROM system:data_sync_info")
        .await
        .unwrap();
    println!(
        "system:data_sync_info rows (no peers): {}",
        result.item_count()
    );
    let _observer = ditto
        .store()
        .register_observer("SELECT * FROM system:data_sync_info", |_| {})
        .unwrap();
    ditto.sync().stop();
}

/// Diagnostics: log callback, disk usage, local presence graph.
#[tokio::test]
async fn diagnostics_apis() {
    let lines = Arc::new(AtomicUsize::new(0));
    {
        let lines = lines.clone();
        DittoLogger::set_custom_log_callback(move |_level, _message| {
            lines.fetch_add(1, Ordering::Relaxed);
        });
    }
    DittoLogger::set_minimum_log_level(LogLevel::Info);
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    ditto.sync().start().unwrap();
    insert(&ditto, "car1").await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    let usage = ditto.disk_usage().item();
    let graph = ditto.presence().graph();
    println!(
        "log lines via callback: {}; disk usage bytes: {}; local peer key set: {}",
        lines.load(Ordering::Relaxed),
        usage.size_in_bytes,
        !graph.local_peer.peer_key.is_empty()
    );
    assert!(lines.load(Ordering::Relaxed) > 0);
    assert!(usage.size_in_bytes > 0);
    DittoLogger::clear_custom_log_callback();
    ditto.sync().stop();
}

/// The error kinds and messages the skill's errors.md table quotes.
#[tokio::test]
async fn error_kinds_and_messages() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;

    let syntax = ditto
        .store()
        .execute("SELEC * FROM cars")
        .await
        .err()
        .unwrap();
    println!("syntax: {:?} | {syntax}", syntax.kind());
    assert_eq!(
        syntax.kind(),
        ErrorKind::CoreApi(CoreApiErrorKind::DqlQueryCompilation)
    );

    let mut options = CreateTransactionOptions::new();
    options.is_read_only = true;
    let read_only = ditto
        .store()
        .transaction_with_options(options, async |txn| {
            txn.execute((
                "INSERT INTO cars DOCUMENTS (:c)",
                json!({ "c": { "_id": "r" } }),
            ))
            .await?;
            Ok::<_, DittoError>(())
        })
        .await
        .err()
        .unwrap();
    println!("read-only: {:?} | {read_only}", read_only.kind());
    assert_eq!(
        read_only.kind(),
        ErrorKind::CoreApi(CoreApiErrorKind::StoreTransactionReadOnly)
    );

    let other = tempfile::tempdir().unwrap();
    let unlicensed = Ditto::open(config(other.path())).await.unwrap();
    let bad = unlicensed
        .set_offline_only_license_token("not-a-license")
        .err()
        .unwrap();
    println!("bad license: {:?} | {bad}", bad.kind());
    assert_eq!(bad.kind(), ErrorKind::License);

    if !Ditto::version().starts_with("5.2.") {
        // Before 5.2.0 there is no up-front validation: a JSON null system parameter
        // makes `open` hang (executed on 5.1.0), so it is not exercised there.
        return;
    }
    let third = tempfile::tempdir().unwrap();
    let mut null_param = config(third.path());
    null_param
        .system_parameters
        .insert("anything".into(), serde_json::Value::Null);
    let invalid = Ditto::open(null_param).await.err().unwrap();
    println!("null parameter: {:?} | {invalid}", invalid.kind());
    assert_eq!(invalid.kind(), ErrorKind::InvalidInput);
}

/// A second instance on a directory that is already open: 5.0.4 and 5.2.0 fail with
/// LockedDittoWorkingDirectory; 5.1.0 hangs in `open` (executed). Runs in a
/// child with a watchdog so a hang cannot stall the suite.
#[test]
fn second_open_on_one_directory() {
    const LOCKED: i32 = 20;
    const OTHER_ERROR: i32 = 21;
    const OPENED: i32 = 22;
    const HUNG: i32 = 23;
    let name = "second_open_on_one_directory";
    if is_child(name) {
        std::thread::spawn(|| {
            std::thread::sleep(Duration::from_secs(20));
            std::process::exit(HUNG);
        });
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let _first = open(dir.path()).await;
            let code = match Ditto::open(config(dir.path())).await {
                Err(e)
                    if e.kind()
                        == ErrorKind::CoreApi(CoreApiErrorKind::LockedDittoWorkingDirectory) =>
                {
                    LOCKED
                }
                Err(_) => OTHER_ERROR,
                Ok(_) => OPENED,
            };
            std::process::exit(code);
        });
    }
    let status = run_child(name);
    println!("second open on {}: {status:?}", Ditto::version());
    let expected = if Ditto::version().starts_with("5.1.") {
        HUNG
    } else {
        LOCKED
    };
    assert_eq!(status.code(), Some(expected), "{status:?}");
}

// Panic probes run in a child process: their failure mode is SIGABRT. The child reports a
// normal outcome through its exit code (stdout from a child test binary is not reliable).
const SURVIVED_WITH_JOIN_ERROR: i32 = 10;

fn run_child(name: &str) -> std::process::ExitStatus {
    std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", name, "--nocapture", "--test-threads=1"])
        .env("RUST_SKILL_CHILD", name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .unwrap()
}

fn is_child(name: &str) -> bool {
    std::env::var("RUST_SKILL_CHILD").as_deref() == Ok(name)
}

#[cfg(unix)]
fn aborted(status: std::process::ExitStatus) -> bool {
    use std::os::unix::process::ExitStatusExt as _;
    status.signal() == Some(6)
}

/// Panics in a spawned task, then exits with SURVIVED_WITH_JOIN_ERROR if it unwound normally.
async fn panic_in_a_task() -> ! {
    let joined = tokio::spawn(async { panic!("task panic") }).await;
    assert!(joined.unwrap_err().is_panic());
    std::process::exit(SURVIVED_WITH_JOIN_ERROR);
}

/// A panic inside an observer handler aborts the process.
#[test]
fn panic_in_observer_handler_aborts() {
    let name = "panic_in_observer_handler_aborts";
    if is_child(name) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let ditto = open(dir.path()).await;
            let _observer = ditto
                .store()
                .register_observer("SELECT * FROM cars", |_| panic!("boom"))
                .unwrap();
            tokio::time::sleep(Duration::from_secs(2)).await;
            std::process::exit(0);
        });
    }
    let status = run_child(name);
    println!("panic in observer handler: {status:?}");
    assert!(aborted(status), "expected SIGABRT, got {status:?}");
}

/// After Ditto::open, a panic in a tokio::spawn task aborts the process instead of
/// surfacing as a JoinError: Ditto installs a process-wide aborting panic hook.
#[test]
fn panic_in_spawned_task_after_open_aborts() {
    let name = "panic_in_spawned_task_after_open_aborts";
    if is_child(name) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let _ditto = open(dir.path()).await;
            panic_in_a_task().await
        });
    }
    let status = run_child(name);
    println!("task panic after open: {status:?}");
    assert!(aborted(status), "expected SIGABRT, got {status:?}");
}

/// Before any Ditto instance exists, the same panic is an ordinary JoinError.
#[test]
fn panic_in_spawned_task_before_open_unwinds() {
    let name = "panic_in_spawned_task_before_open_unwinds";
    if is_child(name) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(panic_in_a_task());
    }
    let status = run_child(name);
    assert_eq!(status.code(), Some(SURVIVED_WITH_JOIN_ERROR), "{status:?}");
}

/// An app hook installed after Ditto::open replaces Ditto's: task panics unwind again.
#[test]
fn panic_in_spawned_task_after_app_hook_unwinds() {
    let name = "panic_in_spawned_task_after_app_hook_unwinds";
    if is_child(name) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let _ditto = open(dir.path()).await;
            std::panic::set_hook(Box::new(|info| eprintln!("app hook: {info}")));
            panic_in_a_task().await
        });
    }
    let status = run_child(name);
    assert_eq!(status.code(), Some(SURVIVED_WITH_JOIN_ERROR), "{status:?}");
}

/// `tokio::spawn` inside an observer handler panics (no runtime on Ditto's thread), and the
/// panic aborts the process.
#[test]
fn tokio_spawn_in_observer_handler_aborts() {
    let name = "tokio_spawn_in_observer_handler_aborts";
    if is_child(name) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let ditto = open(dir.path()).await;
            let _observer = ditto
                .store()
                .register_observer("SELECT * FROM cars", |_| {
                    tokio::spawn(async {});
                })
                .unwrap();
            tokio::time::sleep(Duration::from_secs(2)).await;
            std::process::exit(0);
        });
    }
    let status = run_child(name);
    assert!(aborted(status), "expected SIGABRT, got {status:?}");
}

/// A `Handle` captured before registering works from the handler.
#[tokio::test(flavor = "multi_thread")]
async fn captured_handle_spawns_from_observer_handler() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let handle = tokio::runtime::Handle::current();
    let (tx, mut rx) = mpsc::unbounded_channel();
    let _observer = ditto
        .store()
        .register_observer("SELECT * FROM cars", move |result| {
            let tx = tx.clone();
            let count = result.item_count();
            handle.spawn(async move {
                let _ = tx.send(count);
            });
        })
        .unwrap();
    let count = tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .unwrap();
    assert_eq!(count, Some(0));
}

/// With an app panic hook installed after open, a panic inside a Ditto callback still
/// aborts: it cannot unwind across the FFI boundary.
#[test]
fn panic_in_observer_handler_aborts_even_with_app_hook() {
    let name = "panic_in_observer_handler_aborts_even_with_app_hook";
    if is_child(name) {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let ditto = open(dir.path()).await;
            std::panic::set_hook(Box::new(|_| {}));
            let _observer = ditto
                .store()
                .register_observer("SELECT * FROM cars", |_| panic!("boom"))
                .unwrap();
            tokio::time::sleep(Duration::from_secs(2)).await;
            std::process::exit(0);
        });
    }
    let status = run_child(name);
    assert!(aborted(status), "expected SIGABRT, got {status:?}");
}

/// Server mode: the expiration handler is called right away with zero time remaining.
/// 5.1.0+ runs it on a Ditto-owned thread (`tokio-rt-worker`); 5.0.4 ran it on a worker of
/// the app's own runtime (`tokio-runtime-worker`). Executed.
#[tokio::test(flavor = "multi_thread")]
async fn expiration_handler_first_call() {
    let dir = tempfile::tempdir().unwrap();
    let config = DittoConfig::new(
        "6e5e4a5c-0000-4000-8000-000000000001",
        DittoConfigConnect::Server {
            url: "https://127.0.0.1:9".parse().unwrap(),
        },
    )
    .with_persistence_directory(dir.path());
    let ditto = Ditto::open(config).await.unwrap();
    let (tx, mut rx) = mpsc::unbounded_channel();
    let app_thread_prefix = "tokio-runtime-worker";
    ditto
        .auth()
        .expect("auth exists in Server mode")
        .set_expiration_handler(move |_ditto: &Ditto, remaining: Duration| {
            let tx = tx.clone();
            async move {
                let name = std::thread::current().name().map(str::to_owned);
                let _ = tx.send((remaining, name));
            }
        });
    let (remaining, thread) = tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .unwrap()
        .unwrap();
    println!("expiration handler: remaining={remaining:?} thread={thread:?}");
    assert_eq!(remaining, Duration::ZERO);
    let on_app_runtime = thread.unwrap_or_default().starts_with(app_thread_prefix);
    assert_eq!(on_app_runtime, Ditto::version().starts_with("5.0."));
}
