//! Code samples published in skills/rust-sdk/references/*.md. Each `snippet:` region is
//! copied verbatim into a reference by scripts/sync-snippets.py, so every Rust block the
//! skill shows compiles (and passes clippy) here. Tests run the samples that can run on
//! one peer with an offline license. Requires DITTO_OFFLINE_LICENSE.
#![allow(dead_code)]

use std::{collections::HashMap, time::Duration};

use dittolive_ditto::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::json;

// snippet:start rust-open-config
async fn open_ditto() -> Result<Ditto, DittoError> {
    let mut config = DittoConfig::new(
        "REPLACE_ME_WITH_YOUR_DATABASE_ID",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory("/var/lib/my-app/ditto");
    // Optional overrides, applied before Ditto starts its subsystems.
    config.system_parameters.insert(
        "REPLACE_ME_WITH_A_PARAMETER_NAME".into(),
        serde_json::json!(true),
    );
    Ditto::open(config).await
}
// snippet:end rust-open-config

// snippet:start rust-activate-license
fn activate(ditto: &Ditto) -> Result<(), DittoError> {
    // Small-peers-only mode only. Equivalent: ditto.set_offline_only_license_token(&token)
    ditto.set_license_from_env("DITTO_OFFLINE_LICENSE")
}
// snippet:end rust-activate-license

// snippet:start rust-server-mode
/// A handler that needs state is a type implementing the trait: an `async move` closure
/// that captures a value is not `Fn` and is rejected ("async closure does not implement
/// `Fn` because it captures state from its environment").
struct Login {
    token: String,
    /// The authentication webhook name from the Ditto portal. For a development token,
    /// pass `dittolive_ditto::auth::get_development_provider()` (5.0.x: `identity::`).
    provider: String,
}

impl DittoAuthExpirationHandler for Login {
    async fn on_expiration(&self, ditto: &Ditto, _remaining: Duration) {
        let Some(auth) = ditto.auth() else { return };
        // In production, fetch a fresh token from your identity service here (bounded by
        // a timeout) instead of reusing a stored one.
        if let Err(error) = auth.login(&self.token, &self.provider) {
            eprintln!("Ditto login failed: {error}");
        }
    }
}

async fn open_online(url: &str, database_id: &str, login: Login) -> anyhow::Result<Ditto> {
    let connect = DittoConfigConnect::Server { url: url.parse()? };
    let ditto = Ditto::open(DittoConfig::new(database_id, connect)).await?;
    let auth = ditto.auth().expect("auth exists in Server mode");
    auth.set_expiration_handler(login);
    ditto.sync().start()?;
    Ok(ditto)
}
// snippet:end rust-server-mode

// snippet:start rust-typed-query
#[derive(Debug, Serialize, Deserialize)]
struct Order {
    #[serde(rename = "_id")]
    id: String,
    customer: String,
    total_cents: u64,
}

#[derive(Serialize)]
struct ByCustomer<'a> {
    customer: &'a str,
}

async fn orders_for(store: &Store, customer: &str) -> Result<Vec<Order>, DittoError> {
    let result = store
        .execute((
            "SELECT * FROM orders WHERE customer = :customer ORDER BY total_cents DESC",
            ByCustomer { customer },
        ))
        .await?;
    result
        .iter()
        .map(|item| item.deserialize_value::<Order>())
        .collect()
}
// snippet:end rust-typed-query

// snippet:start rust-write-result
async fn upsert(store: &Store, order: &Order) -> Result<(), DittoError> {
    let result = store
        .execute((
            "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
            json!({ "order": order }),
        ))
        .await?;
    // Mutations return no rows; the affected IDs and the local commit are on the result.
    for id in result.mutated_document_ids() {
        println!(
            "wrote {}",
            id.to_query_compatible(StringPrimitiveFormat::WithoutQuotes)
        );
    }
    println!("commit: {:?}", result.commit_id());
    Ok(())
}
// snippet:end rust-write-result

// snippet:start rust-transaction
/// Reserves `quantity` units if enough stock remains. `stock` is a PN counter: DQL
/// returns counter values as floating-point numbers.
async fn reserve(store: &Store, sku: &str, quantity: f64) -> Result<bool, DittoError> {
    let outcome = store
        .transaction(async |txn| {
            let args = json!({ "sku": sku, "quantity": quantity, "delta": -quantity });
            let stock = txn
                .execute(("SELECT stock FROM products WHERE _id = :sku", args.clone()))
                .await?
                .get_item(0)
                .and_then(|item| item.value().get("stock")?.as_f64())
                .unwrap_or(0.0);
            if stock < quantity {
                return Ok(TransactionCompletionAction::Rollback);
            }
            // Only `txn.execute` here: `store.execute` inside the closure deadlocks.
            txn.execute((
                "UPDATE products APPLY stock PN_INCREMENT BY :delta WHERE _id = :sku",
                args.clone(),
            ))
            .await?;
            txn.execute((
                "INSERT INTO reservations DOCUMENTS ({ 'sku': :sku, 'quantity': :quantity })",
                args,
            ))
            .await?;
            Ok::<_, DittoError>(TransactionCompletionAction::Commit)
        })
        .await?;
    Ok(matches!(outcome, TransactionCompletionAction::Commit))
}
// snippet:end rust-transaction

// snippet:start rust-index-evict
async fn maintain(store: &Store) -> Result<(), DittoError> {
    store
        .execute("CREATE INDEX IF NOT EXISTS orders_by_customer ON orders (customer)")
        .await?;
    let evicted = store
        .execute((
            "EVICT FROM orders WHERE created_at < :cutoff",
            json!({ "cutoff": "2026-01-01T00:00:00Z" }),
        ))
        .await?;
    println!(
        "evicted {} local document(s)",
        evicted.mutated_document_ids().len()
    );
    Ok(())
}
// snippet:end rust-index-evict

// snippet:start rust-subscription-args
fn subscribe_to_customer(
    ditto: &Ditto,
    customer: &str,
) -> Result<std::sync::Arc<dittolive_ditto::sync::SyncSubscription>, DittoError> {
    // Keep the Arc and call cancel() when the data is no longer needed:
    // dropping it does not stop the subscription.
    ditto.sync().register_subscription((
        "SELECT * FROM orders WHERE customer = :customer",
        json!({ "customer": customer }),
    ))
}
// snippet:end rust-subscription-args

// snippet:start rust-sync-info
fn watch_sync_info(
    ditto: &Ditto,
) -> Result<std::sync::Arc<dittolive_ditto::store::StoreObserver>, DittoError> {
    ditto
        .store()
        .register_observer("SELECT * FROM system:data_sync_info", |result| {
            for item in result.iter() {
                println!("sync info: {}", item.json_string());
            }
        })
}
// snippet:end rust-sync-info

// snippet:start rust-differ
use std::sync::Mutex;

use dittolive_ditto::dql::Differ;

fn observe_changes(
    store: &Store,
) -> Result<std::sync::Arc<dittolive_ditto::store::StoreObserver>, DittoError> {
    // One Differ per observer: it remembers the previous result. Its first diff reports
    // every row as an insertion.
    let differ = Mutex::new(Differ::new());
    store.register_observer("SELECT * FROM orders ORDER BY _id", move |result| {
        let Ok(differ) = differ.lock() else { return };
        let diff = differ.diff(result.iter());
        println!(
            "+{} -{} ~{} moved {}",
            diff.insertions.len(),
            diff.deletions.len(),
            diff.updates.len(),
            diff.moves.len()
        );
    })
}
// snippet:end rust-differ

// snippet:start rust-attachments
use dittolive_ditto::store::attachment::DittoAttachmentFetchEvent;

async fn attach_and_fetch(store: &Store, bytes: &[u8]) -> anyhow::Result<()> {
    let metadata = HashMap::from([("name".to_string(), "photo.jpg".to_string())]);
    let attachment = store.new_attachment_from_bytes(bytes, metadata).await?;
    // The field must be declared ATTACHMENT, with the COLLECTION keyword.
    store
        .execute((
            "INSERT INTO COLLECTION photos (image ATTACHMENT) DOCUMENTS (:doc)",
            json!({ "doc": { "_id": "p1", "image": attachment } }),
        ))
        .await?;

    let result = store
        .execute("SELECT * FROM COLLECTION photos (image ATTACHMENT) WHERE _id = 'p1'")
        .await?;
    let item = result
        .get_item(0)
        .ok_or_else(|| anyhow::anyhow!("p1 missing"))?;
    let value = item.value();
    let token = value
        .get("image")
        .and_then(|image| image.as_object())
        .ok_or_else(|| anyhow::anyhow!("no attachment token"))?;

    let (tx, rx) = tokio::sync::oneshot::channel();
    let tx = std::sync::Mutex::new(Some(tx));
    let _fetcher = store.fetch_attachment(token, move |event| match event {
        DittoAttachmentFetchEvent::Progress {
            downloaded_bytes,
            total_bytes,
        } => {
            println!("{downloaded_bytes}/{total_bytes} bytes");
        }
        DittoAttachmentFetchEvent::Completed { attachment } => {
            if let Some(tx) = tx.lock().ok().and_then(|mut slot| slot.take()) {
                let _ = tx.send(attachment.path());
            }
        }
        DittoAttachmentFetchEvent::Deleted => println!("attachment deleted"),
    })?;
    let path = tokio::time::timeout(Duration::from_secs(30), rx).await??;
    println!("attachment file: {}", path.display());
    Ok(())
}
// snippet:end rust-attachments

// snippet:start rust-presence
use dittolive_ditto::presence::{ConnectionRequest, ConnectionRequestAuthorization};

fn configure_presence(ditto: &Ditto) -> Result<PresenceObserver, DittoError> {
    // Visible to peers in their graph and in connection requests (4 KiB limit).
    ditto
        .presence()
        .set_peer_metadata(&json!({ "role": "gateway", "app_version": "1.4.0" }))?;

    ditto
        .presence()
        .set_connection_request_handler(|request: ConnectionRequest| {
            // Runs on a Ditto thread with a 10 s deadline: decide without I/O.
            match request
                .peer_metadata()
                .get("app_version")
                .and_then(|v| v.as_str())
            {
                Some(version) if version.starts_with("1.") => ConnectionRequestAuthorization::Allow,
                _ => ConnectionRequestAuthorization::Deny,
            }
        });

    let graph = ditto.presence().graph();
    println!("local peer {}", graph.local_peer.peer_key);
    ditto.presence().register_observer(|graph: &PresenceGraph| {
        println!("{} remote peer(s)", graph.remote_peers.len());
    })
}
// snippet:end rust-presence

// snippet:start rust-logging
async fn configure_logging() -> Result<(), DittoError> {
    // Process-wide; set before Ditto::open to cover start-up.
    DittoLogger::set_minimum_log_level(LogLevel::Warning);
    DittoLogger::set_custom_log_callback(|level, message| match level {
        LogLevel::Error => eprintln!("ditto error: {message}"),
        LogLevel::Warning => eprintln!("ditto warning: {message}"),
        _ => {}
    });
    // Gzipped JSON lines; the file must not exist yet.
    let bytes = DittoLogger::export_to_file("/tmp/ditto-logs.jsonl.gz").await?;
    println!("exported {bytes} bytes of logs");
    Ok(())
}
// snippet:end rust-logging

// snippet:start rust-tracing-bridge
/// Forwards Ditto's log lines into the app's `tracing` subscriber.
fn forward_ditto_logs_to_tracing() {
    DittoLogger::set_custom_log_callback(|level, message| match level {
        LogLevel::Error => tracing::error!(target: "ditto", "{message}"),
        LogLevel::Warning => tracing::warn!(target: "ditto", "{message}"),
        LogLevel::Info => tracing::info!(target: "ditto", "{message}"),
        _ => tracing::debug!(target: "ditto", "{message}"),
    });
}
// snippet:end rust-tracing-bridge

// snippet:start rust-disk-usage
fn report_disk_usage(ditto: &Ditto) -> std::sync::Arc<DiskUsageObserverHandle> {
    println!(
        "store size: {} bytes",
        ditto.disk_usage().item().size_in_bytes
    );
    // Unlike store observers, dropping this handle stops the observation.
    ditto.disk_usage().observe(|usage: DiskUsageItem| {
        println!("store size now: {} bytes", usage.size_in_bytes);
    })
}
// snippet:end rust-disk-usage

// snippet:start rust-support-bundle
use std::path::{Path, PathBuf};

/// Generates a support bundle (5.2.0+) and copies the archive to `destination`.
/// The bundle is a tar file stored as a local attachment; ship it to Ditto support
/// through your own channel.
async fn save_support_bundle(ditto: &Ditto, destination: &Path) -> anyhow::Result<PathBuf> {
    let result = ditto
        .store()
        .execute((
            "EXECUTE FUNCTION system_request_support_bundle({ 'metadata': :metadata })",
            json!({ "metadata": { "requested_by": "ops-cli" } }),
        ))
        .await?;
    let bundle = result
        .get_item(0)
        .ok_or_else(|| anyhow::anyhow!("no bundle row"))?;
    let value = bundle.value();
    let token = value
        .get("file")
        .and_then(|file| file.as_object())
        .ok_or_else(|| anyhow::anyhow!("bundle row has no file"))?;

    let (tx, rx) = tokio::sync::oneshot::channel();
    let tx = std::sync::Mutex::new(Some(tx));
    let _fetcher = ditto.store().fetch_attachment(token, move |event| {
        if let DittoAttachmentFetchEvent::Completed { attachment } = event {
            if let Some(tx) = tx.lock().ok().and_then(|mut slot| slot.take()) {
                let _ = tx.send(attachment.path());
            }
        }
    })?;
    let stored = tokio::time::timeout(Duration::from_secs(30), rx).await??;
    std::fs::copy(&stored, destination)?; // never move or edit Ditto's own copy
    Ok(destination.to_path_buf())
}
// snippet:end rust-support-bundle

// snippet:start rust-error-match
use dittolive_ditto::error::{CoreApiErrorKind, ErrorKind};

async fn insert_once(store: &Store, id: &str) -> Result<bool, DittoError> {
    match store
        .execute((
            "INSERT INTO cars DOCUMENTS (:car)",
            json!({ "car": { "_id": id } }),
        ))
        .await
    {
        Ok(_) => Ok(true),
        // A duplicate `_id` under the default FAIL policy. Its kind differs by version
        // (5.0.x: StoreDatabase; 5.1.0+: DqlEvaluationError); the message does not.
        Err(error) if error.to_string().contains("Identifier conflict") => Ok(false),
        Err(error) => match error.kind() {
            ErrorKind::CoreApi(CoreApiErrorKind::DqlQueryCompilation) => {
                panic!("bug in a hard-coded query: {error}") // aborts: Ditto is open
            }
            _ => Err(error),
        },
    }
}
// snippet:end rust-error-match

// snippet:start rust-transport-config
fn configure_transports(ditto: &Ditto) {
    // Start from the live config; TransportConfig::default() is NOT TransportConfig::new().
    ditto.update_transport_config(|config| {
        config.peer_to_peer.bluetooth_le.enabled = false;
        config.peer_to_peer.lan.enabled = true;
        config.listen.tcp.enabled = true;
        config.listen.tcp.interface_ip = "0.0.0.0".to_string();
        config.listen.tcp.port = 4040;
        config
            .connect
            .tcp_servers
            .insert("10.0.0.5:4040".to_string());
    });
}
// snippet:end rust-transport-config

// snippet:start rust-test-harness
/// One Ditto per test, in its own directory. Fields drop in declaration order: `ditto`
/// comes first so the TempDir outlives it.
struct TestPeer {
    ditto: Ditto,
    _dir: tempfile::TempDir,
}

async fn test_peer() -> TestPeer {
    let dir = tempfile::tempdir().expect("temp dir");
    let config = DittoConfig::new(
        "my-app-tests",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(dir.path());
    let ditto = Ditto::open(config).await.expect("open");
    ditto
        .set_license_from_env("DITTO_OFFLINE_LICENSE")
        .expect("set DITTO_OFFLINE_LICENSE");
    TestPeer { ditto, _dir: dir }
}

#[tokio::test]
async fn upsert_is_idempotent() {
    let peer = test_peer().await;
    let store = peer.ditto.store();
    for _ in 0..2 {
        store
            .execute((
                "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
                json!({ "car": { "_id": "c1", "make": "Toyota" } }),
            ))
            .await
            .expect("upsert");
    }
    let count = store
        .execute("SELECT * FROM cars")
        .await
        .expect("select")
        .item_count();
    assert_eq!(count, 1);
}
// snippet:end rust-test-harness

// Tests that run the samples above.

#[tokio::test(flavor = "multi_thread")]
async fn store_samples_run() {
    let peer = test_peer().await;
    let store = peer.ditto.store();
    let order = Order {
        id: "o1".into(),
        customer: "ada".into(),
        total_cents: 1200,
    };
    upsert(store, &order).await.unwrap();
    let orders = orders_for(store, "ada").await.unwrap();
    assert_eq!(orders.len(), 1);
    assert_eq!(orders[0].total_cents, 1200);
    maintain(store).await.unwrap();
    assert!(insert_once(store, "x").await.unwrap());
    assert!(!insert_once(store, "x").await.unwrap());
}

#[tokio::test(flavor = "multi_thread")]
async fn transaction_sample_commits_and_rolls_back() {
    let peer = test_peer().await;
    let store = peer.ditto.store();
    store
        .execute((
            "INSERT INTO products DOCUMENTS (:p)",
            json!({ "p": { "_id": "sku1" } }),
        ))
        .await
        .unwrap();
    store
        .execute("UPDATE products APPLY stock PN_INCREMENT BY 10 WHERE _id = 'sku1'")
        .await
        .unwrap();
    assert!(reserve(store, "sku1", 3.0).await.unwrap());
    assert!(
        !reserve(store, "sku1", 50.0).await.unwrap(),
        "insufficient stock rolls back"
    );
    let stock = store
        .execute("SELECT stock FROM products WHERE _id = 'sku1'")
        .await
        .unwrap()
        .get_item(0)
        .unwrap()
        .value()
        .get("stock")
        .unwrap()
        .as_f64()
        .unwrap();
    let reservations = store
        .execute("SELECT * FROM reservations")
        .await
        .unwrap()
        .item_count();
    println!("stock={stock} reservations={reservations}");
    assert_eq!((stock, reservations), (7.0, 1));
}

#[tokio::test(flavor = "multi_thread")]
async fn observer_samples_run() {
    let peer = test_peer().await;
    let subscription = subscribe_to_customer(&peer.ditto, "ada").unwrap();
    let info = watch_sync_info(&peer.ditto).unwrap();
    let changes = observe_changes(peer.ditto.store()).unwrap();
    let presence = configure_presence(&peer.ditto).unwrap();
    let _usage = report_disk_usage(&peer.ditto);
    configure_transports(&peer.ditto);
    assert!(peer.ditto.transport_config().listen.tcp.enabled);
    tokio::time::sleep(Duration::from_millis(200)).await;
    for handle in [&changes, &info] {
        handle.cancel();
    }
    subscription.cancel();
    presence.cancel();
}

#[tokio::test(flavor = "multi_thread")]
async fn attachment_sample_runs() {
    let peer = test_peer().await;
    attach_and_fetch(peer.ditto.store(), b"jpeg bytes")
        .await
        .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn support_bundle_sample_runs_and_is_rate_limited() {
    let peer = test_peer().await;
    let out = tempfile::tempdir().unwrap();
    if !Ditto::version().starts_with("5.2.") {
        // Support bundles are new in 5.2.0: older lines have no such DQL function.
        let error = save_support_bundle(&peer.ditto, &out.path().join("bundle.tar"))
            .await
            .expect_err("support bundles do not exist before 5.2.0");
        println!("support bundle on {}: {error}", Ditto::version());
        return;
    }
    let path = save_support_bundle(&peer.ditto, &out.path().join("bundle.tar"))
        .await
        .unwrap();
    let listing = std::process::Command::new("tar")
        .arg("tf")
        .arg(&path)
        .output()
        .unwrap();
    let entries = String::from_utf8_lossy(&listing.stdout).into_owned();
    println!("bundle entries: {entries:?}");
    assert!(entries.contains("config_snapshot.json"), "{entries}");
    assert!(entries.contains("ditto-logs.log.gz"), "{entries}");
    // dial9 segments rotate every 60 s and only completed ones are bundled, so a bundle
    // from a process younger than a minute has no dial9 entry (one requested after 75 s
    // does: executed on macOS arm64, 5.2.0).
    assert!(
        !entries.contains("dial9"),
        "dial9 entry before 60 s: {entries}"
    );
    let listed = peer
        .ditto
        .store()
        .execute("SELECT * FROM system:support_bundles")
        .await
        .unwrap()
        .item_count();
    assert_eq!(listed, 1);
    // Default budget: 3 requests per rolling ten minutes, per peer.
    for _ in 0..2 {
        peer.ditto
            .store()
            .execute("EXECUTE FUNCTION system_request_support_bundle()")
            .await
            .unwrap();
    }
    let limited = peer
        .ditto
        .store()
        .execute("EXECUTE FUNCTION system_request_support_bundle()")
        .await
        .err()
        .expect("the fourth request in the window is refused");
    println!("rate limited: {:?} | {limited}", limited.kind());
}
