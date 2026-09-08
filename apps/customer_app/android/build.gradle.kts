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
subprojects {
    project.evaluationDependsOn(":app")
}

// `maplibre_gl` applies the Kotlin plugin only below AGP 9 and then calls `kotlin { }`
// unconditionally, on the assumption that AGP 9 supplies that extension itself. It only
// does with `android.builtInKotlin=true`, and the Flutter template sets it false here —
// so on AGP 9 the plugin reaches an extension nobody registered and evaluating it fails
// with `Could not find method kotlin()`. That takes the whole Android build down: no APK
// for any of the three apps, including the two that never draw a map.
//
// Applied to that one subproject rather than turning the flag on, which would move our
// own Kotlin compilation from KGP to AGP to fix somebody else's plugin.
subprojects {
    if (name == "maplibre_gl") {
        apply(plugin = "org.jetbrains.kotlin.android")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
