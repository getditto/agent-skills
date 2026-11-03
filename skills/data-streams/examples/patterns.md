# Worked patterns

Language-agnostic designs. The first is the docs quickstart; the other two are how Ditto's
reference apps use Data Streams in production-shaped code. Code lives in the Kotlin and
Swift SDK skills' `references/data-streams.md`.

## Contents

- [Sensor telemetry: one topic, one direction](#sensor-telemetry-one-topic-one-direction)
- [Whiteboard: two topics, symmetric peers](#whiteboard-two-topics-symmetric-peers)
- [Push-to-talk audio: unreliable fan-out with deadlines](#push-to-talk-audio-unreliable-fan-out-with-deadlines)

## Sensor telemetry: one topic, one direction

From <https://docs.ditto.live/sdk/latest/sync/data-streams>.

- **Receiver session** owns the acceptor for `sensor_data` (reliable) and a thread-safe map
  `peer → stream`. In the bind callback: open the candidate with a receive callback that
  hands `payload` to a non-blocking sink, store the stream (closing any previous one for
  that peer), and spawn a watcher that removes the entry when `waitUntilClosed` returns.
  `close()` closes the acceptor **and then every stream**.
- **Sender session** connects **once** (`take()` the candidate so the stream outlives the
  connect block, then close the taken candidate), caches `maxSendSize`, and exposes
  `send(reading)` that checks the size and returns the status. Shutdown awaits
  `closeSync` in a non-cancellable context so it completes even when the caller is being
  cancelled.
- Discovery: the sender copies the receiver's peer key out of a presence observer and
  connects from a separate coroutine, retrying failures with capped exponential backoff and
  jitter.

## Whiteboard: two topics, symmetric peers

Every peer is both a receiver and a sender, so the design must avoid duplicate streams.

- **Topics:** `wb_live` **unreliable** for in-progress stroke previews (latest wins; a
  bounded queue drops the oldest), `wb_state` **reliable** with compression for committed
  operations, hello/digest exchange and snapshot chunks.
- **Role by key order:** each peer binds both topics; after presence shows a peer, only the
  side with the **lower** peer key runs a connect loop, the higher side only accepts. The
  acceptor also rejects candidates from peers it does not consider admitted (not visible,
  wrong protocol version, over capacity) by returning without opening.
- **Connect loop per (peer, topic):** try `connect` with a 10 s timeout, register the
  stream (closing any older one for the key), then `waitUntilClosed` and loop; on failure
  check the task is still active before retrying, sleep `min(backoff·2, 10 s)` plus jitter.
- **Late joiner:** on `wb_state` the peers exchange a hello with a digest of committed
  operations; a mismatch triggers a snapshot sent as sized chunks under `maxSendSize` with
  a content-addressed transfer id, so a re-send after a stream failure is idempotent.
- **Store use:** nothing about strokes is written to the Ditto store; only profile
  metadata rides on presence.

## Push-to-talk audio: unreliable fan-out with deadlines

- **Topic:** one **unreliable** topic for audio frames; the receiver checks
  `acceptor.reliability()` against its contract at start-up and fails fast on mismatch.
- **Receiver:** `take()` the candidate in the bind callback, hand it to an I/O coroutine
  that opens it with a receive callback feeding a `tryEmit` sink; a per-peer record tracks
  the stream and a disconnect watcher (`waitUntilClosed`) that clears it.
- **Sender:** one bounded channel and worker per peer; the worker reads `maxSendSize`,
  drops oversize frames, and uses the monitoring `send` overload with a **short deadline**:
  it polls `currentStatus` because a torn-down stream can leave the operation `Pending`
  forever and `awaitStatusChange` cannot be interrupted; on expiry it cancels and counts
  the frame as not delivered. Live audio prefers one lost frame to a stalled worker.
- **Observability:** every attempt is logged with delivered/not-delivered so offered versus
  confirmed frames can be compared offline; a separate reliable gossip stream shares link
  quality between peers.
