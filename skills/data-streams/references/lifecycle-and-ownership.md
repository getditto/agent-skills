# Lifecycle and ownership

Every Data Streams handle is a native resource the app owns. This file says which handle
lives how long, who closes it, and in what order. Sources: the Data Streams guide
(<https://docs.ditto.live/sdk/latest/sync/data-streams>), the Kotlin 5.2.0 and Swift 5.2.0
public declarations, and the two-peer fixtures in `tests/kotlin-sdk` and `tests/swift-sdk`
(items marked **executed**).

## The handles

| Handle | Produced by | Lives until | Who closes it |
|---|---|---|---|
| Endpoint (`ditto.dataStreams`) | the `Ditto` instance | `Ditto` closes | closing `Ditto` |
| Acceptor | `bindTopic` | you close it | **you**, when the topic should stop accepting |
| Candidate (borrowed) | the bind callback / the connect block | **the callback returns** | the SDK |
| Candidate (taken) | `take()` on a borrowed one | you close it | **you** |
| Stream | `open` on a candidate | you close it, or the remote closes | **you** (`closeSync` / `closeAndWait`, or `close`) |
| Inbound message | the receive callback | the callback returns | the SDK; copy `payload` out |
| Send operation | the monitoring `send` overload | the block returns | the SDK |

Closing the parent `Ditto` closes the endpoint and everything under it; do not touch the
handles afterwards (<https://docs.ditto.live/sdk/latest/sync/data-streams>).

## Acceptors

- One acceptor binds one topic. **A second bind of a bound topic fails** (executed); close
  the first acceptor before rebinding.
- Keep the acceptor reachable for as long as connections should be accepted. Dropping it
  stops new connections.
- **Closing the acceptor unbinds the topic but does not close the streams opened under it**
  (executed: a stream kept sending `Sent` after `acceptor.close()`, and a new connect to
  the topic then failed). An owner that holds both must close the streams itself.
- The bind callback is invoked **from a separate thread per call**, so the collection it
  writes into must be thread-safe (Kotlin KDoc; the guide says the same).

## Candidates and `take()`

A candidate is an *opportunity* to open a stream, scoped to the callback that delivered it.

- Open it **inside** the callback, or call **`take()`** to move ownership to a new wrapper
  you can use on another thread or coroutine. `take()` invalidates the original wrapper.
- Using the original after the callback returns throws (executed on both SDKs) with the
  message *"Attempted to use a DittoStreamCandidate after it was closed. Note that
  DittoStreamCandidate(s) are closed when exiting the closure that produced them unless you
  call `take()` on them."*: Kotlin as `DittoException.DataStreamsException`, Swift as
  `DittoError.useAfterCloseError`.
- **You must close a taken candidate**, or its native resource leaks. Closing it does not
  close a stream you already opened from it: the stream is parented to the endpoint.
- The **connector's** candidate (inside the connect block) is also borrowed: `connect`
  returns whatever the block returns and closes the candidate afterwards unless taken. Open
  it in the block; `connect` never opens it for you.

Bind-side candidates may pass **arguments** when opening (`MaySendArguments.Allowed`);
connect-side candidates may not (`Disallowed`), because the connector already sent its
arguments in `connect` (<https://docs.ditto.live/sdk/latest/sync/data-streams>). See
[reliability-and-delivery.md](reliability-and-delivery.md#arguments) for what each side
can read.

## Streams

- Retain each stream in one clear owner (a session object keyed by peer and topic).
  Replace an older stream for the same key by closing the old one.
- **Close deliberately.** `closeSync` (Kotlin) / `closeAndWait` (Swift) stops further sends,
  drains the queue and suspends until closed, returning `ClosedByLocal` (executed).
  The non-suspending `close` returns at once; queued sends still flush.
- **`waitUntilClosed` only observes** closure: it resumes when either side closes and
  returns why. It never initiates a close and can wait forever. The other side of a
  `closeSync` sees `ClosedByRemote` (executed). Use it to prune a stream from your map.
- A closed stream **never reconnects**. Open a new one from your own retry logic.

## Receive callback

The callback passed to `open` runs on the connection's **driver thread** to minimise latency
(Kotlin KDoc and the guide). Rules that follow:

- Copy the payload (`payload()` / `payload` returns an owned copy) and hand it to a
  bounded, non-blocking queue (`Channel.trySend`, `MutableSharedFlow.tryEmit`, an
  `AsyncStream` continuation). Return immediately.
- No blocking I/O, heavy decoding, database writes or UI work there; delays stall the
  connection and can time it out.
- Do not retain the inbound wrapper. Executed on the JVM: the thread was neither `main` nor
  a coroutine dispatcher worker.

## Shutdown order

Cancel connect/retry/monitor jobs → close streams (`closeSync`) → close acceptors → close
`Ditto` (<https://docs.ditto.live/sdk/latest/sync/data-streams>). Close concurrently when a
stuck stream must not starve the rest; finish the session's teardown before closing the
instance, and never race the two.
