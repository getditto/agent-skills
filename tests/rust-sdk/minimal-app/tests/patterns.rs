//! The Tokio integration patterns published in skills/rust-sdk. Each `snippet:` region is
//! copied verbatim into the skill by scripts/sync-snippets.py; the tests below execute them.
//! Requires DITTO_OFFLINE_LICENSE.

use std::{path::Path, time::Duration};

use serde_json::json;

// snippet:start rust-cancel-guard
use std::sync::Arc;

use dittolive_ditto::{store::StoreObserver, sync::SyncSubscription};

/// Ditto's handles keep running when the last `Arc` is dropped; only `cancel()` stops
/// them. `Cancelling` restores RAII: dropping the guard cancels the handle.
pub trait Cancel {
    fn cancel(&self);
}

impl Cancel for StoreObserver {
    fn cancel(&self) {
        StoreObserver::cancel(self);
    }
}

impl Cancel for SyncSubscription {
    fn cancel(&self) {
        SyncSubscription::cancel(self);
    }
}

#[must_use = "dropping the guard cancels the handle immediately"]
pub struct Cancelling<T: Cancel>(Arc<T>);

impl<T: Cancel> Cancelling<T> {
    pub fn new(handle: Arc<T>) -> Self {
        Self(handle)
    }
}

impl<T: Cancel> std::ops::Deref for Cancelling<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.0
    }
}

impl<T: Cancel> Drop for Cancelling<T> {
    fn drop(&mut self) {
        self.0.cancel();
    }
}
// snippet:end rust-cancel-guard

// snippet:start rust-observe-channel
use dittolive_ditto::prelude::*;
use serde::de::DeserializeOwned;
use tokio::sync::mpsc;

/// One observer delivery. Ditto sends nothing newer until this value is dropped, so a
/// slow consumer gets the latest state instead of a backlog.
pub struct Update<T> {
    pub items: Vec<T>,
    _ack: Ack,
}

struct Ack(Option<Box<dyn FnOnce() + Send>>);

impl Drop for Ack {
    fn drop(&mut self) {
        if let Some(signal_next) = self.0.take() {
            signal_next(); // never leave Ditto waiting: an uncalled signal stalls the observer
        }
    }
}

/// Observes `query` and delivers decoded rows to async code through a channel.
pub fn observe<T, Q>(
    store: &Store,
    query: Q,
) -> Result<(Cancelling<StoreObserver>, mpsc::Receiver<Update<T>>), DittoError>
where
    T: DeserializeOwned + Send + 'static,
    Q: IntoQuery,
    Q::Args: serde::Serialize,
{
    // Capacity 1 suffices: Ditto waits for the Ack before the next callback.
    let (tx, rx) = mpsc::channel(1);
    let observer =
        store.register_observer_with_signal_next(query, move |result, signal_next| {
            // Runs on a Ditto thread: decode here, never block, never panic.
            let items = result
                .iter()
                .filter_map(|item| item.deserialize_value::<T>().ok())
                .collect();
            let update = Update {
                items,
                _ack: Ack(Some(signal_next)),
            };
            // If the receiver is gone the update is dropped here, which acks it.
            let _ = tx.try_send(update);
        })?;
    Ok((Cancelling::new(observer), rx))
}
// snippet:end rust-observe-channel

// snippet:start rust-heavy-query
/// `Store::execute` does its work inside the first poll, on the polling thread. Move
/// large scans and bulk writes off the async workers.
pub async fn count_off_the_runtime(store: Store, query: String) -> anyhow::Result<usize> {
    let runtime = tokio::runtime::Handle::current();
    let result =
        tokio::task::spawn_blocking(move || runtime.block_on(store.execute(query))).await??;
    Ok(result.item_count())
}
// snippet:end rust-heavy-query

// snippet:start rust-shared-instance
/// One `Ditto` per process and persistence directory. It is `Send + Sync` but not
/// `Clone`: share it as `Arc<Ditto>`.
#[derive(Clone)]
pub struct AppState {
    pub ditto: Arc<Ditto>,
}

impl AppState {
    pub async fn record_reading(&self, sensor: &str, value: f64) -> Result<(), DittoError> {
        self.ditto
            .store()
            .execute((
                "INSERT INTO readings DOCUMENTS (:doc)",
                serde_json::json!({ "doc": { "sensor": sensor, "value": value } }),
            ))
            .await?;
        Ok(())
    }
}
// snippet:end rust-shared-instance

// snippet:start rust-graceful-shutdown
/// Runs until `shutdown` resolves (e.g. `tokio::signal::ctrl_c()`), then tears down in
/// order: the subscription guard cancels, then sync stops. The caller drops the last
/// `Arc<Ditto>` afterwards, which shuts the instance down.
pub async fn serve(
    ditto: Arc<Ditto>,
    shutdown: impl std::future::Future<Output = ()>,
) -> Result<(), DittoError> {
    ditto.sync().start()?;
    let subscription = Cancelling::new(ditto.sync().register_subscription("SELECT * FROM cars")?);
    shutdown.await;
    drop(subscription); // cancels
    ditto.sync().stop();
    Ok(())
}
// snippet:end rust-graceful-shutdown

#[derive(Debug, serde::Deserialize)]
struct Car {
    make: String,
}

async fn open(dir: &Path) -> Ditto {
    let config = DittoConfig::new(
        "rust-skill-patterns",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(dir);
    let ditto = Ditto::open(config).await.unwrap();
    ditto
        .set_offline_only_license_token(&std::env::var("DITTO_OFFLINE_LICENSE").unwrap())
        .unwrap();
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
        .unwrap();
}

#[tokio::test]
async fn dropping_the_guard_cancels() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let observer = Cancelling::new(
        ditto
            .store()
            .register_observer("SELECT * FROM cars", |_| {})
            .unwrap(),
    );
    let subscription = Cancelling::new(
        ditto
            .sync()
            .register_subscription("SELECT * FROM cars")
            .unwrap(),
    );
    assert!(!observer.is_cancelled());
    drop(observer);
    drop(subscription);
    assert_eq!(ditto.sync().subscriptions().len(), 0);
    assert_eq!(ditto.store().observers().keys.len(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn observe_channel_delivers_latest_state_to_a_slow_consumer() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    let (_observer, mut updates) = observe::<Car, _>(ditto.store(), "SELECT * FROM cars").unwrap();
    let initial = updates.recv().await.unwrap();
    assert!(initial.items.is_empty());
    for i in 0..10 {
        insert(&ditto, &format!("car{i}")).await;
    }
    tokio::time::sleep(Duration::from_millis(300)).await; // consumer is "busy"
    drop(initial); // ack: Ditto may now deliver the latest state
    let latest = tokio::time::timeout(Duration::from_secs(10), updates.recv())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(latest.items.len(), 10);
    assert_eq!(latest.items[0].make, "Toyota");
}

#[tokio::test(flavor = "multi_thread")]
async fn heavy_query_runs_on_the_blocking_pool() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = open(dir.path()).await;
    insert(&ditto, "car1").await;
    let n = count_off_the_runtime(ditto.store().clone(), "SELECT * FROM cars".into())
        .await
        .unwrap();
    assert_eq!(n, 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn shared_instance_across_tasks() {
    let dir = tempfile::tempdir().unwrap();
    let state = AppState {
        ditto: Arc::new(open(dir.path()).await),
    };
    let tasks: Vec<_> = (0..8)
        .map(|i| {
            let state = state.clone();
            tokio::spawn(async move { state.record_reading(&format!("s{i}"), i as f64).await })
        })
        .collect();
    for task in tasks {
        task.await.unwrap().unwrap();
    }
    let n = state
        .ditto
        .store()
        .execute("SELECT * FROM readings")
        .await
        .unwrap()
        .item_count();
    assert_eq!(n, 8);
}

#[tokio::test(flavor = "multi_thread")]
async fn serve_tears_down_on_shutdown() {
    let dir = tempfile::tempdir().unwrap();
    let ditto = Arc::new(open(dir.path()).await);
    serve(
        ditto.clone(),
        tokio::time::sleep(Duration::from_millis(100)),
    )
    .await
    .unwrap();
    assert!(!ditto.sync().is_active());
    assert_eq!(ditto.sync().subscriptions().len(), 0);
    let ditto = Arc::into_inner(ditto).expect("sole owner");
    ditto.close();
}
