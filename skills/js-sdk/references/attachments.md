# Attachments

## CAP-12 Attachments

Create with `await store.newAttachment(bytes, metadata)` or a supported native file
path; metadata is a flat string-to-string map. Insert the Attachment itself as a DQL
argument. Read the resulting token from the document and use
`const fetcher = store.fetchAttachment(token)`; `await fetcher` resolves the data handle
(or null when unavailable/deleted). Keep the fetcher to `stop()` cancelled work.
Use `await attachment.data()` for bytes. The fixture round-trips bytes through a stored
token. Attachment data is fetched separately from document subscription.

`copyToPath` is native/Node only and throws in browsers. Native file picker URIs
(`content://`, temporary grants, security-scoped URLs) are not automatically filesystem
paths: resolve/copy into the app sandbox with the platform's file API first, or pass
bytes. Avoid base64-embedding large files inside documents and avoid loading unlimited
attachments into React state. Configure storage cleanup for exported copies separately.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
