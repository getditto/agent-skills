// Minimal Ditto Kotlin SDK harness — Android target, both version lines.
//
//   gradle installDebug -PdittoLine=v4 -PdittoVersion=4.14.7   (default)
//   gradle installDebug -PdittoLine=v5 -PdittoVersion=5.2.0   (v5 default)
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

// snippet:start kotlin-android-build
val dittoLine: String = providers.gradleProperty("dittoLine").getOrElse("v4")
val dittoVersion: String = providers.gradleProperty("dittoVersion")
    .getOrElse(if (dittoLine == "v4") "4.14.7" else "5.2.0")
// snippet:end kotlin-android-build

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

// AGP embeds an older KGP; select the build-cache security fix explicitly.
buildscript {
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
        // Security fixes for AGP's build-time dependency graph.
        classpath("com.google.guava:guava:33.7.2-jre")
        classpath("org.apache.commons:commons-lang3:3.21.0")
        classpath("org.bitbucket.b_c:jose4j:0.9.7")
        classpath("org.bouncycastle:bcprov-jdk18on:1.86")
        classpath("org.bouncycastle:bcpkix-jdk18on:1.86")
        classpath("org.bouncycastle:bcutil-jdk18on:1.86")
        classpath("org.jdom:jdom2:2.0.6.1")
    }
}

// snippet:start kotlin-android-build
plugins {
    id("com.android.application") version "9.5.0"
}
// snippet:end kotlin-android-build

// snippet:start kotlin-android-build
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
// snippet:end kotlin-android-build

// Lint resolves its own tool graph, separately from AGP's buildscript classpath.
// Keep the security fixes scoped to that graph, including all BC modules together.
configurations.matching { it.name == "androidLintTool" }.configureEach {
    resolutionStrategy.eachDependency {
        val patched = when ("${requested.group}:${requested.name}") {
            "com.google.guava:guava" -> "33.7.2-jre"
            "org.apache.commons:commons-lang3" -> "3.21.0"
            "org.apache.httpcomponents:httpclient" -> "4.5.14"
            "org.bouncycastle:bcprov-jdk18on",
            "org.bouncycastle:bcpkix-jdk18on",
            "org.bouncycastle:bcutil-jdk18on" -> "1.86"
            else -> null
        }
        if (patched != null) {
            useVersion(patched)
            because("Use mature versions with fixes for known security advisories")
        }
    }
}

// snippet:start kotlin-android-build
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
// snippet:end kotlin-android-build
