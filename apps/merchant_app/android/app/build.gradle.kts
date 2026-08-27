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

// Applied only when google-services.json is actually present.
//
// The plugin fails the build outright if the file is missing, and this app has to keep
// building for anyone who has not been given one — a developer, CI, a fresh clone. With
// the file, Messaging works; without it, LuqmaPush says so once in the log and the app
// runs.
if (rootProject.file("app/google-services.json").exists() ||
    project.file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.luqma.merchant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time, which does not exist on the older
        // Androids this ships to. Desugaring is what puts it there — without it the
        // build fails outright at checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
