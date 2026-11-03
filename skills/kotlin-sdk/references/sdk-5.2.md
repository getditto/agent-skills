# Kotlin SDK 5.2.0 changes

5.2.0 is the latest release known to this skill. For new apps/POCs resolve Maven
Central's latest stable release and use the same version for Kotlin and JVM binaries.

## Negative integer migration (CAP-08, CAP-19)

Before 5.2.0, map-based arguments encoded negative integers one lower than supplied:
`-5` became `-6`. Value accessors had a matching bug, hiding it in Kotlin round trips;
other SDKs/HTTP saw the stored value. 5.2.0 fixes both encoding and reading, including
`Int.MIN_VALUE`. Existing documents are **not repaired by upgrading**. Audit affected
writes/predicates in execute, transactions, subscriptions and observers; remove any
app compensation and repair data using its authoritative source. Do not blindly add
one to every negative value. Direct typed `@Serializable` payload overloads were not
affected, but serializable values nested inside map arguments were.

## Encryption and deletion (CAP-03, CAP-05, CAP-16)

Set `encryptionKey = DittoEncryptionKey.raw(bytes)` in `DittoConfig`, with exactly
32 high-entropy bytes managed by the app, then `DittoFactory.create(config)`. Keep
key material outside Ditto's directory, protected by the platform's secure storage,
and supply the same key on every open. It protects documents and attachments at rest.
It does not alter sync authorization. No in-place key rotation or plaintext-store
conversion is documented; preserve unsynced work during any planned recreation.

Catch `DittoException.EncryptionException` and inspect `reason`: `KeyRequired`,
`KeyUnexpected`, `KeyInvalid`, `UnsupportedScheme`, `MetadataCorrupt`. The older
passphrase errors are deprecated. `destroy()` on the key releases its native material;
configs retaining a destroyed key cannot subsequently open a store.

After closing all users of the store and `ditto.close()`, use
`DittoFactory.deleteStore(databaseId, persistenceDirectory)` only when the app intends
to erase that cache. It fails while a live instance holds the directory. Do not erase
customer data to recover automatically from an encryption or directory-lock error.

## Configuration, authentication and attachments (CAP-03, CAP-04, CAP-12)

- `DittoConfig.systemParameters: Map<String, Any>` applies overrides at open. Use it
  for startup-only settings; invalid names/types fail immediately.
- Prefer `ngn_data_streams_enabled` / `ngn_sync_enabled` over the deprecated
  `network_enable_ngn` / `replication_over_ngn`. Keep NGN sync false for streams-only
  previews. NGN sync true without streams true fails at sync start.
- Authentication failures expose `AuthenticationException.failureCode` and nullable
  `clientInfoJson`. Branch on the failure category; don't parse message text or assume
  every login error is retryable.
- `DittoTransactionInfo.hintOrNull` is null when absent; `hint` remains an empty string.
- Use `Map<String, String>` attachment metadata. Old `Map<String, Any?>` overloads
  are deprecated and reject non-string values immediately with `IllegalArgumentException`.
  Fetching an attachment no document references now terminates with `Deleted`.

## Android and diagnostics (CAP-02, CAP-06, CAP-15)

`DittoSyncPermissions.requiredMulticastPermissions()` is separate from ordinary
`requiredPermissions()`: reliable UDP multicast needs `CHANGE_WIFI_MULTICAST_STATE`
and, on API 37+ when targeting 37+, `ACCESS_LOCAL_NETWORK`. Declare/grant required
permissions before enabling this opt-in transport. Wi-Fi Aware and BLE recovery fixes
need physical-device tests; a JVM test cannot establish radio behavior.

5.2 adds `system:sync_degradations`, `system:support_bundles`, and
`EXECUTE FUNCTION system_request_support_bundle()` diagnostics. Most virtual observers
are change-driven; explicitly poll when periodic samples are required. DittoAndroidTools
also adds a support-bundle screen. Startup settings and data behavior do not depend
on installing this UI tool.

Sources: [5.2 Kotlin release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/kotlin),
[encryption guide](https://docs.ditto.live/sdk/latest/sync/encryption-at-rest),
and [published 5.2.0 API](https://software.ditto.live/kotlin/ditto-kotlin/5.2.0/api-reference/).
