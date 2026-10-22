# Attachments — Ditto Kotlin SDK

## CAP-12 Attachments

An attachment is created on the store, then stored *in* a document as a field. What comes
back out of a query is a **token**, not the bytes. Attachments carry large binary payloads
(images, PDFs, audio) outside the ~2 GB per-device key-value budget and the per-document
size limit; when to reach for one is `data-modeling`'s topic
(sdk/latest/crud/working-with-attachments).

### Creating

```kotlin
val metadata = mapOf(
    "name" to "japan.png",
    "description" to "This is an image of a sunset in Japan."
)

ditto.store.newAttachment(attachmentPathOrInputStream, metadata).use { attachment ->
    // ...
}
```

`store.newAttachment(path, metadata)` takes a file path (or input stream) plus metadata
(sdk/latest/crud/working-with-attachments). The returned `DittoAttachment` is `Closeable` —
wrap it in `.use { }` (the Java counterpart uses try-with-resources).

**Metadata — stick to `Map<String, String>`.** The v5 signature accepts
`Map<String, Any?>` or `DittoCborSerializable.Dictionary`, but the DQL
`INSERT INTO … ATTACHMENT` layer currently only accepts **string-valued** metadata:
non-String values fail at insert time with `attachment property 'metadata' is invalid`
(sdk/latest/migration-guides/kotlin-v4). `Map<String, String>` satisfies both layers.

There is also a blocking counterpart, `store.newAttachmentBlocking(inputStream, metadata)`,
which in v5 only has the `DittoCborSerializable.Dictionary` metadata overload
(sdk/latest/migration-guides/kotlin-v4).

### Storing it in a document

Pass the `DittoAttachment` itself as a DQL argument; declare the field as `ATTACHMENT` in
the statement — and when you declare types explicitly, the `COLLECTION` keyword is
mandatory:

```kotlin
ditto.store.newAttachment(attachmentPathOrInputStream, mapOf("name" to "image.png"))
    .use { attachment ->
        val document = mapOf("_id" to "123", "my_attachment" to attachment)

        // `my_attachment` must be declared ATTACHMENT; typed fields require COLLECTION.
        val insertQuery =
            "INSERT INTO COLLECTION docs (my_attachment ATTACHMENT) VALUES (:document)"
        ditto.store.execute(insertQuery, mapOf("document" to document))
    }
```

(sdk/latest/crud/working-with-attachments)

### Fetching

Query the document first; the field you get back is an **attachment token** — a pointer
(`id` = content hash, `len` = blob length in bytes, `metadata`) — not the blob
(sdk/latest/crud/working-with-attachments).

In v5, `DittoQueryResultItem.value` is a `DittoCborSerializable.Dictionary`, so read the
token with the typed accessor `.attachmentTokenOrNull` — the v4-style cast
`item.value["my_attachment"] as Map<String, Any>` **throws at runtime**
(sdk/latest/migration-guides/kotlin-v4).

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
                val bytes = attachment.getData()   // ByteArray
            }
        is DittoAttachmentFetchResult.Deleted -> {
            // Attachment was deleted while fetching
        }
    }
}
```

(query shape and `when` from sdk/latest/crud/working-with-attachments — note the docs
page still shows the v4-shaped `.use`-on-`execute` + `tokenMap` call, which does not
compile against v5; this sample follows the 5.1.0 signatures in
`DittoStore.kt` — **[source-verified, compile-verified]**. `.attachmentTokenOrNull`
from sdk/latest/migration-guides/kotlin-v4)

### Reading the bytes — functions, not properties

Byte access on a `DittoAttachment` is exposed as **functions**. Use
`attachment.getInputStream().readBytes()` or `attachment.getData()` (returns `ByteArray`).
`attachment.data` and `attachment.inputStream` do **not** resolve as Kotlin properties and
will not compile (sdk/latest/migration-guides/kotlin-v4).

### Fetcher tracking

`store.attachmentFetchers` (new in v5) exposes the fetchers currently running. The
manual-lifecycle `DittoAttachmentFetcher` class still exists, but the suspend
`store.fetchAttachment()` form is preferred (sdk/latest/migration-guides/kotlin-v4).

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

(sdk/latest/crud/working-with-attachments)

### Deleting

There is no explicit delete API. Update the document to drop the token, or `EVICT` the
whole document; unreferenced blobs are garbage-collected on a ~10-minute cadence
(sdk/latest/crud/working-with-attachments).

### Sync behaviour

Metadata syncs with the document; the blob syncs lazily over a separate protocol, and only
when a peer explicitly fetches it. A document holding a token can replicate through a mesh
while the blob stays behind — design for `fetchAttachment` needing a peer that actually
has the bytes (sdk/latest/crud/working-with-attachments).

### v4 → v5 at a glance

| v4.14 | v5 |
|---|---|
| `store.fetchAttachment(token, callback)` returns `DittoAttachmentFetcher` | `suspend store.fetchAttachment(token, onFetchProgress?)` returns `DittoAttachmentFetchResult` |
| `DittoAttachmentFetchEvent` sealed class (`Progress`/`Completed`/`Deleted`) | `DittoAttachmentFetchResult` (`Completed`/`Deleted`); progress via the `onFetchProgress` callback |
| `DittoAttachmentFetchEventType` enum | **Removed** |
| `DittoCollection.newAttachment()` / `.fetchAttachment()` (deprecated) | **Removed** — use the `store.` forms |
| `store.newAttachment(path, Map<String, String>)` | `store.newAttachment(path, Map<String, Any?>)` — but see the metadata caveat above |
| Attachment/token metadata `Map<String, String>` | `Map<String, Any?>` or `DittoCborSerializable.Dictionary` on the object; string-only at the DQL layer |

(sdk/latest/migration-guides/kotlin-v4)
