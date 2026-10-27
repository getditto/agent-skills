package live.ditto.minimal

import android.app.Activity
import android.os.Bundle
import android.util.Log
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import live.ditto.android.DefaultAndroidDittoDependencies
import live.ditto.Ditto
import live.ditto.DittoIdentity

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

            val dependencies = DefaultAndroidDittoDependencies(applicationContext)
            val ditto = Ditto(
                dependencies,
                // v4 identities capture the dependencies object (javap-verified, 4.14.7)
                DittoIdentity.OfflinePlayground(dependencies, appId = "kotlin-minimal-app")
            )
            ditto.setOfflineOnlyLicenseToken(BuildConfig.DITTO_LICENSE)
            // 4.14.x gates mutating DQL on CRDT version V6, which requires opting out
            // of the legacy V3 sync protocol. Without this call, INSERT/UPDATE/DELETE
            // throw DittoError.StoreError:
            // "<dql> Unsupported feature: Encountered `INSERT` statement. Mutating DQL
            //  statements require that your application is updated to the latest
            //  version. Please configure your app to disable sync with V3 to use DQL"
            ditto.disableSyncWithV3()
            ditto.startSync()

            val query = "SELECT * FROM cars"
            val subscription = ditto.sync.registerSubscription(query)

            val observed = Mutex(locked = true)
            val observer = ditto.store.registerObserver(query) { result ->
                val count = result.items.size
                Log.i(tag, "observer: $count car(s)")
                if (count > 0) observed.unlock()
            }

            ditto.store.execute(
                "INSERT INTO cars DOCUMENTS (:car) ON ID CONFLICT DO UPDATE",
                mapOf("car" to mapOf("_id" to "car1", "make" to "Toyota", "mileage" to 120))
            )

            observed.withLock { }
            val result = ditto.store.execute(
                "SELECT * FROM cars WHERE _id = :id",
                mapOf("id" to "car1")
            )
            Log.i(tag, "read-back make: ${result.items.firstOrNull()?.value?.get("make")}")
            result.close()
            Log.i(tag, "SDK version: ${ditto.sdkVersion}")

            observer.close()
            subscription.close()
            ditto.stopSync()
            ditto.close()
            Log.i(tag, "EXIT=0")
        } catch (t: Throwable) {
            Log.e(tag, "EXIT=1 ${t.javaClass.name}: ${t.message}")
        }
    }
}
