# Attachments — Ditto Kotlin SDK

For 5.2.0 additions and migration changes, read [sdk-5.2.md](sdk-5.2.md).


## Contents

- [CAP-12 Attachments](#cap-12-attachments)
  - [Creating](#creating)
  - [Storing it in a document](#storing-it-in-a-document)
  - [Fetching](#fetching)
  - [Reading the bytes — functions, not properties](#reading-the-bytes--functions-not-properties)
  - [Fetcher tracking](#fetcher-tracking)
  - [Updating](#updating)
  - [Deleting](#deleting)
  - [Sync behaviour](#sync-behaviour)
  - [v4 → v5 at a glance](#v4--v5-at-a-glance)

## CAP-12 Attachments

An attachment is created on the store, then stored *in* a document as a field. What comes
back out of a query is a **token**, not the bytes. Attachments carry large binary payloads
(images, PDFs, audio) outside the ~2 GB per-device key-value budget and the per-document
size limit; when to reach for one is `data-modeling`'s topic
(<https://docs.ditto.live/sdk/latest/crud/working-with-attachments>).

### Creating

```kotlin
import android.content.ContentResolver
import android.net.Uri
import com.ditto.kotlin.Ditto

val metadata = mapOf(
    "name" to "japan.png",
    "description" to "This is an image of a sunset in Japan."
)

// 1. From a file-system path — a plain (non-suspend) function.
ditto.store.newAttachment("/path/to/japan.png", metadata).use { attachment ->
    // ...
}

// 2. From an InputStream — `suspend`; call it from a coroutine. On Android this
//    is the overload for content:// URIs, which have no file path:
suspend fun attachFromUri(ditto: Ditto, resolver: ContentResolver, uri: Uri) {
    resolver.openInputStream(uri)?.use { input ->
        ditto.store.newAttachment(input, metadata).use { attachment ->
            // ...
        }
    }
}
```

`store.newAttachment(path: String, metadata)` is a plain function;
`store.newAttachment(inputStream: InputStream, metadata)` is **`suspend`** (both
confirmed against `com.ditto:ditto-kotlin-android:5.1.0` and the published API
reference; the docs page writes a single `attachmentPathOrInputStream` placeholder
and does not show the difference). Before 5.2.0 the metadata overloads take
`Map<String, Any?>` or `DittoCborSerializable.Dictionary`; 5.2.0 adds the preferred
`Map<String, String>` overloads described below. The
returned `DittoAttachment` is a `DittoResource` (`AutoCloseable`) — wrap it in
`.use { }` (the Java counterpart uses try-with-resources).

**Metadata — use `Map<String, String>`.** 5.2.0 adds string-valued overloads and
deprecates `Map<String, Any?>`; non-string values now throw `IllegalArgumentException`
at attachment creation. Earlier v5 releases could defer rejection until DQL insert.
Source: <https://docs.ditto.live/sdk/latest/release-notes-hub/kotlin>.

There is also a blocking counterpart, `store.newAttachmentBlocking(inputStream, metadata)`,
which in v5 only has the `DittoCborSerializable.Dictionary` metadata overload
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Storing it in a document

Pass the `DittoAttachment` itself as a DQL argument; declare the field as `ATTACHMENT` in
the statement — and when you declare types explicitly, the `COLLECTION` keyword is
mandatory:

```kotlin
ditto.store.newAttachment("/path/to/image.png", mapOf("name" to "image.png"))
    .use { attachment ->
        val document = mapOf("_id" to "123", "my_attachment" to attachment)

        // `my_attachment` must be declared ATTACHMENT; typed fields require COLLECTION.
        val insertQuery =
            "INSERT INTO COLLECTION docs (my_attachment ATTACHMENT) VALUES (:document)"
        ditto.store.execute(insertQuery, mapOf("document" to document))
    }
```

(<https://docs.ditto.live/sdk/latest/crud/working-with-attachments>)

### Fetching

Query the document first; the field you get back is an **attachment token** — a pointer
(`id` = content hash, `len` = blob length in bytes, `metadata`) — not the blob
(<https://docs.ditto.live/sdk/latest/crud/working-with-attachments>).

In v5, `DittoQueryResultItem.value` is a `DittoCborSerializable.Dictionary`, so read the
token with the typed accessor `.attachmentTokenOrNull` — the v4-style cast
`item.value["my_attachment"] as Map<String, Any>` **throws at runtime**
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

`fetchAttachment` is `suspend` and returns a `DittoAttachmentFetchResult` sealed class
with two cases, `Completed` (carries the `attachment`) and `Deleted` (the blob was removed
mid-fetch). Progress arrives through the optional
`onFetchProgress: suspend (ULong, ULong) -> Unit` callback — `(downloadedBytes,
totalBytes)`:

```kotlin
// executeRaw returns the DittoQueryResult for you to close — the plain
// execute(query) overload returns Unit and cannot be `.use`d (compile-verified 5.1.0).
ditto.store.executeRaw(
    query = """
        SELECT * FROM COLLECTION cars (my_attachment ATTACHMENT)
        WHERE _id = "123"
    """,
).use { result ->
    val token = result.items.first().value["my_attachment"].attachmentTokenOrNull
        ?: return@use

    // token is a DittoAttachmentToken — pass it to the `token =` overload.
    // (`tokenMap =` is a different overload taking Map<String, Any>; it does not
    // accept a DittoAttachmentToken — compile-verified 5.1.0.)
    val fetchResult = ditto.store.fetchAttachment(
        token = token,
        onFetchProgress = { downloadedBytes, totalBytes ->
            // Handle progress updates
        },
    )

    when (fetchResult) {
        is DittoAttachmentFetchResult.Completed ->
            fetchResult.attachment.use { attachment ->
                // Small blob: whole thing in memory. Large blob: see "Reading the bytes".
                val bytes: ByteArray = attachment.getData()
                // ...decode / display `bytes` here, inside the `use` block
            }
        is DittoAttachmentFetchResult.Deleted -> {
            // Attachment was deleted while fetching
        }
    }
}
```

(query shape and `when` from <https://docs.ditto.live/sdk/latest/crud/working-with-attachments> — note the docs
page still shows the v4-shaped `.use`-on-`execute` + `tokenMap` call, which does not
compile against v5; this sample follows the 5.1.0 signatures in
`DittoStore.kt` — **[source-verified, compile-verified]**, parameter names
`token` / `tokenMap` / `onFetchProgress` also confirmed against the published 5.1.0
API reference. `.attachmentTokenOrNull` from <https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>)

### Reading the bytes — functions, not properties

Byte access on a `DittoAttachment` is exposed as **functions**:
`attachment.getData(): ByteArray`, `attachment.getInputStream(): FileInputStream`
and `attachment.copyToPath(path: String)` (all three confirmed against
`com.ditto:ditto-kotlin-android:5.1.0`). `attachment.data` and
`attachment.inputStream` do **not** resolve as Kotlin properties and will not
compile (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

Pick by size. `getData()` loads the whole blob onto the JVM heap — fine for a
thumbnail, an OOM risk for the photos, PDFs and audio attachments exist for. For
anything large, stream it: `attachment.getInputStream().use { it.copyTo(output) }`
(e.g. into a `FileOutputStream` or a `ContentResolver` output stream on Android), or
`attachment.copyToPath(destinationPath)` to let the SDK copy the file for you. Do
the copy on `Dispatchers.IO`.

### Fetcher tracking

`store.attachmentFetchers` exposes the fetchers currently running (it exists in v4 too,
`@since 4.6.0` — **[source-verified]** `DittoStore.kt`; not new in v5). The
manual-lifecycle `DittoAttachmentFetcher` class still exists, but the suspend
`store.fetchAttachment()` form is preferred (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

### Updating

Attachments are immutable. Update the *document* to point at a new token:

```kotlin
ditto.store.execute(
    query = """
        UPDATE COLLECTION cars (my_attachment ATTACHMENT)
        SET my_attachment = :newAttachment
        WHERE _id = "123"
    """,
    arguments = mapOf("newAttachment" to newAttachment),
)
```

(<https://docs.ditto.live/sdk/latest/crud/working-with-attachments>)

### Deleting

There is no explicit delete API. Update the document to drop the token, or `EVICT` the
whole document; unreferenced blobs are garbage-collected on a ~10-minute cadence
(<https://docs.ditto.live/sdk/latest/crud/working-with-attachments>).

### Sync behaviour

Metadata syncs with the document; the blob syncs lazily over a separate protocol, and only
when a peer explicitly fetches it. A document holding a token can replicate through a mesh
while the blob stays behind — design for `fetchAttachment` needing a peer that actually
has the bytes (<https://docs.ditto.live/sdk/latest/crud/working-with-attachments>).

### v4 → v5 at a glance

| v4.14 | v5 |
|---|---|
| `store.fetchAttachment(token, callback)` returns `DittoAttachmentFetcher` | `suspend store.fetchAttachment(token, onFetchProgress?)` returns `DittoAttachmentFetchResult` |
| `DittoAttachmentFetchEvent` sealed class (`Progress`/`Completed`/`Deleted`) | `DittoAttachmentFetchResult` (`Completed`/`Deleted`); progress via the `onFetchProgress` callback |
| `DittoAttachmentFetchEventType` enum | **Removed** |
| `DittoCollection.newAttachment()` / `.fetchAttachment()` (deprecated) | **Removed** — use the `store.` forms |
| `store.newAttachment(path, Map<String, String>)` | 5.2.0: prefer the `Map<String, String>` overload. Earlier v5: `Map<String, Any?>`; that overload is deprecated in 5.2.0 and rejects non-string values at creation |
| Attachment/token metadata `Map<String, String>` | Object/token metadata uses `Map<String, Any?>` or `DittoCborSerializable.Dictionary`; 5.2.0 attachment creation requires string values despite this general representation |

(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>;
[5.2 Kotlin release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/kotlin))
