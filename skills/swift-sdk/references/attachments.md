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
**Executed on all three lines** via the file-backed path: `len` equals the byte count,
`metadata` round-trips, `id` is non-empty, and both `data()` and `copy(toPath:)` return
the original bytes.

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
type is **no longer public** — `public class` at
`sdk-release-4.14.6:cocoa/DittoSwift/Store/DittoAttachmentToken.swift:11` becomes bare
`final class` at `sdk-release-5.1.0:sdks/swift/DittoSwift/DittoAttachmentToken.swift:9`.

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

**Executed**: an in-memory attachment written into a document and fetched back through its
token delivers `.completed` with the original byte count. The token carries `id`, `len`
and `metadata` keys (**executed**).

`DittoAttachmentFetchEvent` is a non-frozen enum from another module, so an exhaustive
`switch` needs `@unknown default`.

**A malformed token is a crash, not an error.** `fetchAttachment(token:)` builds a
`DittoAttachmentToken` whose initializer calls `fatalError` when the dictionary is not a
real token
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoAttachmentToken.swift:33-38`, whose own
comment says it *"should ideally be made failable"*). **Observed** —
passing `["not": "a token"]` produced:

```
DittoSwift/DittoAttachmentToken.swift:35: Fatal error: Couldn't fetch attachment, passed
in attachment token dictionary representation is invalid: ["not": "a token"]
```

Take the token from the document. Never construct, persist and replay one, and never pass
user-supplied JSON to `fetchAttachment`.

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

Unlike a store observer, a fetcher holds a `weak` reference to `Ditto`
(`sdk-release-5.1.0:sdks/swift/DittoSwift/DittoAttachmentFetcher.swift:12`) and its
`stop()` routes back through the store, so stopping one after the `Ditto` instance is gone
is a no-op rather than a crash.

### Size

Attachments are the mechanism for anything that would otherwise blow the per-document
size budget — which 5.1.0 enforces at 5 242 880 bytes
([versions.md](versions.md#the-5-mib-per-document-limit-is-new-in-510)). When to reach for
an attachment versus a field is `data-modeling`'s topic
(<https://docs.ditto.live/key-concepts>).
