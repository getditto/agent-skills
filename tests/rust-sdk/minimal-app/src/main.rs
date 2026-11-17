// Minimal Ditto Rust app: open -> subscribe -> observe -> write -> read back -> shut down.
// The published copy in skills/rust-sdk/examples/minimal-app.md is generated from this
// file by scripts/sync-snippets.py; edit this file, then run that script.
// snippet:start rust-minimal-app
use std::time::Duration;

use anyhow::Context as _;
use dittolive_ditto::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::sync::watch;

#[derive(Debug, Serialize, Deserialize)]
struct Car {
    #[serde(rename = "_id")]
    id: String,
    make: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // SmallPeersOnly without a key is unencrypted: development and tests only.
    let config = DittoConfig::new(
        "REPLACE_ME_WITH_YOUR_DATABASE_ID",
        DittoConfigConnect::SmallPeersOnly { private_key: None },
    )
    .with_persistence_directory(std::env::temp_dir().join("ditto-minimal-app"));

    let ditto = Ditto::open(config).await?;
    ditto.set_license_from_env("DITTO_OFFLINE_LICENSE")?;
    ditto.sync().start()?;

    // Both handles run until `cancel()` or Ditto shutdown; dropping the Arc does not stop them.
    let subscription = ditto.sync().register_subscription("SELECT * FROM cars")?;

    // The handler runs on a Ditto thread, not a Tokio task: keep it short and
    // non-blocking, and hand the data to async code through a channel.
    let (count_tx, mut count_rx) = watch::channel(0_usize);
    let observer = ditto
        .store()
        .register_observer("SELECT * FROM cars", move |result| {
            count_tx.send_replace(result.item_count());
        })?;

    let car = Car {
        id: "car1".into(),
        make: "Toyota".into(),
    };
    ditto
        .store()
        .execute((
            "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
            json!({ "car": car }),
        ))
        .await?;

    tokio::time::timeout(Duration::from_secs(10), count_rx.wait_for(|n| *n >= 1))
        .await
        .context("observer did not report the insert within 10 s")??;
    println!("observer: {} car(s)", *count_rx.borrow());

    let result = ditto
        .store()
        .execute((
            "SELECT * FROM cars WHERE _id = :id",
            json!({ "id": "car1" }),
        ))
        .await?;
    let stored: Car = result
        .get_item(0)
        .context("car1 not found")?
        .deserialize_value()?;
    println!("read-back make: {}", stored.make);
    println!("SDK version: {}", Ditto::version());

    observer.cancel();
    subscription.cancel();
    ditto.sync().stop();
    ditto.close();
    Ok(())
}
// snippet:end rust-minimal-app
