# Reliability and delivery

Sources: <https://docs.ditto.live/sdk/latest/sync/data-streams>; the Kotlin 5.2.0 and
Swift 5.2.0 declarations; **executed** items come from the two-peer fixtures.

## Choosing a reliability mode

Every stream is **reliable** or **unreliable**, chosen when the topic is bound and again
when connecting; **both sides must agree** or the connection is rejected (executed:
`Failed to connect stream: Rejected(ConnectionRejected)` when connecting unreliable to a
reliable topic).

| Property | Reliable | Unreliable |
|---|---|---|
| Delivery | in order, or the connection fails | may be lost, reordered or duplicated |
| Latency | higher | lowest |
| Compression | optional LZ4 via `requestCompression` on connect | ignored |
| Fits | control messages, RPC, ordered file chunks, committed operations | continuous frames where the newest matters: audio, sensors, live previews |

- **Neither mode is once-only.** Design message handling to tolerate a repeat.
- Reliable is not "guaranteed": a gap breaks the connection rather than being skipped, and
  the app must then reconnect. It is also not a converging store; that is document sync.
- Reference-app pattern: the whiteboard binds **two topics** on every peer, an unreliable
  one for live stroke previews and a reliable one for committed operations and snapshots;
  the push-to-talk app uses one unreliable topic for audio frames and drops late frames.

## Send modes

Check the size first; a payload over `maxSendSize` is rejected. Then pick exactly one:

| Mode | Returns | Use when |
|---|---|---|
| `send(payload)` | the terminal `DittoSendStatus`, suspending until the message's lifecycle ends | you need to know how the send finished (executed: `Sent`) |
| `sendAndForget(payload)` | nothing, returns at once | high-rate, loss-tolerant frames (executed: delivered) |
| `send(payload) { operation -> … }` | whatever the block returns | backpressure or progress: poll `currentStatus`, `awaitStatusChange`, `cancel` |

The send operation is callback-scoped and closes when the block returns. `cancel` is
best-effort and saves bandwidth; it cannot guarantee the remote never sees the message.

### Statuses

`Unknown`, `Pending`, `Sent`, `Failed`, `Cancelled`. `Sent` means the payload was handed to
the local transport, **not** that the remote app processed it; for an application-level
acknowledgement send one back on the same stream. Treat `Unknown` as terminal for waiting
purposes; do not loop on it.

### Backpressure

Use the monitoring overload: hold the producer while the previous operation is `Pending`
and resume on `awaitStatusChange`. Keep per-peer queues **bounded** and drop the oldest
frame when a slow link cannot keep up; a fast producer must never grow an unbounded
buffer (<https://docs.ditto.live/sdk/latest/sync/data-streams>).

Reference-app caveat (push-to-talk): a stream torn down mid-send can leave an operation
`Pending` with no status change ever arriving, and `awaitStatusChange` is a non-cancellable
suspension over a native callback. That app polls `currentStatus` on a short deadline
inside the monitoring block and cancels on expiry, which ends the `send` call. Treat
this as a defensive pattern for live media, not as documented behaviour.

### `maxSendSize`

Read it from the open stream and enforce it before every send. Executed on the JVM
(Kotlin) and macOS (Swift) with 5.2.0: a reliable stream reported `4294967289`, far above
anything you would allocate, so do not treat the value as a promise that a payload of that
size fits in memory; 1 MiB payloads round-tripped on both, and a 4 GiB send on Swift
reported `failed` and then hung the stream. Frame large transfers yourself (the whiteboard chunks snapshots
with a content-addressed transfer id so a re-send after a failure is idempotent).

## Arguments

`connect(…, arguments)` sends initial bytes to the acceptor; the bind callback reads them
with `arguments()` / `arguments`. The bind side may answer with `open(arguments)`; the
connector reads that reply from its own candidate (executed on Kotlin 5.2.0:
`"hello"` arrived at the acceptor and `"welcome"` came back to the connector). Use them for
a protocol version or a session id, not for payload.

Executed defect to code around (Kotlin on the JVM, 5.0.3 through 5.2.0): when the
connector sent **no** arguments, the acceptor-side `arguments()` threw
`IllegalArgumentException` ("Arrays in Kotlin cannot be larger than …") instead of
returning `null`, and because it escaped the bind callback the candidate was never opened
and the connector timed out with `Rejected(HandshakeTimedOut)`. Swift returns `nil` as
documented. Guard the call, or only read arguments on topics whose protocol always sends them.

## Compression

`requestCompression = true` asks for LZ4 on a reliable stream and is ignored for unreliable
ones. Enable it only when the payload compresses well enough to pay for the CPU and latency
(the whiteboard enables it for its reliable topic only).
