//! Executed evidence for the rust-sdk skill's Tokio guidance: what the SDK's async fns
//! actually do when polled, cancelled, or nested. Requires DITTO_OFFLINE_LICENSE.
//! Probes whose failure mode is an abort or a hang run in a child process.

use std::{
    collections::HashMap,
    path::Path,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
    time::Duration,
};

use dittolive_ditto::prelude::*;
use futures::FutureExt as _;
use serde_json::json;
use tokio::sync::mpsc;

fn license() -> String {
    std::env::var("DITTO_OFFLINE_LICENSE").expect("set DITTO_OFFLINE_LICENSE")
}

fn config(dir: &Path) -> DittoConfig {
    DittoConfig::new(
        "rust-skill-async",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(dir)
}

fn open_sync(dir: &Path) -> Ditto {
    let ditto = Ditto::open_sync(config(dir)).expect("open");
    ditto
        .set_offline_only_license_token(&license())
        .expect("license");
    ditto
}

fn insert_query(id: &str) -> (&'static str, serde_json::Value) {
    (
        "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
        json!({ "car": { "_id": id } }),
    )
}

/// Child outcomes travel as exit codes: stdout from a child test binary is not reliable.
const COMPLETED: i32 = 10;
const ERRORED: i32 = 11;
const HUNG: i32 = 12;

fn run_child(name: &str) -> std::process::ExitStatus {
    std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", name, "--nocapture", "--test-threads=1"])
        .env("RUST_SKILL_CHILD", name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .unwrap()
}

/// Exits the child with HUNG if it is still running after `seconds`.
fn watchdog(seconds: u64) {
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(seconds));
        std::process::exit(HUNG);
    });
}

#[cfg(unix)]
fn aborted(status: std::process::ExitStatus) -> bool {
    use std::os::unix::process::ExitStatusExt as _;
    status.signal() == Some(6)
}

fn is_child(name: &str) -> bool {
    std::env::var("RUST_SKILL_CHILD").as_deref() == Ok(name)
}

/// `Store::execute` does all its work inside the first poll: the future is Ready
/// immediately, so the query runs on (and blocks) whichever thread polls it.
#[test]
fn execute_completes_within_its_first_poll() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open_sync(dir.path());
    let first_poll = ditto.store().execute(insert_query("car1")).now_or_never();
    assert!(
        matches!(first_poll, Some(Ok(_))),
        "execute was not Ready on first poll"
    );
}

/// Futures are lazy: an `execute` future that is dropped unpolled never runs.
#[test]
fn unawaited_execute_does_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open_sync(dir.path());
    drop(ditto.store().execute(insert_query("never")));
    let count = ditto
        .store()
        .execute("SELECT * FROM cars")
        .now_or_never()
        .unwrap()
        .unwrap()
        .item_count();
    assert_eq!(count, 0);
}

/// Dropping the `signal_next` callback without calling it stalls the observer for good.
#[tokio::test(flavor = "multi_thread")]
async fn dropping_signal_next_without_calling_it_stalls_the_observer() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open_sync(dir.path());
    let calls = Arc::new(AtomicUsize::new(0));
    let _observer = {
        let calls = calls.clone();
        ditto
            .store()
            .register_observer_with_signal_next("SELECT * FROM cars", move |_, signal_next| {
                calls.fetch_add(1, Ordering::SeqCst);
                drop(signal_next);
            })
            .unwrap()
    };
    tokio::time::sleep(Duration::from_millis(300)).await;
    for i in 0..3 {
        ditto
            .store()
            .execute(insert_query(&format!("c{i}")))
            .await
            .unwrap();
    }
    tokio::time::sleep(Duration::from_millis(700)).await;
    println!(
        "callbacks with signal_next dropped: {}",
        calls.load(Ordering::SeqCst)
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

/// The bridge the skill recommends: hand `signal_next` to an async consumer, which calls it
/// after its `.await`ed work. Delivery is then paced by the consumer.
#[tokio::test(flavor = "multi_thread")]
async fn signal_next_bridge_paces_delivery_to_the_consumer() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open_sync(dir.path());
    let (tx, mut rx) = mpsc::channel::<(usize, Box<dyn FnOnce() + Send>)>(1);
    let _observer = ditto
        .store()
        .register_observer_with_signal_next("SELECT * FROM cars", move |result, signal_next| {
            // try_send never blocks the Ditto thread; capacity 1 is enough because Ditto
            // waits for signal_next before the next callback.
            if let Err(error) = tx.try_send((result.item_count(), signal_next)) {
                // Channel closed (consumer gone): release Ditto so it is not stalled.
                let (_, signal_next) = error.into_inner();
                signal_next();
            }
        })
        .unwrap();
    let consumer = tokio::spawn(async move {
        let mut seen = Vec::new();
        while let Some((count, signal_next)) = rx.recv().await {
            seen.push(count);
            tokio::time::sleep(Duration::from_millis(100)).await; // slow async work
            signal_next();
            if count == 10 {
                break;
            }
        }
        seen
    });
    for i in 0..10 {
        ditto
            .store()
            .execute(insert_query(&format!("c{i}")))
            .await
            .unwrap();
    }
    let seen = tokio::time::timeout(Duration::from_secs(10), consumer)
        .await
        .unwrap()
        .unwrap();
    println!("consumer saw counts: {seen:?}");
    assert_eq!(seen.last(), Some(&10));
    assert!(
        seen.len() < 11,
        "expected coalescing, got every change: {seen:?}"
    );
}

/// Cancelling an in-flight transaction future (here by `timeout`) while its closure awaits
/// leaves the store wedged: the next transaction never starts (executed 5.0.4-5.2.0).
#[test]
fn cancelling_a_transaction_future_wedges_the_store() {
    let name = "cancelling_a_transaction_future_wedges_the_store";
    if is_child(name) {
        watchdog(8);
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let ditto = open_sync(dir.path());
            let _ = tokio::time::timeout(
                Duration::from_millis(200),
                ditto.store().transaction(async |txn| {
                    txn.execute(insert_query("in-txn")).await?;
                    tokio::time::sleep(Duration::from_secs(2)).await;
                    Ok::<_, DittoError>(TransactionCompletionAction::Commit)
                }),
            )
            .await;
            let next = ditto
                .store()
                .transaction(async |txn| {
                    Ok::<_, DittoError>(txn.execute("SELECT * FROM cars").await?.item_count())
                })
                .await;
            std::process::exit(if next.is_ok() { COMPLETED } else { ERRORED });
        });
    }
    let status = run_child(name);
    println!("next transaction after a cancelled one: {status:?}");
    assert_eq!(status.code(), Some(HUNG), "expected a hang, got {status:?}");
}

/// Cancelling `Ditto::open` before it completes aborts the process when the open finishes.
#[test]
fn cancelling_ditto_open_aborts() {
    let name = "cancelling_ditto_open_aborts";
    if is_child(name) {
        watchdog(8);
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let _ = tokio::time::timeout(Duration::from_micros(1), Ditto::open(config(dir.path())))
                .await;
            tokio::time::sleep(Duration::from_secs(2)).await;
            std::process::exit(COMPLETED);
        });
    }
    let status = run_child(name);
    println!("cancelled open: {status:?}");
    assert!(aborted(status), "expected SIGABRT, got {status:?}");
}

/// `ditto.store().execute` (instead of `txn.execute`) inside a read-write transaction
/// waits for that same transaction: a deadlock.
#[test]
fn store_execute_inside_a_transaction_deadlocks() {
    let name = "store_execute_inside_a_transaction_deadlocks";
    if is_child(name) {
        watchdog(5);
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let dir = tempfile::tempdir().unwrap();
            let ditto = open_sync(dir.path());
            let outcome = ditto
                .store()
                .transaction(async |_txn| {
                    ditto.store().execute(insert_query("outer")).await?;
                    Ok::<_, DittoError>(TransactionCompletionAction::Commit)
                })
                .await;
            std::process::exit(if outcome.is_ok() { COMPLETED } else { ERRORED });
        });
    }
    let status = run_child(name);
    println!("store.execute inside transaction: {status:?}");
    assert_eq!(
        status.code(),
        Some(HUNG),
        "expected a deadlock, got {status:?}"
    );
}

/// `TransportConfig::default()` is not `TransportConfig::new()`.
#[test]
fn transport_config_default_differs_from_new() {
    let new = TransportConfig::new();
    let default = TransportConfig::default();
    println!(
        "new: mdns={} retry={:?} tcp_port={} | default: mdns={} retry={:?} tcp_port={}",
        new.peer_to_peer.lan.mdns_enabled,
        new.connect.retry_interval,
        new.listen.tcp.port,
        default.peer_to_peer.lan.mdns_enabled,
        default.connect.retry_interval,
        default.listen.tcp.port,
    );
    assert!(new.peer_to_peer.lan.mdns_enabled);
    assert!(!default.peer_to_peer.lan.mdns_enabled);
}

/// Attachments: the field must be declared ATTACHMENT; fetch completes locally; dropping
/// the fetcher handle.
#[tokio::test(flavor = "multi_thread")]
async fn attachment_round_trip() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open_sync(dir.path());
    let store = ditto.store();
    let attachment = store
        .new_attachment_from_bytes(b"hello", HashMap::from([("name".into(), "hi.txt".into())]))
        .await
        .unwrap();
    store
        .execute((
            "INSERT INTO COLLECTION files (blob ATTACHMENT) DOCUMENTS (:doc)",
            json!({ "doc": { "_id": "f1", "blob": attachment } }),
        ))
        .await
        .unwrap();
    let result = store
        .execute("SELECT * FROM COLLECTION files (blob ATTACHMENT) WHERE _id = 'f1'")
        .await
        .unwrap();
    let item = result.get_item(0).unwrap();
    let value = item.value();
    let token = value.get("blob").unwrap().as_object().unwrap();

    let (tx, mut rx) = mpsc::unbounded_channel();
    let fetcher = store
        .fetch_attachment(token, move |event| {
            if let DittoAttachmentFetchEvent::Completed { attachment } = event {
                let _ = tx.send(std::fs::read(attachment.path()).unwrap());
            }
        })
        .unwrap();
    let bytes = tokio::time::timeout(Duration::from_secs(10), rx.recv())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(bytes, b"hello");
    drop(fetcher);

    // Without the ATTACHMENT declaration the token is stored as a plain map.
    store
        .execute((
            "INSERT INTO plain DOCUMENTS (:doc)",
            json!({ "doc": { "_id": "p1", "blob": attachment } }),
        ))
        .await
        .unwrap();
    let plain = store.execute("SELECT * FROM plain").await.unwrap();
    let plain_item = plain.get_item(0).unwrap();
    let plain_value = plain_item.value();
    let fetched = store.fetch_attachment(
        plain_value.get("blob").unwrap().as_object().unwrap(),
        |_| {},
    );
    println!(
        "fetch with undeclared field: {:?}",
        fetched.as_ref().err().map(ToString::to_string)
    );
}
