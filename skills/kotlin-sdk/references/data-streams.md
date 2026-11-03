# Data Streams in Kotlin (preview)

How to express Ditto Data Streams in Kotlin, on Android and the JVM. Concepts, lifecycle
rules and design patterns live in the `data-streams` skill
(<https://docs.ditto.live/sdk/latest/sync/data-streams>); this file is the Kotlin spelling
and what the two-peer fixture `tests/kotlin-sdk/minimal-app/src/test/kotlin/DataStreamsTest.kt`
proved (**executed** on the JVM with 5.0.3, 5.1.0 and 5.2.0). Everything here is
**Public Preview** and may change without notice.

## Contents

- [Versions and opt-in](#versions-and-opt-in)
- [Enable NGN before `DittoFactory.create`](#enable-ngn-before-dittofactorycreate)
- [Receive: bind a topic](#receive-bind-a-topic)
- [Send: connect once, reuse the stream](#send-connect-once-reuse-the-stream)
- [Send modes and `maxSendSize()`](#send-modes-and-maxsendsize)
- [Closing](#closing)
- [Cancellation and reconnect](#cancellation-and-reconnect)
- [API surface](#api-surface)
- [Observed on the JVM](#observed-on-the-jvm)
- [Testing with two peers in one JVM](#testing-with-two-peers-in-one-jvm)

## Versions and opt-in

- The docs name **5.1.0** as the requirement and cover Android
  (<https://docs.ditto.live/sdk/latest/sync/data-streams>). The classes ship in 5.0.3 and the
  fixture passes there too (**executed**, JVM), but treat 5.1.0 as the supported floor.
- Every file that touches the API needs the opt-in, or the build fails with the
  `@RequiresOptIn` error:

  ```kotlin
  @file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)
  ```

- Imports: `com.ditto.kotlin.{Ditto, DittoAcceptor, DittoReliability, DittoSendStatus,
  DittoStream, DittoStreamCandidate, DittoStreamStatus, MaySendArguments}` and the
  **extension function** `com.ditto.kotlin.open` (forgetting that import is the usual
  "unresolved reference: open").

## Enable NGN before `DittoFactory.create`

Streams run over NGN, which is read once at start-up. Three forms:

```kotlin
// Android, all versions — Application.onCreate(), before the first DittoFactory.create():
import android.system.Os
Os.setenv("DITTO_NETWORK_ENABLE_NGN", "true", true)     // required
Os.setenv("DITTO_REPLICATION_OVER_NGN", "false", true)  // keep document sync on stable transports

// JVM, all versions — the process environment (a launcher script, Gradle `environment(...)`
// on the run/test task, or the container). System.setenv does not exist; set it outside.

// 5.2.0+, Android or JVM — at open, no environment variable:
val ditto = DittoFactory.create(
    DittoConfig(
        databaseId = "my-app",
        connect = DittoConfig.Connect.SmallPeersOnly(),
        persistenceDirectory = dir,
        experimental = DittoConfig.Experimental(),
        encryptionKey = null,
        systemParameters = mapOf("network_enable_ngn" to true, "replication_over_ngn" to false),
    )
)
```

The `systemParameters` constructor is 5.2.0+ (**executed** in
`src/test52/kotlin/DataStreamsSystemParametersTest.kt`). `replication_over_ngn` must match
on every peer that replicates documents with each other. Then `ditto.sync.start()`: presence
needs sync running. No TCP listener is required; if you change transports use
`ditto.updateTransportConfig { config -> … }`, never a fresh `DittoTransportConfig()`.

## Receive: bind a topic

One owner for the acceptor **and** every stream opened under it (closing the acceptor
does not close them, **executed**). Bind callbacks arrive on separate threads, so the map is
concurrent. Open inside the callback; the stream outlives the candidate.

```kotlin
@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)

class SensorReceiverSession(ditto: Ditto, private val onReading: (ByteArray) -> Unit) : AutoCloseable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val streams = ConcurrentHashMap<String, DittoStream>()

    private val acceptor: DittoAcceptor = ditto.dataStreams.bindTopic(
        topic = "sensor_data",                       // ^[a-zA-Z0-9_ ]{1,15}$
        reliability = DittoReliability.Reliable,
    ) { candidate ->
        val peer = candidate.peerKeyString()
        // Nothing may throw here: an unopened candidate times the connector out.
        val stream = candidate.open { inbound ->
            onReading(inbound.payload())             // driver thread: owned copy, hand off, return
        }
        streams.put(peer, stream)?.let { old -> scope.launch { old.closeSync() } }
        scope.launch { stream.waitUntilClosed(); streams.remove(peer, stream) }
    }

    override fun close() {
        acceptor.close()                             // stop accepting…
        val open = streams.values.toList(); streams.clear()
        scope.launch {                               // …then close what the acceptor did not
            open.map { launch { it.closeSync() } }.joinAll()
            scope.cancel()
        }
    }
}
```

`onReading` must be non-blocking (`Channel.trySend`, `MutableSharedFlow.tryEmit`). To open
elsewhere, `take()` the candidate and close the taken wrapper yourself:

```kotlin
ditto.dataStreams.bindTopic("sensor_data") { borrowed ->
    val owned = borrowed.take()                      // borrowed is dead after this callback
    scope.launch(Dispatchers.IO) {
        owned.use { candidate -> register(candidate.open { inbound -> sink.trySend(inbound.payload()) }) }
    }
}
```

The connector is suspended in `connect` until you open, so the deferred open must run
concurrently with it, not after it (**executed**: opening only after `connect` returned
deadlocked into `Rejected(HandshakeTimedOut)`).

## Send: connect once, reuse the stream

`connect` is `suspend`, takes a continuation and returns whatever it returns. It **lends**
the candidate; your block must open it. Named arguments: `requestCompression` sits between
`topic` and `reliability` positionally.

```kotlin
class SensorSenderSession private constructor(private val stream: DittoStream) : AutoCloseable {
    val maxSendSize: Long = stream.maxSendSize()

    suspend fun send(reading: ByteArray): DittoSendStatus {
        require(reading.size.toLong() <= maxSendSize) { "reading exceeds maxSendSize()" }
        return stream.send(reading)                  // Sent = handed to the transport, not processed
    }
    suspend fun closeAndWait() { stream.closeSync() }
    override fun close() { stream.close() }          // non-suspending; queued sends still flush

    companion object {
        suspend fun connect(ditto: Ditto, receiverPeerKey: String): SensorSenderSession =
            ditto.dataStreams.connect(
                peer = receiverPeerKey,              // from presence: peer.peerKey
                topic = "sensor_data",
                reliability = DittoReliability.Reliable,
                timeoutMs = 10_000,                  // 0 = Ditto's default of 10 s
            ) { candidate ->
                SensorSenderSession(candidate.open { inbound -> handleReply(inbound.payload()) })
            }
    }
}

val session = SensorSenderSession.connect(ditto, receiverPeerKey)
try { readings.collect { session.send(it) } }
finally { withContext(NonCancellable) { session.closeAndWait() } }
```

Get `receiverPeerKey` from `ditto.presence.graph.remotePeers` or `presence.observe()`, and
launch the connect from your own coroutine, never inside the presence callback.

## Send modes and `maxSendSize()`

```kotlin
val status: DittoSendStatus = stream.send(payload)            // suspend until terminal
stream.sendAndForget(payload)                                  // no status, least overhead
val terminal = stream.send(payload) { op ->                    // monitor / backpressure
    var s = op.currentStatus()
    while (s == DittoSendStatus.Pending) s = op.awaitStatusChange()
    s
}
```

All three **executed**: `send` and the monitoring form returned `Sent`; `sendAndForget`
delivered. Treat `Unknown` as terminal. `maxSendSize()` on a reliable JVM stream was
`4294967289` (**executed**), so check it but frame large transfers yourself. The
push-to-talk reference app polls `currentStatus()` on a deadline inside the monitoring
block because `awaitStatusChange()` is a non-cancellable suspension that may never fire
after a stream is torn down mid-send.

## Closing

- `closeSync()` suspends until closed and returns `ClosedByLocal`; the other end's
  `waitUntilClosed()` returns `ClosedByRemote` (**executed**).
- `close()` returns immediately; `waitUntilClosed()` only observes and may wait forever.
- Order: cancel jobs → `closeSync()` streams → `acceptor.close()` → `ditto.close()`.

## Cancellation and reconnect

Streams do not reconnect. Keep one connect loop per `(peerKey, topic)`:

```kotlin
suspend fun connectLoop(key: StreamKey) {
    var backoff = 500L
    while (currentCoroutineContext().isActive && peerVisible(key.peerKey) && !streams.containsKey(key)) {
        try {
            val stream = ditto.dataStreams.connect(peer = key.peerKey, topic = key.topic, timeoutMs = 10_000) {
                it.open { inbound -> enqueue(key, inbound.payload()) }
            }
            backoff = 500; registerAndWait(key, stream)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (e: DittoException.DataStreamsException) {
            currentCoroutineContext().ensureActive()   // 5.1.0 can wrap a cancellation in this type
            recordError(key.peerKey, e)
        }
        delay(backoff + Random.nextLong(0, minOf(250, backoff / 4)))
        backoff = minOf(backoff * 2, 10_000)
    }
}
```

Early connects fail with `Rejected(HandshakeTimedOut)` until the other side has bound and
opened; that is expected, not fatal. For two symmetric peers pick the connecting side by
peer-key order so only one stream exists per topic (whiteboard reference app).

## API surface

Package `com.ditto.kotlin`; entry point `ditto.dataStreams: DittoDataStreamsEndpoint`
(5.2.0 sources jar; identical declarations in 5.1.0).

| Type | Members |
|---|---|
| `DittoDataStreamsEndpoint` | `bindTopic(topic, reliability = Reliable, onNewCandidate): DittoAcceptor`; `suspend fun <T> connect(peer, topic, requestCompression = false, reliability = Reliable, timeoutMs = 0, arguments: ByteArray? = null, continuation: suspend (DittoStreamCandidate<Disallowed>) -> T): T` |
| `DittoAcceptor` | `topic()`, `reliability()`, `close()` |
| `DittoStreamCandidate<Args>` | `peerKeyString()`, `topic()`, `arguments()`, `take()`, `close()`; extension `open(...)`: bind-side (`Allowed`) `open(arguments: ByteArray? = null)` and `open(arguments, onReceive)`; connect-side (`Disallowed`) `open()` and `open(onReceive)` |
| `DittoStream` | `suspend send(payload): DittoSendStatus`; `suspend <T> send(payload, withSendOperation)`; `sendAndForget(payload)`; `peerKeyString()`; `topic()`; `maxSendSize(): Long`; `suspend waitUntilClosed()`; `suspend closeSync()`; `close()` |
| `DittoInbound` | `payload(): ByteArray` (owned copy) |
| `DittoSendOperation` | `currentStatus()`, `cancel()`, `suspend awaitStatusChange()` |
| `DittoReliability` | `Reliable`, `Unreliable` |
| `DittoStreamStatus` | `Open`, `ClosedByRemote`, `ClosedByLocal` |
| `DittoSendStatus` | `Unknown`, `Pending`, `Sent`, `Failed`, `Cancelled` |
| `DittoException.DataStreamsException` | every stream failure; `message` carries the reason, e.g. `Failed to connect stream: Rejected(ConnectionRejected)` |

## Observed on the JVM

All **executed** with 5.0.3, 5.1.0 and 5.2.0, same results on each:

- Reliability mismatch: `Failed to connect stream: Rejected(ConnectionRejected)`.
- Invalid topic (`has-dash`, 16 characters, empty, non-ASCII): `Failed to bind topic: Err(InvalidTopic)`;
  `"ok topic_15 abc"` binds.
- Second bind of a bound topic: `Failed to bind topic: Err(TopicAlreadyBound)`.
- Borrowed candidate used after its callback: `DataStreamsException` "Attempted to use a
  DittoStreamCandidate after it was closed…"; a `take()`n one works and must be closed.
- Arguments: `connect(arguments = "hello")` arrived at the acceptor; the acceptor's
  `open(arguments = "welcome")` was readable from the connector's candidate.
- **Defect:** acceptor-side `candidate.arguments()` with **no** arguments sent throws
  `IllegalArgumentException: Arrays in Kotlin cannot be larger than '2147483647'…` instead
  of returning `null`; left uncaught it kills the bind callback and the connector gets
  `Rejected(HandshakeTimedOut)`. Wrap it, or only read arguments on topics that always send them.
- **Defect:** `DittoAcceptor.topic()` and `DittoStream.topic()` return garbage bytes;
  `peerKeyString()` is correct. Key your maps by the topic you bound, not by reading it back.
- The receive callback ran on a thread that was neither `main` nor a coroutine dispatcher worker.

## Testing with two peers in one JVM

The fixture opens two instances with different persistence directories and the same
database ID, LAN discovery off, one listening on a TCP loopback port
(`config.listen.tcp { enabled = true; interfaceIp = "127.0.0.1"; port = p }`) and the other
dialling it (`config.connect.tcpServers.add("127.0.0.1:$p")`), with
`DITTO_NETWORK_ENABLE_NGN=true` on the Gradle test task. It waits for
`presence.observe()` to show the other peer on both sides before binding and connecting,
and retries `connect` a bounded number of times. Copy that shape for your own tests; a
single instance cannot stream to itself.
