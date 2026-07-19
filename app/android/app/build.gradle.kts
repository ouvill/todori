plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.taskveil.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.taskveil.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    val androidXTestJunitVersion = "1.2.1"
    val androidXTestRunnerVersion = "1.6.2"
    val androidXTestRulesVersion = "1.6.1"
    val espressoVersion = "3.6.1"

    // Flutter 3.44.6 integration_test exposes dynamic AndroidX Test dependencies
    // on the debug runtime. Keep that graph aligned with the instrumentation APK.
    // Re-evaluate these constraints when Flutter stops exposing dynamic versions.
    constraints {
        add("debugImplementation", "androidx.test:runner:$androidXTestRunnerVersion") {
            because("Flutter integration_test and androidTest runtimes must resolve the same runner")
        }
        add("debugImplementation", "androidx.test:rules:$androidXTestRulesVersion") {
            because("Flutter integration_test exposes AndroidX Test rules on the debug runtime")
        }
        add("debugImplementation", "androidx.test.espresso:espresso-core:$espressoVersion") {
            because("Flutter integration_test exposes Espresso on the debug runtime")
        }
    }

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    androidTestImplementation("androidx.test.ext:junit:$androidXTestJunitVersion")
    androidTestImplementation("androidx.test:runner:$androidXTestRunnerVersion")
}
