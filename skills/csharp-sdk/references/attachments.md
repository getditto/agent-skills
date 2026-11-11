# Attachments

## CAP-12 Attachments

Source: [attachments](https://docs.ditto.live/sdk/latest/crud/working-with-attachments),
published DittoStore/DittoAttachmentFetchEvent APIs and the executed attachment test.

Create with `await ditto.Store.NewAttachmentAsync(path, metadata)`. Metadata is
Dictionary<string,string>, not Dictionary<string,object>. Insert the returned attachment
as a document field via a dictionary argument. After querying, pass the attachment
field's Dictionary<string,object> token to Store.FetchAttachment(token, callback).
The handle returned by NewAttachmentAsync is also disposable: retain it through the
awaited INSERT, then dispose it with using. Completed fetch attachments have a separate
ownership scope; disposing one handle does not replace disposing the other.

The callback receives Completed, Progress or Deleted subclasses. Completed.Attachment
provides Data(), Stream and CopyToPath; copy/read while it is alive and dispose it.
Keep the fetcher until completion; call Stop to abandon a pending fetch and dispose
the handle. There is no fetcher.Cancel method. Do not block the UI reading a large
attachment into a byte array; stream or copy on an appropriate worker path.

CopyToPath requires a destination that does not already exist. A save-file picker may
create the chosen file before returning it, so copying directly to that path can fail.
Copy to a unique temporary file in the destination directory, then move/replace it
after successful completion and the user's overwrite choice. On modern .NET,
File.Move(staging, destination, overwrite: true) supports this final replacement;
do not paste that overload into net48. Clean up staging files on failure/cancellation,
and keep the previous destination intact until the fetch/copy succeeds. The real-SDK
fixture verifies the existing-path failure, preserved old contents and staged replacement.

Treat synchronized attachment IDs and names as untrusted metadata, not filesystem paths.
For an Open/Share cache, generate a local unique directory and use a sanitized basename;
never derive the directory from the document ID or delete an arbitrary preexisting path.

Callbacks must handle errors without throwing across FFI and use a bounded completion
wait in tests. The local attachment round trip is executed. Physical-peer transfer,
interruption/retry and large-file memory behavior require separate tests before making
those additional guarantees.
