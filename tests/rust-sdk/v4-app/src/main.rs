// 4.14.7: DittoConfig/Ditto::open exist, DQL uses the *_v2 methods, and mutating DQL
// fails until disable_sync_with_v3() is called. Prints each observed outcome.
// Compiled for the skill, never called.
#[allow(dead_code)]
mod legacy;

use std::time::Duration;

use dittolive_ditto::prelude::*;
use serde_json::json;
use tokio::sync::watch;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let dir = std::env::temp_dir().join(format!("ditto-v4-app-{}", std::process::id()));
    let config = DittoConfig::new(
        "rust-skill-v4",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(&dir);
    let ditto = Ditto::open(config).await?;
    ditto.set_license_from_env("DITTO_OFFLINE_LICENSE")?;
    ditto.sync().start()?;

    let insert = (
        "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
        json!({ "car": { "_id": "car1", "make": "Toyota" } }),
    );
    match ditto.store().execute_v2(insert.clone()).await {
        Ok(_) => println!("insert before disable_sync_with_v3: ok"),
        Err(error) => println!("insert before disable_sync_with_v3: {error}"),
    }
    ditto.disable_sync_with_v3()?;

    let _subscription = ditto
        .sync()
        .register_subscription_v2("SELECT * FROM cars")?;
    let (tx, mut rx) = watch::channel(0_usize);
    let observer = ditto
        .store()
        .register_observer_v2("SELECT * FROM cars", move |result| {
            tx.send_replace(result.item_count());
        })?;
    ditto.store().execute_v2(insert).await?;
    tokio::time::timeout(Duration::from_secs(10), rx.wait_for(|n| *n >= 1)).await??;
    println!("observer: {} car(s)", *rx.borrow());
    println!("SDK version: {}", Ditto::version());
    observer.cancel();
    ditto.close();
    let _ = std::fs::remove_dir_all(dir);
    Ok(())
}
