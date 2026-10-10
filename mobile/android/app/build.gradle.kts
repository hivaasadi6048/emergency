plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.emergency.app.emergency_poc"
    // PHASE 0 decision (docs/architecture.md Q-04 / §14 row 10):
    // Play requires targetSdk 36 for new apps/updates since Aug 31, 2026.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.emergency.app.emergency_poc"
        // PHASE 0 proposal A-01: minSdk 26 (Android 8.0) — final confirmation in PHASE 1 device matrix.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    // androidx.core is used by the PoC native service (NotificationCompat/ContextCompat).
    // The template ships no dependencies block; the pin keeps the compile classpath explicit.
    implementation("androidx.core:core-ktx:1.15.0")
}
