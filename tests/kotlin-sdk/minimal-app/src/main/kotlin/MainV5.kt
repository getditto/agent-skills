// Minimal Ditto Kotlin SDK program, v5 (JVM). Everything between the snippet markers is
// copied into the kotlin-sdk skill's examples/minimal-app.md by scripts/sync-snippets.py;
// CI fails if the copy drifts. Run: gradle run -PdittoVersion=5.1.0
// snippet:start kotlin-minimal-app
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.Ditto
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

fun main() = runBlocking {
    val license = System.getenv("DITTO_OFFLINE_LICENSE")
        ?: error("DITTO_OFFLINE_LICENSE is not set")
    // Offline licenses are issued per database ID; use the one the license was made for.
    val databaseId = System.getenv("DITTO_DATABASE_ID") ?: "kotlin-minimal-app"

    buildDir().deleteRecursively()  // deterministic output across runs
    com.ditto.kotlin.DittoLogger.isEnabled = false

    val ditto = DittoFactory.create(
        DittoConfig(
            databaseId = databaseId,
            connect = DittoConfig.Connect.SmallPeersOnly(),
            persistenceDirectory = buildDir().absolutePath,
        )
    )
    ditto.setOfflineOnlyLicenseToken(license)
    ditto.sync.start()

    val query = "SELECT * FROM cars"
    val subscription = ditto.sync.registerSubscription(query)

    val observed = Mutex(locked = true)
    val observer = ditto.store.registerObserver(query) { result ->
        val count = result.items.size
        println("observer: $count car(s)")
        if (count > 0) observed.unlock()
    }

    ditto.store.execute(
        query = "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
        arguments = mapOf("car" to mapOf("_id" to "car1", "make" to "Toyota", "mileage" to 120))
    )

    // Wait for the observer to fire, then verify with a read.
    launch {
        observed.withLock { }
        val make = ditto.store.execute(
            query = "SELECT * FROM cars WHERE _id = :id",
            arguments = mapOf("id" to "car1")
        ) { result -> result.items.firstOrNull()?.value?.get("make")?.stringOrNull }
        println("read-back make: $make")
        println("SDK version: ${Ditto.VERSION}")

        observer.close()
        subscription.close()
        ditto.sync.stop()
        ditto.close()
    }.join()
}

fun buildDir(): java.io.File =
    java.io.File(System.getProperty("user.dir"), "ditto-data").apply { mkdirs() }
// snippet:end kotlin-minimal-app
