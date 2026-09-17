# Error handling — Ditto Swift SDK

## CAP-16 Error handling

Every throwing Ditto API throws `DittoError`, a `Sendable` enum conforming to
`LocalizedError`. **Executed**: `errorDescription` and `localizedDescription` are
non-empty for a real failure.

```swift
do {
    try await ditto.store.execute(query: sql, arguments: arguments)
} catch let error as DittoError {
    switch error {
    case .storeError(let reason):          handle(reason)
    case .activationError(let reason):     handle(reason)
    case .authenticationError(let reason): handle(reason)
    case .validationError(let reason):     handle(reason)
    case .encryptionError(let reason):     handle(reason)
    case .ioError(let reason):             handle(reason)
    case .useAfterCloseError(let message):  assertionFailure(message)
    case .unsupportedError(let message), .unknownError(let message): report(message)
    @unknown default:                      report("\(error)")
    }
}
```

`DittoError` is a non-frozen enum from another module: an exhaustive `switch` needs
`@unknown default`. `.transportError` exists but is deprecated in 5.1.0.

## The cases you will actually hit

### `storeError(_:)`

| Reason | Thrown by | Meaning |
|---|---|---|
| `.queryInvalid(message:)` | `execute`, `registerObserver`, `registerSubscription` | the DQL does not parse |
| `.queryArgumentsInvalid` | the same | an argument value the SDK cannot encode |
| `.queryNotSupported(message:)` | `registerObserver` | the query is not a `SELECT`; on 4.14.x, also every mutating statement before `disableSyncWithV3()` |
| `.queryError(message:)` | `execute` | the statement parsed but failed |
| `.transactionReadOnly(message:)` | `transaction(isReadOnly: true)` | a mutation inside a read-only transaction |
| `.persistenceDirectoryLocked(message:)` | `Ditto.open` / `openSync` | another live instance holds that directory |
| `.documentNotFound` | attachment and document lookups | — |
| `.attachmentNotFound`, `.attachmentTokenInvalid`, `.failedToFetchAttachment`, `.attachmentFileNotFound`, `.attachmentFilePermissionDenied`, `.failedToCreateAttachment` | the attachment APIs | see [attachments.md](attachments.md) |

All of the first six are **executed** against a running SDK.

### `activationError(_:)`

`.licenseTokenVerificationFailed(message:)` (**executed**, from
`setOfflineOnlyLicenseToken` with a bad token), `.licenseTokenExpired(message:)`,
`.licenseTokenUnsupportedFutureVersion(message:)`, `.notActivatedError(message:)`.

`.licenseTokenExpired` is the one to surface to an operator rather than retry — an
offline-only fleet stops working when its token lapses and nothing else explains it.

### `authenticationError(_:)`

`.expirationHandlerMissing(message:)` — **executed**: `ditto.sync.start()` on a `.server`
instance with no `auth.expirationHandler` installed throws this. Install the handler
first ([connect.md](connect.md#cap-04-authentication-and-identity)).

`.failedToAuthenticate` — the credential was rejected. Retrying with the same token will
not help; get a new one.

### `validationError(_:)`

`.sizeLimitExceeded(message:)` (**executed**, from `smallPeerInfo.setMetadata` and
`presence.setPeerMetadata`), `.depthLimitExceeded`, `.notADictionary`,
`.notJSONCompatible`, `.invalidJSON`, `.invalidCBOR`, `.invalidDittoConfig`.

**The per-document size limit does not arrive here.** From 5.1.0 a document over
5 242 880 bytes fails the insert as `unknownError` whose message names the byte counts —
match on the message, not the case. On 4.14.6 and 5.0.3 it does not fail at all. See
[versions.md](versions.md#the-5-mib-per-document-limit-is-new-in-510).

### `encryptionError(_:)`

`.passphraseNotGiven`, `.passphraseInvalid`, `.extraneousPassphraseGiven` — all three from
opening a store whose encryption state does not match the config
([connect.md](connect.md#encryption-at-rest)).

### `ioError(_:)`

`.notFound`, `.permissionDenied`, `.alreadyExists`, `.operationFailed` — file-system
failures against the persistence directory or an attachment path.

## Errors you cannot catch

These are `fatalError`, so `try` and `catch` do nothing. They are API-misuse assertions,
and the fix is always in the calling code.

| Call | When it is fatal |
|---|---|
| `store.registerObserver`, `store.execute`, `store.fetchAttachment`, `sync.start` / `stop` / `isActive`, `sync.registerSubscription`, `presence.graph`, `smallPeerInfo.*` | the owning `Ditto` has been released. **v5 only** — 4.14.6 throws `useAfterCloseError` instead |
| `store.fetchAttachment(token:)` | the dictionary is not a real attachment token |
| `ditto.transportConfig = …` | Ditto Core rejects the configuration |
| `DittoDiffer.diff(_:)` | the diff result fails to decode (`try!`) |

The first row is the expensive one, and is why
[`SKILL.md` § Object lifetimes and retention](../SKILL.md#object-lifetimes-and-retention)
is promoted out of this file.

## Errors the SDK stopped producing

`DittoError.StoreErrorReason.invalidDocumentStructure(cbor:)` and
`.nonStringKeyInDocument(key:)` are deprecated in 5.1.0 and are **no longer emitted**
(#SDKS-4009). Do not write recovery paths for them. The `CBOR` enum they carry is
deprecated on the same ticket.

## Retry, surface, or fail

| Class | Do |
|---|---|
| `.queryInvalid`, `.queryArgumentsInvalid`, `.queryNotSupported`, `.transactionReadOnly` | fix the code — retrying is pointless |
| `.persistenceDirectoryLocked` | fix ownership — one instance per directory |
| `.licenseTokenExpired`, `.failedToAuthenticate`, `.expirationHandlerMissing` | surface to the operator or the auth flow; do not loop |
| `.ioError`, `.unknownError` from a transient write | retry with backoff, then surface |
| any `fatalError` in the table above | not recoverable at runtime — it is a bug |

Sync itself does not throw when the network is down. `sync.start()` succeeds offline and
Ditto reconnects on its own; connectivity is observed through the presence graph
([presence.md](presence.md)), not through caught errors.
