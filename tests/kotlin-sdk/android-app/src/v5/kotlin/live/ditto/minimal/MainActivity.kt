package live.ditto.minimal

import android.app.Activity
import android.os.Bundle
import android.os.Looper
import android.util.Log
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConfig
import com.ditto.kotlin.DittoFactory
import com.ditto.kotlin.DittoLogger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout

// v5 flow on Android: the same open → subscribe → observe → write → read-back as the
// JVM MainV5.kt, plus two probes the JVM cannot answer for Android —
//   1. which thread a registerObserver handler starts on (the skill says: main), and
//   2. whether `.flowOn(Dispatchers.IO)` moves an observe() transform (the skill says: no).
// A production app would hold Ditto in Application and use a ViewModel; this is a
// harness that runs once and exits, so it uses a bare thread and logs instead.
class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Thread { runBlocking { run() } }.start()
    }

    private suspend fun run() {
        val tag = "DittoMinimal"
        try {
            val persistenceDir = java.io.File(filesDir, "ditto-data")
            persistenceDir.deleteRecursively() // deterministic output across runs
            persistenceDir.mkdirs()
            DittoLogger.isEnabled = false

            // No Context parameter: the SDK obtains it through DittoInitializer (AndroidX Startup).
            val ditto = DittoFactory.create(
                DittoConfig(
                    databaseId = BuildConfig.DITTO_DATABASE_ID.ifEmpty { "kotlin-minimal-app" },
                    connect = DittoConfig.Connect.SmallPeersOnly(),
                    persistenceDirectory = persistenceDir.absolutePath,
                )
            )
            ditto.setOfflineOnlyLicenseToken(BuildConfig.DITTO_LICENSE)
            ditto.sync.start()

            val query = "SELECT * FROM cars"
            val subscription = ditto.sync.registerSubscription(query)

            val observed = CompletableDeferred<Unit>()
            val observer = ditto.store.registerObserver(query) { result ->
                val count = result.items.size
                val onMain = Looper.getMainLooper().isCurrentThread
                Log.i(tag, "observer: $count car(s) [thread=${Thread.currentThread().name} main=$onMain]")
                if (count > 0) observed.complete(Unit)
            }

            // Probe 2: the transform's thread, with flowOn(IO) applied downstream of observe().
            val transformThread = withTimeout(10_000) {
                ditto.store.observe(query) { _ -> Thread.currentThread().name }
                    .flowOn(Dispatchers.IO)
                    .first()
            }
            Log.i(tag, "observe() transform under flowOn(IO) ran on thread=$transformThread")

            ditto.store.execute(
                "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
                mapOf("car" to mapOf("_id" to "car1", "make" to "Toyota", "mileage" to 120))
            )

            withTimeout(10_000) { observed.await() }
            val make = ditto.store.execute(
                "SELECT * FROM cars WHERE _id = :id",
                mapOf("id" to "car1")
            ) { result -> result.items.firstOrNull()?.let { it.value["make"].stringOrNull } }
            Log.i(tag, "read-back make: $make")
            Log.i(tag, "SDK version: ${Ditto.VERSION}")

            observer.close()
            subscription.close()
            ditto.sync.stop()
            ditto.close()
            Log.i(tag, "EXIT=0")
        } catch (t: Throwable) {
            Log.e(tag, "EXIT=1 ${t.javaClass.name}: ${t.message}")
        }
    }
}
