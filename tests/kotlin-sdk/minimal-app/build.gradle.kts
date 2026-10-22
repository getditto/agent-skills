// Minimal Ditto Kotlin SDK harness — JVM target (v5 only).
//
// Run a specific SDK version:
//   gradle run -PdittoLine=v5 -PdittoVersion=5.1.0
//   gradle run -PdittoLine=v5 -PdittoVersion=5.0.3
//
// 4.14.x is NOT runnable here: `live.ditto:ditto` is an Android-only AAR with no
// JVM artifact, so it cannot resolve on this target. The v4 leg lives in
// ../android-app (runs on an emulator).
//
// Requires DITTO_OFFLINE_LICENSE in the environment (the repo-root .env is NOT
// auto-loaded here; export it first).

val dittoLine: String by project
val dittoVersion: String by project

plugins {
    kotlin("jvm") version "2.3.21"
    application
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    when (dittoLine) {
        // v5: KMP root module; Gradle resolves the -jvm variant. The JVM
        // variant also needs the native binary for the host platform as an
        // explicit classifier (macos-arm64 | linux-x64 | linux-arm64 |
        // windows-x64); without it the SDK throws
        // "Unable to find binary 'libdittoall' ... on classpath".
        "v5" -> {
            implementation("com.ditto:ditto-kotlin:$dittoVersion")
            runtimeOnly("com.ditto:ditto-binaries:$dittoVersion:macos-arm64")
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
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
}

tasks.test {
    useJUnitPlatform()
    // The tests read the offline license from the environment.
    environment("DITTO_OFFLINE_LICENSE", System.getenv("DITTO_OFFLINE_LICENSE") ?: "")
}

application {
    mainClass.set("MainV5Kt")
}

// Each line's main imports packages that only exist in that line's artifact.
// MainV4.kt is excluded permanently: it documents the v4 shape for reference but
// cannot compile here (no v4 JVM artifact). The runnable v4 harness is
// ../android-app.
sourceSets {
    main {
        kotlin {
            exclude("MainV4.kt")
        }
    }
}
