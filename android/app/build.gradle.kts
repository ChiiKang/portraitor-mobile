plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningValues = mapOf(
    "storeFile" to providers.gradleProperty("PORTRAITOR_UPLOAD_STORE_FILE")
        .orElse(providers.environmentVariable("PORTRAITOR_UPLOAD_STORE_FILE")).orNull,
    "storePassword" to providers.gradleProperty("PORTRAITOR_UPLOAD_STORE_PASSWORD")
        .orElse(providers.environmentVariable("PORTRAITOR_UPLOAD_STORE_PASSWORD")).orNull,
    "keyAlias" to providers.gradleProperty("PORTRAITOR_UPLOAD_KEY_ALIAS")
        .orElse(providers.environmentVariable("PORTRAITOR_UPLOAD_KEY_ALIAS")).orNull,
    "keyPassword" to providers.gradleProperty("PORTRAITOR_UPLOAD_KEY_PASSWORD")
        .orElse(providers.environmentVariable("PORTRAITOR_UPLOAD_KEY_PASSWORD")).orNull,
)
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val missingReleaseSigningValues = releaseSigningValues
    .filterValues { it.isNullOrBlank() }
    .keys

if (releaseBuildRequested && missingReleaseSigningValues.isNotEmpty()) {
    throw GradleException(
        "Release signing requires: ${missingReleaseSigningValues.joinToString()}",
    )
}

android {
    namespace = "ai.portraitor.portraitor_mobile"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ai.portraitor.portraitor_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseSigningValues["storeFile"]?.let { storeFile = file(it) }
            storePassword = releaseSigningValues["storePassword"]
            keyAlias = releaseSigningValues["keyAlias"]
            keyPassword = releaseSigningValues["keyPassword"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
