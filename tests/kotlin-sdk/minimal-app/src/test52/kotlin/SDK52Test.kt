import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoEncryptionKey
import com.ditto.kotlin.DittoException
import com.ditto.kotlin.DittoFactory
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class SDK52Test {
    @TempDir lateinit var directory: File
    private val databaseId get() = System.getenv("DITTO_DATABASE_ID") ?: "test-database"
    private fun config(key: DittoEncryptionKey? = null) = DittoConfig(
        databaseId = databaseId, connect = DittoConfig.Connect.SmallPeersOnly(),
        persistenceDirectory = directory.absolutePath, encryptionKey = key,
        systemParameters = mapOf("transports_websocket_so_keepalive_idle_secs" to 60),
    )
    private fun open(config: DittoConfig = config()): Ditto = DittoFactory.create(config).also {
        it.setOfflineOnlyLicenseToken(System.getenv("DITTO_OFFLINE_LICENSE") ?: error("License required"))
    }

    @Test fun negativeMapArgumentsMatchLiterals() = runBlocking {
        open().use { ditto ->
            for (value in listOf(-5, Int.MIN_VALUE)) {
                ditto.store.execute("INSERT INTO numbers DOCUMENTS (:doc)",
                    mapOf("doc" to mapOf("_id" to value.toString(), "n" to value)))
                val matches = ditto.store.execute("SELECT * FROM numbers WHERE n = $value") { it.items.size }
                assertEquals(1, matches) // Literal query avoids a symmetric encode/decode false positive.
                val bound = ditto.store.execute("SELECT * FROM numbers WHERE n = :n", mapOf("n" to value)) { it.items.size }
                assertEquals(1, bound)

                // Seed with a DQL literal so a matching argument-encoding bug cannot
                // hide a typed-accessor decoding bug in a Kotlin round trip.
                ditto.store.execute("INSERT INTO literal_numbers DOCUMENTS ({'_id':'$value','n':$value})")
                val decoded = ditto.store.execute("SELECT * FROM literal_numbers WHERE _id = '$value'") {
                    it.items.single().value["n"].intOrNull
                }
                assertEquals(value, decoded, "Typed read must preserve the DQL negative literal")
            }
            val parameter = ditto.store.execute("SHOW transports_websocket_so_keepalive_idle_secs") {
                it.items.first().jsonString()
            }
            assertTrue(parameter.contains("60"))
        }
    }

    @Test fun encryptionAndDelete() = runBlocking {
        val key = DittoEncryptionKey.raw(ByteArray(32) { 0x51 }) // Test-only deterministic key.
        try {
            open(config(key)).use { ditto ->
                ditto.store.execute("INSERT INTO secret DOCUMENTS ({'_id':'one','value':'persisted'})")
                assertFailsWith<DittoException> { DittoFactory.deleteStore(databaseId, directory.absolutePath) }
            }
            assertFailsWith<DittoException.EncryptionException> { open() }
            val wrong = DittoEncryptionKey.raw(ByteArray(32) { 0x52 })
            try { assertFailsWith<DittoException.EncryptionException> { open(config(wrong)) } }
            finally { wrong.destroy() }
            open(config(key)).use { ditto ->
                assertEquals(1, ditto.store.execute("SELECT * FROM secret WHERE value = 'persisted'") { it.items.size })
            }
            DittoFactory.deleteStore(databaseId, directory.absolutePath)
            open().use { ditto ->
                assertEquals(0, ditto.store.execute("SELECT * FROM secret") { it.items.size })
            }
        } finally { key.destroy() }
    }

    @Test fun invalidStartupParametersFail() {
        assertFailsWith<DittoException> {
            DittoFactory.create(DittoConfig(databaseId = databaseId,
                connect = DittoConfig.Connect.SmallPeersOnly(), persistenceDirectory = directory.absolutePath,
                systemParameters = mapOf("not_a_ditto_system_parameter" to true)))
        }
    }

    @Suppress("DEPRECATION")
    @Test fun attachmentMetadataRequiresStrings() {
        val payload = File(directory, "payload.bin").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        open().use { ditto ->
            ditto.store.newAttachment(payload.absolutePath, mapOf("name" to "payload")).use { }
            assertFailsWith<IllegalArgumentException> {
                ditto.store.newAttachment(payload.absolutePath, mapOf<String, Any?>("count" to 3)).use { }
            }
        }
    }
}
