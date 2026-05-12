plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_ai_assignment"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.flutter_ai_assignment"
        // tflite_flutter & camera plugin butuh minSdk >= 21.
        // 24 dipakai supaya NNAPI delegate (akselerasi AI di NPU/GPU) tersedia.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Mencegah ProGuard membuang simbol native TFLite & GPU delegate.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // .tflite tidak perlu dikompresi APK — supaya mmap() bisa langsung baca file.
    androidResources {
        noCompress += listOf("tflite")
    }
}

flutter {
    source = "../.."
}
