import java.io.FileInputStream
import java.util.Properties

// The release keystore lives once, at the repo root, and every app signs with it.
//
// A machine without signing/key.properties (CI, a fresh clone) cannot sign a release,
// and the build says so rather than quietly reaching for the debug certificate. A
// debug-signed APK installs, runs and looks finished — and is refused by Play, cannot be
// updated by a properly signed build, and has a private key that is in every Android
// SDK on earth. The one legitimate use of debug keys in release mode is a `--release`
// smoke test on this desk, and that asks for itself:
//
//     flutter build apk --release -Pluqma.debugSigning=true
val keystoreProperties = Properties().apply {
    val file = rootProject.file("../../../signing/key.properties")
    if (file.exists()) load(FileInputStream(file))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.luqma.customer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered in Firebase and permanent once published: an application id
        // cannot be changed on an app already in the Play Store, and it is half of
        // what an OAuth client is keyed on (the other half is the signing key's SHA-1).
        applicationId = "com.luqma.customer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystoreProperties.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (project.findProperty("luqma.debugSigning") != "true") {
                throw GradleException(
                    "No signing/key.properties, so this release cannot be signed. " +
                    "See signing/README.md. For a local smoke test only, pass " +
                    "-Pluqma.debugSigning=true — never for anything anybody installs."
                )
            } else {
                // Explicitly asked for. Never what ships — see the note at the top.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
