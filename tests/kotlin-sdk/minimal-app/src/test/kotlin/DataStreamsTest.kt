@file:OptIn(PreviewDataStreams::class)

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoAcceptor
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoException
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.DittoReliability
import com.ditto.kotlin.DittoSendStatus
import com.ditto.kotlin.DittoStream
import com.ditto.kotlin.DittoStreamCandidate
import com.ditto.kotlin.DittoStreamStatus
import com.ditto.kotlin.MaySendArguments
import com.ditto.kotlin.PreviewDataStreams
import com.ditto.kotlin.open
import com.ditto.kotlin.transports.DittoTransportConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.ServerSocket
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

// Executed evidence for skills/data-streams and skills/kotlin-sdk/references/data-streams.md.
//
// Two Ditto peers run in this JVM: `server` listens on a TCP loopback port, `client`
// connects to it, both with LAN discovery off so the only link is the one under test.
// Data Streams run over NGN, which the Gradle test task enables through the
// DITTO_NETWORK_ENABLE_NGN environment variable (read by the native core at start-up).
//
// Run: gradle test -PdittoVersion=5.2.0 --tests DataStreamsTest
class DataStreamsTest {

    @TempDir lateinit var serverDir: File
    @TempDir lateinit var clientDir: File

    private val opened = mutableListOf<Ditto>()

    @AfterEach
    fun closeAll() {
        opened.reversed().forEach { it.sync.stop(); it.close() }
        opened.clear()
    }

    // ---- fixture ---------------------------------------------------------------

    private val databaseId = System.getenv("DITTO_DATABASE_ID") ?: "kotlin-data-streams"

    private fun open(dir: File, configure: DittoTransportConfig.Builder.() -> Unit): Ditto {
        val ditto = DittoFactory.create(
            DittoConfig(
                databaseId = databaseId,
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = dir.absolutePath,
            )
        )
        ditto.setOfflineOnlyLicenseToken(
            System.getenv("DITTO_OFFLINE_LICENSE") ?: error("DITTO_OFFLINE_LICENSE not set")
        )
        // Modify the current config — a fresh DittoTransportConfig() has every transport off.
        ditto.updateTransportConfig { config ->
            config.peerToPeer.lan.enabled = false   // loopback TCP is the only link under test
            config.configure()
        }
        ditto.sync.start()                           // presence needs sync running
        opened += ditto
        return ditto
    }

    private class Pair(val server: Ditto, val client: Ditto) {
        val serverKey: String get() = server.presence.graph.localPeer.peerKey
        val clientKey: String get() = client.presence.graph.localPeer.peerKey
    }

    private suspend fun connectedPair(): Pair {
        val port = ServerSocket(0).use { it.localPort }
        val server = open(serverDir) {
            listen.tcp { enabled = true; interfaceIp = "127.0.0.1"; this.port = port }
        }
        val client = open(clientDir) {
            connect.tcpServers.add("127.0.0.1:$port")
        }
        val pair = Pair(server, client)
        // Presence is the discovery mechanism: wait until each side sees the other.
        withTimeout(30_000) {
            server.presence.observe().first { g -> g.remotePeers.any { it.peerKey == pair.clientKey } }
            client.presence.observe().first { g -> g.remotePeers.any { it.peerKey == pair.serverKey } }
        }
        return pair
    }

    /** Presence does not prove the topic is bound yet: retry a failed connect, bounded. */
    private suspend fun <T> connectWithRetry(
        attempts: Int = 5,
        block: suspend () -> T,
    ): T {
        var last: Throwable? = null
        repeat(attempts) { n ->
            try {
                return block()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (e: DittoException) {
                last = e
                delay(200L * (n + 1))
            }
        }
        throw last!!
    }

    /** The receiving side: one acceptor plus the stream each peer opened. */
    private class Receiver(
        ditto: Ditto,
        topic: String,
        reliability: DittoReliability,
        openArguments: ByteArray? = null,
        readArguments: Boolean = false,
    ) : AutoCloseable {
        val inbound = Channel<ByteArray>(Channel.UNLIMITED)
        val receiveThreads = Channel<String>(Channel.UNLIMITED)
        val streams = Channel<DittoStream>(Channel.UNLIMITED)
        val arguments = Channel<Result<ByteArray?>>(Channel.UNLIMITED)
        val acceptor: DittoAcceptor = ditto.dataStreams.bindTopic(topic, reliability) { candidate ->
            // An exception escaping this callback leaves the candidate unopened and the
            // connector times out (HandshakeTimedOut) — see argumentsTravel… for why
            // arguments() is read inside runCatching.
            if (readArguments) arguments.trySend(runCatching { candidate.arguments() })
            // Open inside the callback; the stream outlives the candidate.
            val stream = candidate.open(arguments = openArguments) { message ->
                receiveThreads.trySend(Thread.currentThread().name)
                inbound.trySend(message.payload())   // owned copy; return fast
            }
            streams.trySend(stream)
        }
        override fun close() { acceptor.close() }
    }

    private suspend fun <T> within(ms: Long = 15_000, block: suspend () -> T): T = withTimeout(ms) { block() }

    // ---- claims ----------------------------------------------------------------

    @Test
    fun bytesRoundTripBothWaysOnOneReliableStream() = runBlocking<Unit> {
        val pair = connectedPair()
        Receiver(pair.server, "sensor_data", DittoReliability.Reliable).use { receiver ->
            val echoed = Channel<ByteArray>(Channel.UNLIMITED)
            val clientStream = connectWithRetry {
                pair.client.dataStreams.connect(
                    peer = pair.serverKey,
                    topic = "sensor_data",
                    reliability = DittoReliability.Reliable,
                    timeoutMs = 10_000,
                ) { candidate ->
                    // connect() lends the candidate; this block must open it (or take() it).
                    candidate.open { message -> echoed.trySend(message.payload()) }
                }
            }
            assertTrue(clientStream.maxSendSize() > 0)
            println("maxSendSize = ${clientStream.maxSendSize()}")
            // Accessors on the connector's stream (asserted separately in streamAccessors…).
            println("client stream topic() = '${clientStream.topic()}' peerKeyString() = '${clientStream.peerKeyString()}' (server = '${pair.serverKey}')")

            // Client -> server, twice on the same stream: connect once, reuse.
            assertEquals(DittoSendStatus.Sent, clientStream.send("reading-1".toByteArray()))
            assertEquals(DittoSendStatus.Sent, clientStream.send("reading-2".toByteArray()))
            assertContentEquals("reading-1".toByteArray(), within { receiver.inbound.receive() })
            assertContentEquals("reading-2".toByteArray(), within { receiver.inbound.receive() })

            // Server -> client on the same stream: the channel is symmetric.
            val serverStream = within { receiver.streams.receive() }
            println("server stream topic() = '${serverStream.topic()}' peerKeyString() = '${serverStream.peerKeyString()}' (client = '${pair.clientKey}')")
            assertEquals(DittoSendStatus.Sent, serverStream.send("ack".toByteArray()))
            assertContentEquals("ack".toByteArray(), within { echoed.receive() })

            // sendAndForget delivers too; it just reports nothing.
            clientStream.sendAndForget("reading-3".toByteArray())
            assertContentEquals("reading-3".toByteArray(), within { receiver.inbound.receive() })

            // The receive callback is not on a coroutine dispatcher or the main thread.
            val thread = within { receiver.receiveThreads.receive() }
            assertTrue(
                !thread.startsWith("DefaultDispatcher") && thread != "main",
                "onReceive ran on '$thread'"
            )

            // Monitoring overload: observe the status transitions to a terminal state.
            val terminal = clientStream.send("reading-4".toByteArray()) { operation ->
                var status = operation.currentStatus()
                while (status == DittoSendStatus.Pending) status = operation.awaitStatusChange()
                status
            }
            assertEquals(DittoSendStatus.Sent, terminal)

            // Closing: closeSync() on one side is ClosedByRemote on the other.
            assertEquals(DittoStreamStatus.ClosedByLocal, clientStream.closeSync())
            assertEquals(DittoStreamStatus.ClosedByRemote, within { serverStream.waitUntilClosed() })
        }
    }

    @Test
    fun argumentsTravelWithConnectAndWithOpen() = runBlocking<Unit> {
        val pair = connectedPair()
        Receiver(
            pair.server, "with_args", DittoReliability.Reliable,
            openArguments = "welcome".toByteArray(), readArguments = true,
        ).use { receiver ->
            val clientSeen = Channel<Result<ByteArray?>>(Channel.UNLIMITED)
            val stream = connectWithRetry {
                pair.client.dataStreams.connect(
                    peer = pair.serverKey,
                    topic = "with_args",
                    arguments = "hello".toByteArray(),
                    timeoutMs = 10_000,
                ) { candidate ->
                    clientSeen.trySend(runCatching { candidate.arguments() })
                    candidate.open()                 // write-only: no onReceive
                }
            }
            assertContentEquals("hello".toByteArray(), within { receiver.arguments.receive() }.getOrThrow())
            // The acceptor's open(arguments = …) reply is what the connector's candidate sees.
            val reply = within { clientSeen.receive() }
            println("connector-side candidate.arguments() -> $reply")
            assertContentEquals("welcome".toByteArray(), reply.getOrThrow())
            stream.closeSync()
        }
    }

    @Test
    fun readingAbsentArgumentsOnTheAcceptorSide() = runBlocking<Unit> {
        // Documented: arguments() returns null when the connector sent none. Observed on the
        // JVM: it throws IllegalArgumentException("Arrays in Kotlin cannot be larger than …")
        // from the FFI array-size conversion. Either way, never let it escape the callback.
        val pair = connectedPair()
        Receiver(pair.server, "no_args", DittoReliability.Reliable, readArguments = true).use { receiver ->
            val stream = connectWithRetry {
                pair.client.dataStreams.connect(peer = pair.serverKey, topic = "no_args", timeoutMs = 10_000) { it.open() }
            }
            val observed = within { receiver.arguments.receive() }
            println("acceptor-side candidate.arguments() with none sent -> $observed")
            observed.onSuccess { assertEquals(null, it) }
            observed.onFailure { assertTrue(it is IllegalArgumentException, "unexpected ${it::class}") }
            stream.closeSync()
        }
    }

    @Test
    fun reliabilityMustMatchTheBinding() = runBlocking<Unit> {
        val pair = connectedPair()
        Receiver(pair.server, "reliable_only", DittoReliability.Reliable).use {
            val failure = assertFailsWith<DittoException> {
                within(20_000) {
                    pair.client.dataStreams.connect(
                        peer = pair.serverKey,
                        topic = "reliable_only",
                        reliability = DittoReliability.Unreliable,
                        timeoutMs = 5_000,
                    ) { candidate -> candidate.open() }
                }
            }
            println("reliability mismatch -> ${failure::class.simpleName}: ${failure.message}")
        }
    }

    @Test
    fun aBorrowedCandidateDiesWithItsCallbackUnlessTaken() = runBlocking<Unit> {
        val pair = connectedPair()
        val leaked = Channel<DittoStreamCandidate<MaySendArguments.Allowed>>(Channel.UNLIMITED)
        val taken = Channel<DittoStreamCandidate<MaySendArguments.Allowed>>(Channel.UNLIMITED)
        val acceptor = pair.server.dataStreams.bindTopic("ownership") { borrowed ->
            leaked.trySend(borrowed)        // wrong: the wrapper closes when this returns
            taken.trySend(borrowed.take())  // right: ownership moves to the taken wrapper
        }
        acceptor.use {
            // connect() suspends until the acceptor opens the candidate, so the deferred open
            // must run concurrently with it — on another coroutine, as a real app would.
            val serverStreamDeferred = async {
                val owned = within { taken.receive() }
                assertEquals(pair.clientKey, owned.peerKeyString())   // usable outside the callback
                owned.use { it.open() }                                // …and closed by us
            }
            val clientStream = connectWithRetry {
                pair.client.dataStreams.connect(peer = pair.serverKey, topic = "ownership", timeoutMs = 10_000) {
                    it.open()
                }
            }
            val serverStream = within { serverStreamDeferred.await() }
            val borrowed = within { leaked.receive() }
            val useAfterClose = assertFailsWith<DittoException.DataStreamsException> { borrowed.peerKeyString() }
            assertTrue(useAfterClose.message!!.contains("after it was closed"), useAfterClose.message)

            assertEquals(DittoSendStatus.Sent, serverStream.send("late open".toByteArray()))
            serverStream.closeSync()
            clientStream.closeSync()
        }
    }

    @Test
    fun closingTheAcceptorUnbindsButLeavesOpenStreamsAlive() = runBlocking<Unit> {
        val pair = connectedPair()
        val receiver = Receiver(pair.server, "unbind", DittoReliability.Reliable)
        val clientStream = connectWithRetry {
            pair.client.dataStreams.connect(peer = pair.serverKey, topic = "unbind", timeoutMs = 10_000) { it.open() }
        }
        val serverStream = within { receiver.streams.receive() }

        receiver.close()   // acceptor.close(): the topic no longer accepts…
        // …but the stream opened under it keeps working.
        assertEquals(DittoSendStatus.Sent, clientStream.send("still open".toByteArray()))
        assertContentEquals("still open".toByteArray(), within { receiver.inbound.receive() })

        // A new connect to the unbound topic fails (bounded by its own timeout).
        assertFailsWith<DittoException> {
            within(20_000) {
                pair.client.dataStreams.connect(peer = pair.serverKey, topic = "unbind", timeoutMs = 5_000) { it.open() }
            }
        }
        clientStream.closeSync()
        serverStream.closeSync()
    }

    @Test
    fun topicsOutsideThePatternAreRejected() = runBlocking<Unit> {
        val server = open(serverDir) { }
        for (bad in listOf("has-dash", "sixteen_chars_ab", "", "émoji")) {
            val e = assertFailsWith<DittoException>("topic '$bad'") {
                server.dataStreams.bindTopic(bad) { }.close()
            }
            println("invalid topic '$bad' -> ${e::class.simpleName}: ${e.message}")
        }
        // Spaces, digits and underscores are allowed, up to fifteen characters.
        server.dataStreams.bindTopic("ok topic_15 abc") { }.close()
    }

    @Test
    fun payloadsLargerThanMaxSendSizeDoNotReportSent() = runBlocking<Unit> {
        val pair = connectedPair()
        Receiver(pair.server, "too_big", DittoReliability.Reliable).use { it ->
            val stream = connectWithRetry {
                pair.client.dataStreams.connect(peer = pair.serverKey, topic = "too_big", timeoutMs = 10_000) { it.open() }
            }
            val max = stream.maxSendSize()
            println("maxSendSize = $max")
            assertTrue(max > 0)
            if (max <= 64L * 1024 * 1024) {
                val outcome = runCatching { stream.send(ByteArray(max.toInt() + 1)) }
                outcome.onSuccess { status -> assertNotEquals(DittoSendStatus.Sent, status) }
                outcome.onFailure { e -> assertTrue(e is DittoException, "unexpected ${e::class}") }
                println("oversize send -> $outcome")
                // The stream itself survives for correctly sized payloads.
                assertEquals(DittoSendStatus.Sent, stream.send(ByteArray(max.toInt())))
            } else {
                // Observed on JVM 5.2.0: 4294967289 for a reliable stream — too large to allocate
                // here, so only a 1 MiB payload is exercised. Treat the value as "check before
                // sending", not as a promise that a payload of that size fits in memory.
                println("maxSendSize too large to probe; sending 1 MiB instead")
                assertEquals(DittoSendStatus.Sent, stream.send(ByteArray(1024 * 1024)))
                assertContentEquals(ByteArray(1024 * 1024), within { it.inbound.receive() })
            }
            stream.closeSync()
        }
    }

    @Test
    fun streamAccessorsReportTopicAndPeer() = runBlocking<Unit> {
        val pair = connectedPair()
        Receiver(pair.server, "accessors", DittoReliability.Reliable).use { receiver ->
            val clientStream = connectWithRetry {
                pair.client.dataStreams.connect(peer = pair.serverKey, topic = "accessors", timeoutMs = 10_000) { it.open() }
            }
            val serverStream = within { receiver.streams.receive() }
            val observed = mapOf(
                "client.topic" to clientStream.topic(), "client.peer" to clientStream.peerKeyString(),
                "server.topic" to serverStream.topic(), "server.peer" to serverStream.peerKeyString(),
                "acceptor.topic" to receiver.acceptor.topic(),
            )
            println("stream accessors -> $observed")
            assertEquals(pair.clientKey, serverStream.peerKeyString())
            assertEquals(pair.serverKey, clientStream.peerKeyString())
            // Documented: topic() returns the topic. Observed on the JVM (5.0.3, 5.1.0, 5.2.0):
            // DittoAcceptor.topic() and DittoStream.topic() return garbage bytes on both ends
            // (recorded above), so they are not asserted. Keep the topic in your own key, as the
            // reference apps do, instead of reading it back.
            for ((name, value) in observed) {
                if (name.endsWith("topic") && value != "accessors") println("DEFECT: $name = '$value' on ${Ditto.VERSION}")
            }
            clientStream.closeSync()
        }
    }

    @Test
    fun oneAcceptorPerTopicAtATime() = runBlocking<Unit> {
        val server = open(serverDir) { }
        val first = server.dataStreams.bindTopic("single") { }
        val second = runCatching { server.dataStreams.bindTopic("single") { } }
        println("second bind of the same topic -> $second")
        assertTrue(second.isFailure && second.exceptionOrNull() is DittoException, "second bind should fail")
        first.close()
        // After the first acceptor closes the topic can be bound again.
        server.dataStreams.bindTopic("single") { }.close()
        assertNotNull(first)
    }
}
