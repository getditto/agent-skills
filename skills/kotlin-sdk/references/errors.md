# Error handling — Ditto Kotlin SDK

## Contents

- [CAP-16 Error handling](#cap-16-error-handling)
  - [The hierarchy](#the-hierarchy)
- [The failures you will actually hit](#the-failures-you-will-actually-hit)
- [Failures that are not `DittoException`](#failures-that-are-not-dittoexception)
- [`DittoPanicException` and crash reporters](#dittopanicexception-and-crash-reporters)
- [v4 → v5 mapping (condensed)](#v4--v5-mapping-condensed)
- [Retry, surface, or fail](#retry-surface-or-fail)

Everything here is the **v5** (5.0.x / 5.1.x) form; the v4 (`live.ditto:ditto`)
mapping is condensed at the bottom and [versions.md](versions.md) owns the full
per-line table.

Sources: <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4> — the **only** language migration
guide with an ERROR HANDLING / exception-taxonomy block — plus
<https://docs.ditto.live/sdk/latest/install-guides/kotlin> and <https://docs.ditto.live/sdk/latest/deployment/troubleshooting>.

## CAP-16 Error handling

Every SDK failure surfaces as a `DittoException`, a **sealed class**, so one `catch`
plus a `when` over the subclasses covers the whole taxonomy
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, AFTER block):

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
`when` over a second time. `FatalException`, `UnknownException`,
`UnsupportedException` and `DataStreamsException` carry only a message (no public
`reason` — **[source-verified]** `DittoException.kt`; the full subclass/`reason` table
below is confirmed against `com.ditto:ditto-kotlin-android:5.1.0`).

**Catch `DittoException`, not `Exception`, around suspend calls.** Every suspend
store API (`execute`, `executeRaw`, `collect`, `transaction`, `fetchAttachment`)
declares `kotlinx.coroutines.CancellationException` alongside `DittoException`
(5.1.0). A `catch (e: Exception)` — or `catch (t: Throwable)` — around
`store.execute` swallows coroutine cancellation and keeps a cancelled coroutine
running. If you must catch broadly, rethrow first:

```kotlin
try {
    ditto.store.execute(query, args)
} catch (e: CancellationException) {
    throw e                      // never swallow cancellation
} catch (e: DittoException) {
    // handle
}
```

### The hierarchy

Carried over from v4, renamed `*Error` → `*Exception`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, "Exception Hierarchy Changes"):

| Subclass | Payload |
|---|---|
| `DittoException.ActivationException` | `reason: ActivationExceptionReason` |
| `DittoException.AuthenticationException` | `reason: AuthenticationExceptionReason`; 5.2.0 adds `failureCode: AuthenticationFailureCode?` and `clientInfoJson: String?` |
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
<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>.)

### Missing expiration handler — `AuthenticationException`

`ditto.sync.start()` on a `DittoConfig.Connect.Server` instance throws
`DittoException.AuthenticationException` with reason `ExpirationHandlerMissing` if
`auth.expirationHandler` was not set **first**
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, AUTHENTICATION rules). The handler is a
property — `auth.expirationHandler = { ditto, t -> ... }` — and the lambda is already
`suspend`; see [connect.md](connect.md).

### `LIMIT` / `ORDER BY` in a subscription

`ditto.sync.registerSubscription()` with a `LIMIT` or `ORDER BY` clause fails with
`<dql> Unsupported feature: Limit or Order by`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). A subscription defines *what* to sync, not
display order — sort at query time.

### Non-string attachment metadata

`store.newAttachment(path, metadata)` accepts `Map<String, Any?>`, but the DQL
`INSERT INTO … ATTACHMENT` layer currently rejects non-String values at insert time
with ``attachment property `metadata` is invalid``. Stick to `Map<String, String>`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, which quotes the same error string; string
shape **[source-verified]** in `crates/ditto-types/src/attachment_handle.rs` — path
not re-verified in this review).

## Failures that are not `DittoException`

These throw plain JVM exceptions, so `catch (e: DittoException)` will **not** see them.

| Seen as | Cause | Fix |
|---|---|---|
| `IllegalStateException: Unable to find binary 'libdittoall.dylib' … include a ditto-binaries dependency` | **Executed** on 5.0.3/5.1.0: `DittoFactory.create()` on the **JVM** variant without a `com.ditto:ditto-binaries` classifier artifact on the runtime classpath | add `runtimeOnly("com.ditto:ditto-binaries:<version>:macos-arm64")` (or `linux-x64` / `linux-arm64` / `windows-x64`) — [testing.md](testing.md) |
| `IllegalStateException: Query result item has already been closed.` | a `DittoQueryResultItem` escaped its observer/`execute` handler — the result is a managed native resource, closed when the lambda returns (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>, OBSERVERS) | extract plain Kotlin data (`item.jsonString()`, typed accessors) **inside** the lambda; never return `result.items` |
| `java.lang.NoSuchMethodError: no static method "Lcom/ditto/internal/dittoffi/DittoFFI;.someNativeMethod(...)"` | release build minified without the Ditto keep rules (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>, Proguard — this is the guide's *illustrative* string, `someNativeMethod` is a placeholder). In 5.1.0 every transitive AAR ships consumer rules — `ditto-internal-*` keep `com.ditto.internal.**`, `ditto-cinterop-android` keeps `com.ditto.dittoffi.**` and `native <methods>`, `com.ditto:rustls` keeps `org.rustls.platformverifier.**` — so those packages survive R8 without any app-side rule. The one artifact with **no** consumer rules is `ditto-kotlin-android` itself, i.e. the public `com.ditto.kotlin.**` facade; a real crash would name a facade class (confirmed from the AARs' `proguard.txt`) | `-keep class com.ditto.** { *; }` (covers the facade) — the install guide's second line, `-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }`, duplicates the consumer rule already in the `rustls` AAR and is harmless to keep. Rules in [testing.md](testing.md) |
| `ClassCastException` from `doc.value["field"] as SomeType` | v5 `DittoQueryResultItem.value` is a `DittoCborSerializable.Dictionary`, not `Map<String, Any>` | use `.stringOrNull` / `.intOrNull` etc., or `item.jsonString()` |
| `java.lang.IllegalArgumentException` from `store.execute(query, mapOf(...))`, `registerSubscription(query, map)` or `presence.setPeerMetadata(map)` | the `Map<String, Any?>` overloads declare `IllegalArgumentException` (5.1.0) for a value the SDK cannot encode to CBOR/JSON (the exact rejected set is not enumerated in the docs — inference: arbitrary objects and non-String keys in nested maps) | pass primitives, Strings, Lists/Maps of those, `DittoAttachment`/`DittoAttachmentToken`, or pre-encode with `toDittoCborOrThrow()` / `toDittoJsonOrThrow()` so the failure is explicit |
| `kotlinx.coroutines.CancellationException` out of any suspend store call | the collecting scope was cancelled (ViewModel cleared, screen left) — not an SDK failure | let it propagate; never catch it as a generic `Exception` (see CAP-16 above) |

## `DittoPanicException` and crash reporters

A panic in the Rust core is bridged to Kotlin as `DittoException.DittoPanicException`;
read `nativeCrashMessage` and `nativeCrashStackTrace` for the native side of the
story. To verify your crash reporter (Crashlytics, Sentry, BugSnag) actually captures
native crashes, trigger one deliberately (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>):

```kotlin
DittoExperimental.triggerTestPanic()
```

Without uploaded native symbols the report is unreadable — the symbolication workflow
(`.so` path included) is in [testing.md](testing.md#crash-reporter-verification).

## v4 → v5 mapping (condensed)

Full table lives in [versions.md](versions.md). The mechanical rules
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>):

| v4.14 | v5.0 |
|---|---|
| `catch (e: DittoError)` | `catch (e: DittoException)` |
| `DittoError.StoreError` → `…AuthenticationError`, `…FatalError`, `…IoError`, `…PresenceError`, `…TransportError`, `…UnknownError`, `…UnsupportedError`, `…ValidationError`, `…ActivationError` | same names with `Exception` suffix (`StoreError` → `StoreException`, etc.) |
| `*ErrorReason` sealed classes | `*ExceptionReason` |
| `FilesystemError`, `InternalError`, `LockedWorkingDirectoryError` (all deprecated in v4) | **removed** — directory-lock failures are `StoreException(PersistenceDirectoryLocked)` |
| — | NEW: `SmallPeerInfoException`, `DataStreamsException`, `DittoPanicException` |

Compile-error breadcrumbs from the migration guide's build-fix list:
`Unresolved reference: DittoError` → replace with `DittoException`.

> **v4 doc-drift warning.** The Kotlin snippet on <https://docs.ditto.live/sdk/latest/deployment/troubleshooting>
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
| `IllegalStateException: Query result item has already been closed.` | a bug in your handler, not a runtime condition — fix the lifetime |
| `DittoPanicException` | capture `nativeCrashMessage` / `nativeCrashStackTrace` for a support ticket; not recoverable in-process |

Sync itself does not throw when the network is down. `sync.start()` succeeds offline
and Ditto reconnects on its own; observe connectivity through
`ditto.presence.observe()` and `ditto.transportCondition`, not through caught errors.
