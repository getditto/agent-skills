@file:OptIn(PreviewDataStreams::class)

import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.DittoSendStatus
import com.ditto.kotlin.PreviewDataStreams
import com.ditto.kotlin.open
import kotlinx.coroutines.channels.Channel
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

// 5.2.0+ only (this source set is compiled only for those versions): NGN enabled through
// DittoConfig.systemParameters instead of the process environment. The Gradle test task
// still sets DITTO_NETWORK_ENABLE_NGN for DataStreamsTest, so this test proves only that
// the systemParameters form is accepted and a stream works with it present — it cannot
// prove the environment variable was unnecessary. See tests/kotlin-sdk/README.md.
class DataStreamsSystemParametersTest {

    @TempDir lateinit var serverDir: File
    @TempDir lateinit var clientDir: File
    private val opened = mutableListOf<Ditto>()

    @AfterEach fun closeAll() { opened.reversed().forEach { it.sync.stop(); it.close() }; opened.clear() }

    private fun open(dir: File, configure: com.ditto.kotlin.transports.DittoTransportConfig.Builder.() -> Unit): Ditto {
        val ditto = DittoFactory.create(
            DittoConfig(
                databaseId = System.getenv("DITTO_DATABASE_ID") ?: "kotlin-data-streams",
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = dir.absolutePath,
                experimental = DittoConfig.Experimental(),
                encryptionKey = null,
                // The 5.2.0 way to enable NGN at open, no environment variable needed.
                systemParameters = mapOf("network_enable_ngn" to true, "replication_over_ngn" to false),
            )
        )
        ditto.setOfflineOnlyLicenseToken(System.getenv("DITTO_OFFLINE_LICENSE") ?: error("DITTO_OFFLINE_LICENSE not set"))
        ditto.updateTransportConfig { config -> config.peerToPeer.lan.enabled = false; config.configure() }
        ditto.sync.start()
        opened += ditto
        return ditto
    }

    @Test
    fun ngnFromSystemParametersCarriesAStream() = runBlocking<Unit> {
        val port = ServerSocket(0).use { it.localPort }
        val server = open(serverDir) { listen.tcp { enabled = true; interfaceIp = "127.0.0.1"; this.port = port } }
        val client = open(clientDir) { connect.tcpServers.add("127.0.0.1:$port") }
        val serverKey = server.presence.graph.localPeer.peerKey
        val clientKey = client.presence.graph.localPeer.peerKey
        withTimeout(30_000) {
            server.presence.observe().first { g -> g.remotePeers.any { it.peerKey == clientKey } }
            client.presence.observe().first { g -> g.remotePeers.any { it.peerKey == serverKey } }
        }
        val inbound = Channel<ByteArray>(Channel.UNLIMITED)
        server.dataStreams.bindTopic("sysparams") { candidate ->
            candidate.open { message -> inbound.trySend(message.payload()) }
        }.use {
            val stream = client.dataStreams.connect(peer = serverKey, topic = "sysparams", timeoutMs = 10_000) { it.open() }
            assertEquals(DittoSendStatus.Sent, stream.send("via systemParameters".toByteArray()))
            assertContentEquals("via systemParameters".toByteArray(), withTimeout(15_000) { inbound.receive() })
            stream.closeSync()
        }
    }
}
