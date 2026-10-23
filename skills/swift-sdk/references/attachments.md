# Attachments — Ditto Swift SDK

## CAP-12 Attachments

An attachment is created on the store, then stored *in* a document as a field. What comes
back out of a query is a **token**, not the bytes.

### Creating

```swift
// From memory — v5 only.
let attachment = try await ditto.store.newAttachment(
    data: imageData,
    metadata: ["name": "photo.jpg", "contentType": "image/jpeg"]
)

// From a file — available on every supported line.
let attachment = try await ditto.store.newAttachment(
    path: fileURL.path,
    metadata: ["name": fileURL.lastPathComponent]
)
```

`newAttachment(data:)` does not exist on 4.14.x — see
[versions.md](versions.md#store-results-and-errors). `path:` takes a **file-system path
`String`**, not a `URL`; pass `url.path`.

`DittoAttachment` exposes `id` (base64, unpadded), `len`, `metadata: [String: String]`,
`data() throws -> Data` and `copy(toPath:) throws`. Metadata values are `String`s only.

### Storing it in a document

```swift
try await ditto.store.execute(
    query: "INSERT INTO cars DOCUMENTS (:car)",
    arguments: ["car": ["_id": "car-1", "photo": attachment]]
)
```

Pass the `DittoAttachment` itself as an argument; the SDK encodes it as an attachment
token in the document.

### Fetching

In v5 the token in a query result is a plain `[String: Any]`. The `DittoAttachmentToken`
type is public on 4.14.x and **no longer public** in v5.

```swift
guard let token = item.value["photo"] as? [String: Any] else { return }

let fetcher = try ditto.store.fetchAttachment(token: token) { event in
    switch event {
    case .completed(let attachment):
        // attachment.data() / attachment.copy(toPath:)
    case .progress(let downloadedBytes, let totalBytes):
        // report progress
    case .deleted:
        // the attachment was removed while fetching
    @unknown default:
        break
    }
}
```

The token carries `id`, `len` and `metadata` keys.

`DittoAttachmentFetchEvent` is a non-frozen enum from another module, so an exhaustive
`switch` needs `@unknown default`.

**Only pass `fetchAttachment` a token read from a document's attachment field.** An
invalid token dictionary is not reported as a thrown error. Never construct a token by
hand, persist and replay one, or pass user-supplied JSON to `fetchAttachment`.

### Combine

`fetchAttachmentPublisher(attachmentToken:)` is the one place a Ditto Combine publisher is
the idiomatic answer, because progress reporting maps cleanly onto it:

```swift
let cancellable = ditto.store
    .fetchAttachmentPublisher(attachmentToken: token)
    .progress()
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { _ in },
        receiveValue: { progress in
            progressView.progress = progress.percentage   // also downloadedBytes / totalBytes
        }
    )
```

`.completed()` gives an `AnyPublisher<DittoAttachment, DittoError>` instead. Releasing the
`AnyCancellable` stops the underlying fetcher — the publisher's `Subscription.cancel()`
calls `fetcher.stop()`.

### Fetcher lifetime

`fetchAttachment` returns a `DittoAttachmentFetcher` and is `@discardableResult`. Retain
it until the fetch completes or you intentionally stop it, and call `stop()` to cancel.
`ditto.store.attachmentFetchers` is the set of fetchers currently running.

Unlike a store observer, a fetcher holds a `weak` reference to `Ditto`, so stopping one
after the `Ditto` instance is gone is a no-op.

### Size

Attachments are the mechanism for anything that would otherwise blow the per-document
size budget — which 5.1.0 enforces at 5 242 880 bytes
([versions.md](versions.md#the-5-mib-per-document-limit-is-new-in-510)). When to reach for
an attachment versus a field is `data-modeling`'s topic
(<https://docs.ditto.live/key-concepts>).
