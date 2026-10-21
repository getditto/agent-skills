// Minimal Ditto Kotlin SDK harness — Android target (v4 line; live.ditto:ditto is
// Android-only, so this module is the only way to execute 4.14.x).
//
//   gradle installDebug -PdittoLicense="$DITTO_OFFLINE_LICENSE"
//   adb shell am start -n live.ditto.minimal/.MainActivity
//   adb logcat -d -s DittoMinimal:I
//
// The license is injected as a BuildConfig field from the -PdittoLicense property;
// it is never written to disk in the repo.

plugins {
    id("com.android.application") version "9.4.1"
}

android {
    namespace = "live.ditto.minimal"
    compileSdk = 35

    defaultConfig {
        applicationId = "live.ditto.minimal"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        debug {
            val license = providers.gradleProperty("dittoLicense").orElse("").get()
            buildConfigField("String", "DITTO_LICENSE", "\"$license\"")
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("live.ditto:ditto:4.14.7")
}
