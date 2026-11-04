// Minimal Ditto Kotlin SDK harness — JVM target (v5 only).
//
// Run a specific SDK version:
//   gradle run -PdittoVersion=5.2.0      (default when -PdittoVersion is omitted)
//   gradle run -PdittoVersion=5.1.0
//   gradle run -PdittoVersion=5.0.3
//
// 4.14.x is NOT runnable here: `live.ditto:ditto` is an Android-only AAR with no
// JVM artifact, so it cannot resolve on this target. The v4 leg lives in
// ../android-app (runs on an emulator).
//
// Requires DITTO_OFFLINE_LICENSE: read from the environment, else from the gitignored
// repo-root .env (copy .env-sample). Environment variables take precedence, matching
// tests/lib/load-env.mjs.

// Both properties default to the current line so `gradle run` works without -P flags.
val dittoLine: String = providers.gradleProperty("dittoLine").getOrElse("v5")
val dittoVersion: String = providers.gradleProperty("dittoVersion").getOrElse("5.2.0")

// The JVM variant loads its native library from a classifier jar; pick the host's.
// Published classifiers: macos-arm64 | linux-x64 | linux-arm64 | windows-x64 (no macos-x64).
val dittoBinariesClassifier: String = run {
    val os = System.getProperty("os.name").lowercase()
    val arch = System.getProperty("os.arch").lowercase()
    val isArm = arch == "aarch64" || arch == "arm64"
    when {
        os.contains("mac") && isArm -> "macos-arm64"
        os.contains("mac") -> error("Ditto $dittoVersion publishes no macos-x64 binaries; run on Apple silicon or Linux")
        os.contains("linux") && isArm -> "linux-arm64"
        os.contains("linux") -> "linux-x64"
        os.contains("windows") -> "windows-x64"
        else -> error("unsupported host for ditto-binaries: $os/$arch")
    }
}

plugins {
    kotlin("jvm") version "2.4.21"
    application
}

repositories {
    mavenCentral()
}

dependencies {
    // Align the SDK's transitive Java telemetry modules with the tracestate DoS fix.
    implementation(enforcedPlatform("io.opentelemetry:opentelemetry-bom:1.67.0"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
    when (dittoLine) {
        // v5: KMP root module; Gradle resolves the -jvm variant. The JVM
        // variant also needs the native binary for the host platform as an
        // explicit classifier (macos-arm64 | linux-x64 | linux-arm64 |
        // windows-x64); without it the SDK throws
        // "Unable to find binary 'libdittoall' ... on classpath".
        "v5" -> {
            implementation("com.ditto:ditto-kotlin:$dittoVersion")
            runtimeOnly("com.ditto:ditto-binaries:$dittoVersion:$dittoBinariesClassifier")
        }
        else -> error(
            "unknown dittoLine: $dittoLine — only 'v5' runs on JVM; " +
                "4.14.x is Android-only, see ../android-app"
        )
    }

    // Test stack — mirrors skills/kotlin-sdk/references/testing.md. kotlin("test")
    // is REQUIRED for kotlin.test.assertEquals; the kotlin("jvm") plugin does not
    // add it automatically.
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:6.1.3")
    // Use Jupiter's BOM to align the launcher with the engine on Gradle 9.
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}

// KEY=VALUE lines from the repo-root .env, used only for keys the environment lacks.
val dotEnv: Map<String, String> = rootDir.resolve("../../../.env").takeIf { it.isFile }   // repo root
    ?.readLines()
    ?.mapNotNull { line ->
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#") || '=' !in trimmed) null
        else trimmed.substringBefore('=').trim() to trimmed.substringAfter('=').trim().trim('"', '\'')
    }?.toMap() ?: emptyMap()
val offlineLicense: String = System.getenv("DITTO_OFFLINE_LICENSE") ?: dotEnv["DITTO_OFFLINE_LICENSE"] ?: ""
// Offline licenses are bound to a database ID; pass the matching one through (optional).
val databaseId: String? = System.getenv("DITTO_DATABASE_ID") ?: dotEnv["DITTO_DATABASE_ID"]

// DittoConfig.systemParameters exists from 5.2.0; the test that uses it compiles only there.
val isAtLeast52 = !dittoVersion.startsWith("5.0.") && !dittoVersion.startsWith("5.1.")
if (isAtLeast52) {
    sourceSets.test { kotlin.srcDir("src/test52/kotlin") }
}

tasks.test {
    useJUnitPlatform()
    environment("DITTO_OFFLINE_LICENSE", offlineLicense)
    databaseId?.let { environment("DITTO_DATABASE_ID", it) }
    // Data Streams (DataStreamsTest) run over NGN, which the native core enables from the
    // process environment at start-up — the JVM equivalent of Android's Os.setenv() in
    // Application.onCreate(). Set here so every Ditto instance in the test JVM gets it.
    environment("DITTO_NETWORK_ENABLE_NGN", "true")
    environment("DITTO_REPLICATION_OVER_NGN", "false")
    testLogging {
        events("passed", "failed", "skipped")
        showStandardStreams = true
    }
}

tasks.named<JavaExec>("run") {
    environment("DITTO_OFFLINE_LICENSE", offlineLicense)
    databaseId?.let { environment("DITTO_DATABASE_ID", it) }
}

application {
    mainClass.set("MainV5Kt")
}

