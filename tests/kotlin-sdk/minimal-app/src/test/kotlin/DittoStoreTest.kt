import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.newSingleThreadContext
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.test.assertNotEquals
import kotlin.time.Duration.Companion.seconds
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

// Executed pattern for skills/kotlin-sdk/references/testing.md.
// Run: gradle test -PdittoLine=v5 -PdittoVersion=5.1.0
// (DITTO_OFFLINE_LICENSE must be in the environment.)
class DittoStoreTest {

    @TempDir
    lateinit var tempDir: File   // unique per test — two live instances on one
                                 // directory fail with a persistence-directory lock

    private fun makeDitto(): Ditto {
        val ditto = DittoFactory.create(
            DittoConfig(
                databaseId = System.getenv("DITTO_DATABASE_ID") ?: "test-database",  // license is per database ID
                connect = DittoConfig.Connect.SmallPeersOnly(),
                persistenceDirectory = tempDir.absolutePath,  // String? in v5, not File?
            )
        )
        // Never commit a license token — read it from the environment.
        ditto.setOfflineOnlyLicenseToken(
            System.getenv("DITTO_OFFLINE_LICENSE") ?: error("DITTO_OFFLINE_LICENSE not set")
        )
        return ditto
    }

    @Test
    fun insertThenReadBack() = runTest {
        val ditto = makeDitto()
        try {
            ditto.store.execute(
                query = "INSERT INTO cars DOCUMENTS (:doc)",
                arguments = mapOf("doc" to mapOf("_id" to "car1", "color" to "blue")),
            )
            val color = ditto.store.execute(
                query = "SELECT * FROM cars WHERE _id = :id",
                arguments = mapOf("id" to "car1"),
            ) { result -> result.items.first().value["color"].stringOrNull }
            assertEquals("blue", color)
        } finally {
            ditto.close()   // v5 classes implement DittoResource (AutoCloseable)
        }
    }

    // NOTE: runBlocking, not runTest. Ditto delivers observer events from real
    // background FFI threads, but runTest fast-forwards *virtual* time — a
    // withTimeout inside runTest expires before the write round-trips
    // (TimeoutCancellationException: "Timed out after 10s of _virtual_ time").
    // Observer tests need real time.
    @Test
    fun observerReportsTheWrite() = runBlocking {
        val ditto = makeDitto()
        try {
            val counts = ditto.store.observe("SELECT * FROM cars") { result ->
                result.items.size          // plain data only — items die with the lambda
            }
            ditto.store.execute(
                "INSERT INTO cars DOCUMENTS (:doc)",
                mapOf("doc" to mapOf("_id" to "car1")),
            )
            val seen = withTimeout(10_000) { counts.first { it == 1 } }
            assertEquals(1, seen)
        } finally {
            ditto.close()
        }
    }

    // The idiomatic alternative documented in references/testing.md: stay on runTest
    // but wait on a dispatcher that does not use the virtual-time scheduler, so the
    // timeout is real time. runTest's own `timeout` is real time as well.
    @Test
    fun observerReportsTheWriteUnderRunTest() = runTest(timeout = 30.seconds) {
        val ditto = makeDitto()
        try {
            val counts = ditto.store.observe("SELECT * FROM cars") { result -> result.items.size }
            ditto.store.execute("INSERT INTO cars DOCUMENTS (:doc)", mapOf("doc" to mapOf("_id" to "car1")))
            val seen = withContext(Dispatchers.Default) { withTimeout(10_000) { counts.first { it == 1 } } }
            assertEquals(1, seen)
        } finally {
            ditto.close()
        }
    }

    // references/concurrency.md: `.flowOn()` does not reach the observe() transform.
    // The transform runs inside the SDK-launched handler (SDK scope), not in the
    // callbackFlow producer that flowOn moves. A dedicated single thread makes the
    // check deterministic: if flowOn reached the transform, the thread name would match.
    @Test
    fun flowOnDoesNotReachTheObserveTransform() = runBlocking {
        val ditto = makeDitto()
        val probe = newSingleThreadContext("flowOn-probe")
        try {
            val threadNames = ditto.store.observe("SELECT * FROM cars") { _ -> Thread.currentThread().name }
                .flowOn(probe)
            val transformThread = withTimeout(10_000) { threadNames.first() }
            assertNotEquals("flowOn-probe", transformThread, "transform ran on the flowOn dispatcher")
            // On JVM the SDK scope is Dispatchers.Default — a shared-pool worker thread.
            assert(transformThread.startsWith("DefaultDispatcher-worker")) { "unexpected transform thread: $transformThread" }
        } finally {
            probe.close()
            ditto.close()
        }
    }
}
