allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// snippet:start flutter-android-compilesdk-override
// ditto_live 5.1.0 and 5.2.0: the plugin compiles with compileSdk 34, but the
// com.ditto Android libraries it depends on require compileSdk 36, and AGP 9
// checks this per library module. Raise the plugin's compileSdk. afterEvaluate
// runs after the plugin's own build script; keep this block above the
// evaluationDependsOn(":app") block below.
subprojects {
    afterEvaluate {
        if (name == "ditto_live") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
    }
}
// snippet:end flutter-android-compilesdk-override
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
