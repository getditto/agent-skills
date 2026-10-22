# Error handling — Ditto Kotlin SDK

Everything here is the **v5** (5.0.x / 5.1.x) form; the v4 (`live.ditto:ditto`)
mapping is condensed at the bottom and [versions.md](versions.md) owns the full
per-line table.

Sources: `sdk/latest/migration-guides/kotlin-v4` — the **only** language migration
guide with an ERROR HANDLING / exception-taxonomy block — plus
`sdk/latest/install-guides/kotlin` and `sdk/latest/deployment/troubleshooting`.

## CAP-16 Error handling

Every SDK failure surfaces as a `DittoException`, a **sealed class**, so one `catch`
plus a `when` over the subclasses covers the whole taxonomy
(`sdk/latest/migration-guides/kotlin-v4`, AFTER block):

```kotlin
try {
    ditto.sync.start()
} catch (e: DittoException) {
    when (e) {
        is DittoException.StoreException -> println(e.reason)
        is DittoException.AuthenticationException -> println(e.reason)
        else -> println(e.message)
    }
}
```

Most subclasses carry a typed `reason` — a `*ExceptionReason` sealed class you can
`when` over a second time. `FatalException`, `UnknownException` and
`UnsupportedException` carry only a message.

### The hierarchy

Carried over from v4, renamed `*Error` → `*Exception`
(`sdk/latest/migration-guides/kotlin-v4`, "Exception Hierarchy Changes"):

| Subclass | Payload |
|---|---|
| `DittoException.ActivationException` | `reason: ActivationExceptionReason` |
| `DittoException.AuthenticationException` | `reason: AuthenticationExceptionReason` |
| `DittoException.FatalException` | message |
| `DittoException.IoException` | `reason: IoExceptionReason` |
| `DittoException.PresenceException` | `reason: PresenceExceptionReason` |
| `DittoException.StoreException` | `reason: StoreExceptionReason` |
| `DittoException.TransportException` | `reason: TransportExceptionReason` |
| `DittoException.UnknownException` | message |
| `DittoException.UnsupportedException` | message |
| `DittoException.ValidationException` | `reason: ValidationExceptionReason` |

**New in v5** (same table):

| Subclass | Payload |
|---|---|
| `DittoException.SmallPeerInfoException` | `reason: SmallPeerInfoExceptionReason` (NEW reason class: `SizeLimitExceeded`, `DepthLimitExceeded`, `NotADictionary`) |
| `DittoException.DataStreamsException` | Data Streams API (preview) errors |
| `DittoException.DittoPanicException` | a native (Rust core) crash bridged to Kotlin; carries `nativeCrashMessage` and `nativeCrashStackTrace` |

All v4 `*ErrorReason` sealed classes were renamed `*ExceptionReason`
(`ActivationErrorReason` → `ActivationExceptionReason`, and likewise for
`Authentication`, `Io`, `Presence`, `Store`, `Transport`, `Validation`). Specific
reason changes worth branching on:

- `PresenceErrorReason.JsonParsingError(message)` → `PresenceExceptionReason.FailedToEncodeJson(cause)` — renamed **and** payload type changed.
- `StoreErrorReason.FailedToEncodeValue` → `StoreExceptionReason.FailedToEncodeValue(value, message, cause)` — extra params.
- NEW `StoreExceptionReason` entries: `AttachmentDataRetrievalError`, `AttachmentFileCopyError`, `CrdtError`, `DocumentContentEncodingFailed`, `FailedToDecodeData(cause, data)`, `FailedToGetDocumentData(path)`, `FailedToGetDocumentIDData(path)`, `InvalidDocumentStructure(cbor)`, `NonStringKeyInDocument(key)`.
- Removed: `TransportErrorReason.FailedToDecodeTransportDiagnostics`, `ValidationErrorReason.UnknownSyncScope`.
- Removed deprecated v4 exception types: `FilesystemError`, `InternalError`, `LockedWorkingDirectoryError` — the last one's cases surface in v5 as `StoreException` with reason `PersistenceDirectoryLocked`.

## The failures you will actually hit

Exact strings as they appear in a stack trace or logcat.

### Plain `INSERT` on an existing `_id` — arrives as `UnknownException`

**Executed** on 5.0.3 and 5.1.0:

```
DittoException$UnknownException: <dql> Query failed: ... Identifier conflict on document "car1": using FAIL conflict policy
```

`INSERT INTO cars DOCUMENTS (:doc)` uses the FAIL conflict policy by default, so
re-inserting an existing `_id` throws. Note the class: this is **not** a
`StoreException` — match on the message or, better, write the intent into the query:

```kotlin
ditto.store.execute(
    query = "INSERT INTO cars DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE",
    arguments = mapOf("doc" to mapOf("_id" to "car1", "color" to "blue")),
)
```

(`ON ID CONFLICT DO UPDATE` replaces the v4 `upsert` / `DittoWriteStrategy.Merge`;
`sdk/latest/migration-guides/kotlin-v4`.)

### Missing expiration handler — `AuthenticationException`

`ditto.sync.start()` on a `DittoConfig.Connect.Server` instance throws
`DittoException.AuthenticationException` with reason `ExpirationHandlerMissing` if
`auth.expirationHandler` was not set **first**
(`sdk/latest/migration-guides/kotlin-v4`, AUTHENTICATION rules). The handler is a
property — `auth.expirationHandler = { ditto, t -> ... }` — and the lambda is already
`suspend`; see [connect.md](connect.md).

### `LIMIT` / `ORDER BY` in a subscription

`ditto.sync.registerSubscription()` with a `LIMIT` or `ORDER BY` clause fails with
`<dql> Unsupported feature: Limit or Order by`
(`sdk/latest/migration-guides/kotlin-v4`). A subscription defines *what* to sync, not
display order — sort at query time.

### Non-string attachment metadata

`store.newAttachment(path, metadata)` accepts `Map<String, Any?>`, but the DQL
`INSERT INTO … ATTACHMENT` layer currently rejects non-String values at insert time
with `attachment property 'metadata' is invalid`. Stick to `Map<String, String>`
(`sdk/latest/migration-guides/kotlin-v4`).

## Failures that are not `DittoException`

These throw plain JVM exceptions, so `catch (e: DittoException)` will **not** see them.

| Seen as | Cause | Fix |
|---|---|---|
| `IllegalStateException: Unable to find binary 'libdittoall.dylib' … include a ditto-binaries dependency` | **Executed** on 5.0.3/5.1.0: `DittoFactory.create()` on the **JVM** variant without a `com.ditto:ditto-binaries` classifier artifact on the runtime classpath | add `runtimeOnly("com.ditto:ditto-binaries:<version>:macos-arm64")` (or `linux-x64` / `linux-arm64` / `windows-x64`) — [testing.md](testing.md) |
| `IllegalStateException: Query result item has already been closed` | a `DittoQueryResultItem` escaped its observer/`execute` handler — the result is a managed native resource, closed when the lambda returns (`sdk/latest/migration-guides/kotlin-v4`, OBSERVERS) | extract plain Kotlin data (`item.jsonString()`, typed accessors) **inside** the lambda; never return `result.items` |
| `java.lang.NoSuchMethodError: no static method "Lcom/ditto/internal/dittoffi/DittoFFI;.someNativeMethod(...)"` | release build minified without the Ditto keep rules (`sdk/latest/install-guides/kotlin`, Proguard) | `-keep class com.ditto.** { *; }` **and** `-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }` — rules in [testing.md](testing.md) |
| `ClassCastException` from `doc.value["field"] as SomeType` | v5 `DittoQueryResultItem.value` is a `DittoCborSerializable.Dictionary`, not `Map<String, Any>` | use `.stringOrNull` / `.intOrNull` etc., or `item.jsonString()` |

## `DittoPanicException` and crash reporters

A panic in the Rust core is bridged to Kotlin as `DittoException.DittoPanicException`;
read `nativeCrashMessage` and `nativeCrashStackTrace` for the native side of the
story. To verify your crash reporter (Crashlytics, Sentry, BugSnag) actually captures
native crashes, trigger one deliberately (`sdk/latest/install-guides/kotlin`):

```kotlin
DittoExperimental.triggerTestPanic()
```

Without uploaded native symbols the report is unreadable — the symbolication workflow
(`.so` path included) is in [testing.md](testing.md#crash-reporter-verification).

## v4 → v5 mapping (condensed)

Full table lives in [versions.md](versions.md). The mechanical rules
(`sdk/latest/migration-guides/kotlin-v4`):

| v4.14 | v5.0 |
|---|---|
| `catch (e: DittoError)` | `catch (e: DittoException)` |
| `DittoError.StoreError` → `…AuthenticationError`, `…FatalError`, `…IoError`, `…PresenceError`, `…TransportError`, `…UnknownError`, `…UnsupportedError`, `…ValidationError`, `…ActivationError` | same names with `Exception` suffix (`StoreError` → `StoreException`, etc.) |
| `*ErrorReason` sealed classes | `*ExceptionReason` |
| `FilesystemError`, `InternalError`, `LockedWorkingDirectoryError` (all deprecated in v4) | **removed** — directory-lock failures are `StoreException(PersistenceDirectoryLocked)` |
| — | NEW: `SmallPeerInfoException`, `DataStreamsException`, `DittoPanicException` |

Compile-error breadcrumbs from the migration guide's build-fix list:
`Unresolved reference: DittoError` → replace with `DittoException`.

> **v4 doc-drift warning.** The Kotlin snippet on `sdk/latest/deployment/troubleshooting`
> ("Setting the Logs to Debug Level") is still v4-shaped — `DefaultAndroidDittoDependencies`,
> `DittoIdentity.OnlinePlayground`, `DittoLogLevel.DEBUG`, `catch (e: DittoError)`. Do not
> copy it into a v5 app; the v5 equivalents are `DittoFactory.create(DittoConfig(...))`,
> `DittoLogLevel.Debug`, and `catch (e: DittoException)`.

## Retry, surface, or fail

| Class | Do |
|---|---|
| `ExpirationHandlerMissing`, `FailedToAuthenticate`-class auth failures | surface to the auth flow; retrying with the same token does not help |
| `UnknownException` "Identifier conflict … FAIL conflict policy" | fix the query (`ON ID CONFLICT …`); never retry as-is |
| `<dql> Unsupported feature: …` / query-parse failures | fix the code — retrying is pointless |
| `StoreException(PersistenceDirectoryLocked)` | fix ownership — one live instance per persistence directory |
| `IllegalStateException: Query result item has already been closed` | a bug in your handler, not a runtime condition — fix the lifetime |
| `DittoPanicException` | capture `nativeCrashMessage` / `nativeCrashStackTrace` for a support ticket; not recoverable in-process |

Sync itself does not throw when the network is down. `sync.start()` succeeds offline
and Ditto reconnects on its own; observe connectivity through
`ditto.presence.observe()` and `ditto.transportCondition`, not through caught errors.
