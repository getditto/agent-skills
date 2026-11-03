# Troubleshooting

Strings are as observed in the two-peer fixtures (Kotlin 5.2.0 on the JVM, Swift 5.2.0 on
macOS) unless marked docs. Kotlin raises `DittoException.DataStreamsException`; Swift throws
`DittoError.dataStreamsError(message:)`.

| Symptom | Cause | Fix |
|---|---|---|
| `Failed to connect stream: Rejected(HandshakeTimedOut)` | The remote never opened a candidate: the topic is not bound yet, the bind callback threw before `open`, or NGN is off on one side | Bind before connecting; retry with backoff; make the bind callback exception-free (wrap `arguments()`); enable NGN on both peers before creating `Ditto` |
| `Failed to connect stream: Rejected(ConnectionRejected)` | Reliability mismatch between connector and binding, **or** nobody has bound that topic on the remote (acceptor closed or never created) | Use the same `DittoReliability` on both sides; bind before connecting and keep the acceptor alive |
| `Failed to bind topic: Err(InvalidTopic)` | Topic outside `^[a-zA-Z0-9_ ]{1,15}$` (dash, 16+ chars, empty, non-ASCII) | Rename the topic |
| Second `bindTopic` on a bound topic fails | One acceptor per topic at a time | Close the previous acceptor first |
| `Attempted to use a DittoStreamCandidate after it was closed…` (Kotlin `DataStreamsException`, Swift `useAfterCloseError`) | A borrowed candidate used after its callback returned | Open inside the callback or `take()` it |
| Sends return `Sent` but nothing arrives | The receiver opened write-only (no receive callback), or it is on the other end of a stream you already replaced | Open with a receive callback; keep one stream per peer and topic |
| Messages arrive late, connection drops | Blocking work in the receive callback (driver thread) | Copy the payload, enqueue, return |
| Stream closed and never came back | Streams do not reconnect (docs) | Reconnect from your own loop with bounded backoff and jitter |
| New connects fail after you "restarted" the receiver | Closing the acceptor did not close its streams; or the topic is not rebound | Close streams explicitly; rebind |
| `IllegalArgumentException: Arrays in Kotlin cannot be larger than …` from `arguments()` (Kotlin on the JVM, 5.0.3–5.2.0) | Reading arguments when the connector sent none; Swift returns `nil` here | Guard the call; agree on always-present arguments |
| `DittoAcceptor.topic()` / `DittoStream.topic()` return garbage (Kotlin on the JVM, 5.0.3–5.2.0) | Observed defect; Swift's `topic` is correct | Key streams by your own `(peerKey, topic)`; `peerKeyString()` is correct |
| A multi-GiB send hangs or reports `Failed` | `maxSendSize` (observed `4294967289` on a reliable stream) is not an invitation | Frame transfers in small chunks; 1 MiB round-trips on both SDKs |
| Nothing works at all, no errors | NGN not enabled before `Ditto` was created | Set `network_enable_ngn` / `DITTO_NETWORK_ENABLE_NGN` before create; it cannot be changed at runtime |
| Document sync broke after enabling streams | `replication_over_ngn` differs between peers | Use the same value on every replicating peer; prefer `false` in the preview |
| Swift: crash on `sync.start()` in a debug build with NGN on | Stack overflow on a cooperative thread | Start sync on a dedicated large-stack thread |

Diagnose in this order: NGN enabled on both peers → sync started → presence shows the peer
→ topic bound (acceptor alive) → reliability matches → candidate opened inside the
callback → payload under `maxSendSize`.
