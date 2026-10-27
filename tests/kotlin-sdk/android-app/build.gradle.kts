// Minimal Ditto Kotlin SDK harness — Android target, both version lines.
//
//   gradle installDebug -PdittoLine=v4 -PdittoVersion=4.14.7   (default)
//   gradle installDebug -PdittoLine=v5 -PdittoVersion=5.1.0
//   adb shell am start -n live.ditto.minimal/.MainActivity
//   adb logcat -d -s DittoMinimal:I
//
// `live.ditto:ditto` (4.14.x) is Android-only, so this module is the only way to execute
// the v4 line; the v5 leg here is what verifies the Android-specific v5 claims (handlers
// start on the main thread) that the JVM harness cannot. Each line has its own source
// set because the two APIs share no package.
//
// The license comes from -PdittoLicense, else DITTO_OFFLINE_LICENSE in the environment,
// else the gitignored repo-root .env. It is injected as a BuildConfig field and never
// written into the repository.

val dittoLine: String = providers.gradleProperty("dittoLine").getOrElse("v4")
val dittoVersion: String = providers.gradleProperty("dittoVersion")
    .getOrElse(if (dittoLine == "v4") "4.14.7" else "5.1.0")

val dotEnv: Map<String, String> = rootDir.resolve("../../../.env").takeIf { it.isFile }   // repo root
    ?.readLines()
    ?.mapNotNull { line ->
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#") || '=' !in trimmed) null
        else trimmed.substringBefore('=').trim() to trimmed.substringAfter('=').trim().trim('"', '\'')
    }?.toMap() ?: emptyMap()
val dittoLicense: String = providers.gradleProperty("dittoLicense").orNull
    ?: System.getenv("DITTO_OFFLINE_LICENSE") ?: dotEnv["DITTO_OFFLINE_LICENSE"] ?: ""
val dittoDatabaseId: String = providers.gradleProperty("dittoDatabaseId").orNull
    ?: System.getenv("DITTO_DATABASE_ID") ?: dotEnv["DITTO_DATABASE_ID"] ?: ""

plugins {
    id("com.android.application") version "9.4.1"
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    when (dittoLine) {
        "v4" -> implementation("live.ditto:ditto:$dittoVersion")
        // KMP root module; Gradle resolves the -android variant. No ditto-binaries needed.
        "v5" -> implementation("com.ditto:ditto-kotlin:$dittoVersion")
        else -> error("unknown dittoLine: $dittoLine (v4 | v5)")
    }
}
