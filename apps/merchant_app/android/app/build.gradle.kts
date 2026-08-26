import java.io.FileInputStream
import java.util.Properties

// The release keystore lives once, at the repo root, and every app signs with it.
// Guarded: a machine without signing/key.properties (CI, a fresh clone) still builds
// release against debug keys, which is what `--release` smoke tests want.
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
    namespace = "com.luqma.merchant"
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
        applicationId = "com.luqma.merchant"
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
            } else {
                // No keystore on this machine: sign with debug keys so lutter run
                // --release still works. Never what ships.
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
