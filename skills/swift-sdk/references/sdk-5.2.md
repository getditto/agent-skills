# Swift SDK 5.2.0 changes

5.2.0 is the latest release covered by this skill. For new apps resolve the latest
stable SwiftPM release; fixed versions in tests identify evidence, not recommendations.

## Store encryption (CAP-03, CAP-16)

Load exactly 32 high-entropy bytes from the application's secure key store. Set
`config.encryptionKey = try DittoEncryptionKey.raw(keyBytes)` before
`try await Ditto.open(config: config)`. `keyBytes` can be `Data`; the key factory
accepts `ContiguousBytes`. `ditto.isEncrypted` reports the opened store's state.

Persist the same key outside the Ditto directory and supply it on every open. This
protects local documents and attachments, not authorization or data in transit. An
existing plaintext store cannot be encrypted by just reopening with a key; there is
no in-place rotation/conversion API. Plan export/recreation or re-sync with protection
for local unsynced changes. Do not delete a store as automatic error recovery.

Handle `DittoError.encryptionError(reason:)`: `.keyRequired`, `.keyUnexpected`,
`.keyInvalid`, `.unsupportedScheme`, `.metadataCorrupt`. The old passphrase reasons
are deprecated: `.passphraseNotGiven` → `.keyRequired`, `.extraneousPassphraseGiven`
→ `.keyUnexpected`, and `.passphraseInvalid` → `.keyInvalid`. Raw-key encryption
supersedes the experimental passphrase recipe.

## Deleting a store (CAP-05)

`try Ditto.deleteStore(databaseID: id, persistenceDirectory: directory)` deletes a
closed store. It fails when an instance holds the directory. Cancel consumers and
in-flight operations, stop sync and release **all** strong references before deleting.
Closing/releasing alone preserves data; deletion is a separate app retention decision.

**Published API discrepancy:** the 5.2 release notes advertise `Ditto.close()`, but
the shipped 5.2.0 public Swift interface and versioned API reference expose no such
instance method. Do not generate `ditto.close()` for 5.2.0. Releasing the last strong
reference remains the usable shutdown path. Data Stream handles have their own
`close()` methods; they are different types.

## Startup parameters (CAP-03, CAP-06)

Pass `systemParameters:` to `DittoConfig` before opening. Swift values are
`DittoSystemParameterValue`, a `Codable` enum with `.bool`, `.int64`, `.uint64`,
`.double`, `.string`, `.array` and `.object` cases; literals also work.
For example, `["transports_websocket_so_keepalive_idle_secs": .int64(60)]`.
The published `systemParameters:` initializer and `deleteStore` declarations carry
a `compiler(>=5.3)` guard; both compile with this skill’s Swift 6 toolchain.
Invalid names/types fail at open. Runtime `ALTER SYSTEM SET` remains available for
runtime settings; it cannot retroactively apply startup-only settings.

Data Streams use `ngn_data_streams_enabled: .bool(true)` and
`ngn_sync_enabled: .bool(false)` at open. The old `network_enable_ngn` and
`replication_over_ngn` names are deprecated aliases. Enabling NGN sync without NGN
streams now fails at sync start. Preview SPI/ownership rules still apply.

## Binding, observers and diagnostics (CAP-08, CAP-11, CAP-15)

Booleans from `JSONSerialization` arguments are now stored as booleans, not 0/1.
Most virtual-collection observers are change-driven; use an application timer if
periodic sampling is required. Reduced observer memory and unrelated-write work do
not remove handle ownership, ordered UI delivery or callback cleanup requirements.

Query `system:sync_degradations` to diagnose degraded documents; query
`system:support_bundles` and execute `system_request_support_bundle()` for local
support captures. See the `write-dql` skill or the public support-bundle guide.
Native WebSockets enable TCP keepalive by default; AWDL recovery is improved.

5.2 does not change the on-disk format from 5.1. Downgrades below 5.1 still need
5.0.2+ or 4.14.6+ as a bridge. Do not infer older releases can read raw-key-encrypted
stores; their API does not support this key form. Validate migration on copies.

Sources: [5.2 release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/swift),
[encryption guide](https://docs.ditto.live/sdk/latest/sync/encryption-at-rest),
[versioned Ditto API](https://software.ditto.live/swift/DittoSwift/5.2.0/api-reference/documentation/dittoswift/ditto),
[versioned config API](https://software.ditto.live/swift/DittoSwift/5.2.0/api-reference/documentation/dittoswift/dittoconfig),
and the published 5.2.0 XCFramework's `arm64-apple-macos.swiftinterface`.
