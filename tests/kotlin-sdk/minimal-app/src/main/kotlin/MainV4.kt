// 4.14.x reference flow — NOT COMPILABLE in this module: `live.ditto:ditto` is an
// Android-only AAR (no JVM artifact exists for 4.14.x). The runnable v4 harness is
// ../../android-app (executed on an Android emulator, API 35). This file is kept so
// the v4 call shape is visible next to MainV5.kt; the Gradle build excludes it.
//
// API shape below verified against the 4.14.7 AAR (javap) and by the android-app run:
//  - v4 identities take the dependencies object FIRST:
//    DittoIdentity.OfflinePlayground(dependencies, appId = ...)
//  - DefaultAndroidDittoDependencies(context) lives in package live.ditto.android
//  - ditto.disableSyncWithV3() is REQUIRED before any mutating DQL, else
//    DittoError.StoreError: "<dql> Unsupported feature: Encountered `INSERT`
//    statement. ... disable sync with V3 to use DQL"
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import live.ditto.DefaultDittoDependencies
import live.ditto.Ditto
import live.ditto.DittoIdentity

fun main() = runBlocking {
    val license = System.getenv("DITTO_OFFLINE_LICENSE")
        ?: error("DITTO_OFFLINE_LICENSE is not set")

    val persistenceDir = java.io.File(System.getProperty("user.dir"), "ditto-data")
    persistenceDir.deleteRecursively()  // deterministic output across runs
    persistenceDir.mkdirs()

    val dependencies = DefaultDittoDependencies(persistenceDir)
    val ditto = Ditto(
        dependencies,
        // v4 quirk (javap-verified): the identity captures the dependencies object.
        DittoIdentity.OfflinePlayground(dependencies, appId = "kotlin-minimal-app")
    )
    ditto.setOfflineOnlyLicenseToken(license)
    // Required before mutating DQL on 4.14.x — see versions.md / connect.md.
    ditto.disableSyncWithV3()
    ditto.startSync()

    val query = "SELECT * FROM cars"
    val subscription = ditto.sync.registerSubscription(query)

    val observed = Mutex(locked = true)
    val observer = ditto.store.registerObserver(query) { result ->
        val count = result.items.size
        println("observer: $count car(s)")
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
    println("read-back make: ${result.items.firstOrNull()?.value?.get("make")}")
    result.close()
    println("SDK version: ${ditto.sdkVersion}")

    observer.close()
    subscription.close()
    ditto.stopSync()
    ditto.close()
}
