// The deprecated 4.14.x builder form, compiled against 4.14.7 so the skill's versions.md can
// show it accurately. Never emit this for 5.x: every item here was removed in 5.0.
// snippet:start rust-v4-builder
#![allow(deprecated)]

use std::sync::Arc;

use dittolive_ditto::{identity, prelude::*};

/// 4.14.x only. Deprecated there ("will be removed in SDK 5.0"); use DittoConfig instead.
pub fn open_with_v4_builder() -> Result<Ditto, DittoError> {
    Ditto::builder()
        .with_root(Arc::new(PersistentRoot::from_current_exe()?))
        .with_identity(|root| identity::OfflinePlayground::new(root, AppId::from_env("APP_ID")?))?
        .build()
}
// snippet:end rust-v4-builder
