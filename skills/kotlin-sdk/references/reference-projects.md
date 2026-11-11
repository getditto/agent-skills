# Reference Gradle projects — Kotlin

The build files of the two projects CI builds and runs for this skill, copied here
so they are available wherever the skill is installed. Use them with the rules in
[gradle-project-generation.md](gradle-project-generation.md); the versions in them are
validation baselines, so resolve current versions as [setup.md](setup.md) describes.

Both build files take `-PdittoLine` and `-PdittoVersion` so CI can run several SDK
versions from one project. A generated app needs only its own line and version.

The `build.gradle.kts` sections below leave out harness-only parts: reading the license
from the test repository's `.env` file and passing it to the test and run tasks. Read
the license from an environment variable or a Gradle property in your build, and never
commit it.

## Contents

- [JVM v5 project](#jvm-v5-project)
- [Android project](#android-project)

## JVM v5 project

A command-line JVM app on the v5 line, built with `gradle run`. Its program is in
[examples/minimal-app.md](../examples/minimal-app.md).

`settings.gradle.kts`:

<!-- snippet-file: tests/kotlin-sdk/minimal-app/settings.gradle.kts -->
<!-- Generated from tests/kotlin-sdk/minimal-app/settings.gradle.kts by scripts/sync-snippets.py. Edit the source, not this block. -->
```kotlin
rootProject.name = "ditto-kotlin-minimal-app"
```
<!-- /snippet -->

`build.gradle.kts` (add `tasks.test { useJUnitPlatform() }` to run JUnit 5 tests):

<!-- snippet: kotlin-jvm-build -->
<!-- Generated from tests/kotlin-sdk/minimal-app/build.gradle.kts by scripts/sync-snippets.py. Edit the source, not this block. -->
```kotlin
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

    // Test stack — mirrors the kotlin-sdk skill's testing reference. kotlin("test")
    // is REQUIRED for kotlin.test.assertEquals; the kotlin("jvm") plugin does not
    // add it automatically.
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:6.1.3")
    // Use Jupiter's BOM to align the launcher with the engine on Gradle 9.
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}

application {
    mainClass.set("MainV5Kt")
}
```
<!-- /snippet -->

## Android project

An Android app that builds either line (`-PdittoLine=v4|v5`). Its v5 leg was built with
AGP 9.4.1 at `compileSdk 36`.

`settings.gradle.kts`:

<!-- snippet-file: tests/kotlin-sdk/android-app/settings.gradle.kts -->
<!-- Generated from tests/kotlin-sdk/android-app/settings.gradle.kts by scripts/sync-snippets.py. Edit the source, not this block. -->
```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "ditto-kotlin-minimal-android-app"
```
<!-- /snippet -->

`gradle.properties`:

<!-- snippet-file: tests/kotlin-sdk/android-app/gradle.properties -->
<!-- Generated from tests/kotlin-sdk/android-app/gradle.properties by scripts/sync-snippets.py. Edit the source, not this block. -->
```properties
android.useAndroidX=true
android.nonTransitiveRClass=true
org.gradle.jvmargs=-Xmx4g
```
<!-- /snippet -->

`build.gradle.kts`. `dittoLicense` and `dittoDatabaseId` are build-time strings; the
harness reads them from `-PdittoLicense`/`-PdittoDatabaseId` or the
`DITTO_OFFLINE_LICENSE`/`DITTO_DATABASE_ID` environment variables:

<!-- snippet: kotlin-android-build -->
<!-- Generated from tests/kotlin-sdk/android-app/build.gradle.kts by scripts/sync-snippets.py. Edit the source, not this block. -->
```kotlin
val dittoLine: String = providers.gradleProperty("dittoLine").getOrElse("v4")
val dittoVersion: String = providers.gradleProperty("dittoVersion")
    .getOrElse(if (dittoLine == "v4") "4.14.7" else "5.2.0")

plugins {
    id("com.android.application") version "9.5.0"
}

// v5 AARs declare a minimum compileSdk of 36 (the install guide's value); the v4 leg
// keeps the 35 it was recorded with.
val sdkLevel: Int = if (dittoLine == "v4") 35 else 36

android {
    namespace = "live.ditto.minimal"
    compileSdk = sdkLevel

    defaultConfig {
        applicationId = "live.ditto.minimal"
        minSdk = 24
        targetSdk = sdkLevel
        versionCode = 1
        versionName = "1.0"
        // Declared in defaultConfig so every variant compiles; `assembleRelease` used to
        // fail with an unresolved BuildConfig.DITTO_LICENSE when this lived under `debug`.
        buildConfigField("String", "DITTO_LICENSE", "\"$dittoLicense\"")
        buildConfigField("String", "DITTO_DATABASE_ID", "\"$dittoDatabaseId\"")
        buildConfigField("String", "DITTO_VERSION", "\"$dittoVersion\"")
        // Optional: -PdittoAbi=arm64-v8a keeps only the emulator's ABI. The SDK bundles
        // four ABIs, which makes the debug APK ~220 MB and can exhaust a small image.
        providers.gradleProperty("dittoAbi").orNull?.let { abi -> ndk { abiFilters += abi } }
    }

    buildFeatures {
        buildConfig = true
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/$dittoLine/kotlin")
        }
    }
}

dependencies {
    // Align the v5 SDK's transitive telemetry modules with the tracestate DoS fix.
    implementation(enforcedPlatform("io.opentelemetry:opentelemetry-bom:1.67.0"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    when (dittoLine) {
        "v4" -> {
            implementation("live.ditto:ditto:$dittoVersion")
            // Keep the patched 2.18 line: 2.22's Kotlin module needs Android API 26
            // (MethodHandle.invokeExact), but this fixture must still build for API 24.
            implementation(enforcedPlatform("com.fasterxml.jackson:jackson-bom:2.18.12"))
        }
        // KMP root module; Gradle resolves the -android variant. No ditto-binaries needed.
        "v5" -> implementation("com.ditto:ditto-kotlin:$dittoVersion")
        else -> error("unknown dittoLine: $dittoLine (v4 | v5)")
    }
}
```
<!-- /snippet -->

`src/main/AndroidManifest.xml`:

<!-- snippet-file: tests/kotlin-sdk/android-app/src/main/AndroidManifest.xml -->
<!-- Generated from tests/kotlin-sdk/android-app/src/main/AndroidManifest.xml by scripts/sync-snippets.py. Edit the source, not this block. -->
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- No permissions are declared here: the SDK's merged manifest supplies the
         transport permissions, and this offline-only harness needs nothing else. -->
    <application android:label="Ditto Minimal">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```
<!-- /snippet -->
