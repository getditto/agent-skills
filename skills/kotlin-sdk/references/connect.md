# Connecting, authentication and lifecycle — Ditto Kotlin SDK

## Contents

- [CAP-03 Connecting: config, opening, persistence directory](#cap-03-connecting-config-opening-persistence-directory)
- [CAP-04 Authentication and identity](#cap-04-authentication-and-identity)
- [CAP-05 Lifecycle: start/stop sync, shutdown, ownership](#cap-05-lifecycle-startstop-sync-shutdown-ownership)

Everything here is the **5.x** form (`com.ditto:ditto-kotlin`, imports under
`com.ditto.kotlin.*`). The 4.14.x differences are tagged **v4** inline and
collected at the bottom of this file; broader version deltas live in
[versions.md](versions.md).

## CAP-03 Connecting: config, opening, persistence directory

Initialization is **four separate phases** — configure, initialize,
authenticate, start sync — not a constructor that does everything
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>):

```kotlin
import com.ditto.kotlin.*

// 1. Configure
val config = DittoConfig(
    databaseId = "your-database-id",
    connect = DittoConfig.Connect.Server(
        url = "REPLACE_ME_WITH_YOUR_CONNECT_URL"
    )
)

// 2. Initialize — NOT suspend, no coroutine needed
val ditto = DittoFactory.create(config)

// 3. Authenticate (see CAP-04)

// 4. Start sync
ditto.sync.start()
```

Details that cost a build or a support ticket if missed:

- **`DittoFactory.create(config)` is not a suspend function.** Calling it inside
  `launch {}` works but is unnecessary; there is no async "open" step.
- **`DittoConfig.Connect.Server(url: String)` takes a `String`,** not a
  `java.net.URI` — the class is nested inside `DittoConfig`. **v4:** it was
  `DittoConfigConnect.Server(url: URI)`, top-level.
- **The URL is the portal's *Connect via SDK* value copied verbatim** — an
  `https://` URL. Do not build it from the database ID, and do not paste a
  `wss://` value: you no longer need to add the cloud WebSocket URL to the
  transport config (it is inferred from `DittoConfig.Connect.Server.url`; the
  v4 `config.connect.websocketUrls.add(...)` workaround is unnecessary). The
  `Connect.websocketUrls` API itself still exists in v5 — see
  [transports.md](transports.md).
- **`DittoConfig` properties are immutable `val`s.** You cannot mutate the
  config after construction; pass a new one. `persistenceDirectory` is `String?`
  — **v4:** `File?`.
- **The default persistence directory includes the database ID:**
  `ditto-{databaseId}` on v5, versus plain `ditto` on v4. A v5 instance with no
  explicit `persistenceDirectory` **does** pick up a v4 store at the default
  location — the SDK passes a `legacyPersistenceDirectoryPath` fallback
  (`<defaultRoot>/ditto`) to the core (**[source-verified]**
  `InternalDittoFactory.kt`). Pass the old path explicitly only if v4 used a
  **custom** directory (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>):

  ```kotlin
  val ditto = DittoFactory.create(
      DittoConfig(
          databaseId = "your-database-id",
          connect = DittoConfig.Connect.Server(url = "REPLACE_ME_WITH_YOUR_URL"),
          persistenceDirectory = context.filesDir.resolve("ditto").absolutePath
      )
  )
  ```

  The resolved absolute path is readable as `ditto.absolutePersistenceDirectory`
  (v4's `ditto.persistenceDirectory` is removed).

### Offline-only instances

`DittoConfig.Connect.SmallPeersOnly(privateKey = null)` opens an instance with
no server connection (<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>). It needs an
offline license token before it will accept work — see
[CAP-04](#offline-license-token). An optional `privateKey` enables SharedKey
mesh authentication (see the v4 mapping table below).

### Android: no `Context` parameter

`DittoConfig` has **no `Context` parameter**. The SDK obtains the Android
application context itself through `DittoInitializer`, an AndroidX App Startup
initializer shipped in the SDK's manifest and applied by manifest merger.
**Remove any manual `DittoInitializer` entries from your `AndroidManifest.xml`**
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

"Autonomous context" does not mean "create it anywhere": hold the instance at
the **Application level** so exactly one survives for the app's lifetime
(<https://docs.ditto.live/sdk/latest/install-guides/kotlin>):

```kotlin
class MyApplication : Application() {
    lateinit var ditto: Ditto
        private set

    override fun onCreate() {
        super.onCreate()
        ditto = DittoFactory.create(
            DittoConfig(
                databaseId = BuildConfig.DITTO_DATABASE_ID,
                connect = DittoConfig.Connect.Server(url = BuildConfig.DITTO_URL)
            )
        )
        ditto.auth?.let { auth -> /* expirationHandler — see CAP-04 */ }
        ditto.sync.start()
    }
}
```

The install guide's warning is explicit: instantiating from an Activity's
`Context` risks the instance going out of scope or being garbage collected.

### JVM target

`com.ditto:ditto-kotlin` is a Kotlin Multiplatform artifact and publishes a
**JVM variant** in addition to Android (Gradle resolves the Android variant
automatically for an Android app — never write `com.ditto:ditto-kotlin-android`
yourself). On JVM there is no `DittoInitializer` and no `Context`; nothing else
about `DittoFactory.create` changes.

**Verified by execution (JVM, 5.1.0):** the JVM variant needs a platform
classifier runtime dependency or the SDK cannot load its native library:

```kotlin
// build.gradle.kts — pick the classifier for your platform
runtimeOnly("com.ditto:ditto-binaries:5.1.0:macos-arm64")
```

Classifiers: `macos-arm64` | `linux-x64` | `linux-arm64` | `windows-x64`.
Without one, `DittoFactory.create` throws:

```
IllegalStateException: Unable to find binary 'libdittoall.dylib' for Darwin ARM64
on classpath ... Make sure you've included a `ditto-binaries` dependency for the
correct platform.
```

**v4:** `live.ditto:ditto` is Android-only — there is no JVM variant.

## CAP-04 Authentication and identity

What the auth modes mean (playground vs. custom webhook vs. offline) is a
concept question — see
[Authentication and Authorization](https://docs.ditto.live/key-concepts/authentication-and-authorization).
This section is the Kotlin mechanics.

### `ditto.auth` is nullable

`ditto.auth` is `null` when the instance uses `DittoConfig.Connect.SmallPeersOnly`
and non-null for `Connect.Server`. Guard every access with `?.let { }`
(<https://docs.ditto.live/sdk/latest/install-guides/kotlin>).

### The expiration handler is a property holding a suspend lambda

```kotlin
ditto.auth?.let { auth ->
    auth.expirationHandler = { ditto, timeUntilExpiration ->
        // This lambda body IS suspend — call login() directly, no coroutine needed
        ditto.auth?.login(
            token = "your-token",
            provider = DittoAuthenticationProvider.development(),
        )
    }
}
ditto.sync.start()
```

`expirationHandler` receives `(ditto: Ditto, timeUntilExpiration: Double)`.
`timeUntilExpiration == 0.0` means initial authentication or an expired token;
`> 0` means the token expires soon — refresh
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>).

Three syntax rules, each a top v4→v5 migration failure:

- **It is a property assignment (`=`), not a method call.** There is no
  `setExpirationHandler()` and no invoke form — neither compiles.
- **Set it BEFORE `ditto.sync.start()`** when using `Connect.Server`. Starting
  sync without it throws `DittoException.AuthenticationException` with reason
  `ExpirationHandlerMissing`.
- **Never wrap the body in `launch { }`.** The lambda is already a suspend
  lambda; launching a child coroutine inside returns immediately and abandons
  the login. The wrong form:

  ```kotlin
  // WRONG — do not do this
  auth.expirationHandler = { ditto, t ->
      CoroutineScope(Dispatchers.IO).launch { ditto.auth?.login("...", provider) }
  }
  ```

### Login, providers, status, logout

- `auth.login(token, provider)` is **suspend** — no callback parameter. It
  returns the webhook's `clientInfo` JSON as a `String?` and throws
  `DittoException.AuthenticationException` on failure
  (<https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication>).
- Providers: `DittoAuthenticationProvider.development()` for portal playground
  tokens; `DittoAuthenticationProvider.custom("provider-name")` for a webhook
  provider registered in the portal. The string must match the provider **Name**
  in the portal (<https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication>).
- `auth.observeStatus()` returns `StateFlow<DittoAuthenticationStatus>` —
  collect it in a coroutine scope; the v4 status-change callback interface is
  removed.
- `auth.logout(cleanupFn: ((Ditto) -> Unit)?)` — the optional cleanup function
  is called **synchronously before logout completes** (`DittoAuthenticator.kt`
  KDoc — **[source-verified]**), receiving the `Ditto` instance in a state that
  is no longer authorized for writes but can still query and evict — the place
  to evict the signed-out user's data.

### Offline license token

For `Connect.SmallPeersOnly` deployments with no Ditto Server, activate with the
portal's offline license:

```kotlin
val ditto = DittoFactory.create(
    DittoConfig(
        databaseId = "your-database-id",
        connect = DittoConfig.Connect.SmallPeersOnly()
    )
)
ditto.setOfflineOnlyLicenseToken("REPLACE_ME_WITH_YOUR_OFFLINE_LICENSE")
```

**Verified by execution (JVM, 5.0.3 and 5.1.0):** the call succeeds and
`ditto.isActivated` reports true afterwards.

## CAP-05 Lifecycle: start/stop sync, shutdown, ownership

```kotlin
try {
    ditto.sync.start()
} catch (e: DittoException) {
    // handle error
}
ditto.sync.isActive   // true
ditto.sync.stop()
ditto.sync.isActive   // false
```

Only `sync.start()` declares `DittoException`; `sync.stop()` declares no checked
error (**[source-verified]** `DittoSync.kt`), so a try/catch around `stop()` can
never fire. **v4:** `ditto.startSync()` /
`ditto.stopSync()` / `ditto.isSyncActive`, catching `DittoError`.

Start sync in the top-most scope of the app and leave it on for the app's
lifetime (<https://docs.ditto.live/sdk/latest/sync/syncing-data>). Stopping sync pauses subscriptions and
disconnects from peers but does not close the local store — it is the switch
for a "work offline" mode, not instance teardown. On Android, the optional
`DefaultDittoForegroundService` (declared in the manifest) is automatically
started and stopped on `sync.start()`/`sync.stop()` so sync continues in the
background (<https://docs.ditto.live/sdk/latest/install-guides/kotlin>).

### Activation state

`ditto.isActivated` (v5) reports whether the instance is activated.
**v4:** the same value was `ditto.activated` — renamed.

### Shutdown

`Ditto` implements `DittoResource`, which extends `AutoCloseable`
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>): call `ditto.close()` when a
short-lived instance is done — test harnesses, CLI tools, a second per-user
instance. In an app you normally never call it: the instance is a singleton
held for the whole process lifetime and dies with the process. Only one live
instance may hold a given persistence directory at a time; `close()` is what
frees it for a subsequent open.

### Ownership

Create **once** and hold for the process:

- **Android:** a field on the `Application` subclass (see the CAP-03 sample) or
  a DI singleton. Never per-Activity — a destroyed Activity takes the instance,
  and the store with it.
- **JVM:** a lazily created singleton, e.g.:

  ```kotlin
  object DittoHolder {
      val ditto: Ditto by lazy {
          DittoFactory.create(config).also { d ->
              d.setOfflineOnlyLicenseToken(license)   // SmallPeersOnly only
              d.sync.start()
          }
      }
  }
  ```

### SDK version string

`Ditto.VERSION` is a companion `const` with the SDK version — use it in
diagnostic logging. **v4:** it was the instance property `ditto.sdkVersion`.

## v4 → v5 identity mapping (4.14.x reference)

v4 initialization mixed everything into a `Ditto(dependencies, identity)`
constructor with `live.ditto.android.DefaultAndroidDittoDependencies(context)` and a
`DittoIdentity` sealed class — all removed in v5
(<https://docs.ditto.live/sdk/latest/migration-guides/kotlin-v4>; package layout javap-verified at 4.14.7).
Note the v4 quirk that identities **capture the dependencies object**:
`DittoIdentity.OfflinePlayground(dependencies, appId = "…")` — the dependencies are
the first constructor argument, not optional (javap-verified, 4.14.7):

| v4 identity | v5 equivalent |
|---|---|
| `DittoIdentity.OnlinePlayground(deps, appId, token, …)` | `Connect.Server(url)` + `expirationHandler` + `login(token, .development())` |
| `DittoIdentity.OnlineWithAuthentication(deps, …)` | `Connect.Server(url)` + `expirationHandler` + `login(token, .custom("name"))` |
| `DittoIdentity.OfflinePlayground(deps, appId = "…")` | `Connect.SmallPeersOnly(privateKey = null)` + `setOfflineOnlyLicenseToken(token)` |
| `DittoIdentity.SharedKey(deps, appId = "…", sharedKey = …)` | `Connect.SmallPeersOnly(privateKey = sharedKey)` |
| `DittoIdentity.Manual(...)` | **Removed — no v5 equivalent** |

v4 also needed `config.connect.websocketUrls.add("wss://…")` and
`ditto.disableSyncWithV3()`; both are gone in v5 (cloud URL inferred from
`Connect.Server.url`, v3 sync disable removed). **Without `disableSyncWithV3()`,
mutating DQL on 4.14.x throws** ``DittoError.StoreError: <dql> Unsupported feature:
Encountered `INSERT` statement. … Please configure your app to disable sync with V3
to use DQL`` — executed on 4.14.7 (Android); `SELECT` and observers work without it.
See [versions.md](versions.md).
