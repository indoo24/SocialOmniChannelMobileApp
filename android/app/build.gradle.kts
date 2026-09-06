import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * Release signing material, read from `android/key.properties`.
 *
 * That file is git-ignored and never committed: it names a keystore path and
 * two passwords, which are the credentials that prove a build came from us.
 * Create it from `key.properties.example`.
 *
 * When it is absent — a fresh clone, CI without secrets — `release` simply has
 * no signing config and the build fails at the signing step with a clear
 * message, rather than quietly producing an artefact signed with something
 * else. See the buildTypes block for why "something else" was the problem.
 */
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

/*
 * Refuse to assemble an unsigned release rather than emit one that looks fine.
 *
 * Without a keystore the release build still *succeeds* — it just produces an
 * APK with no signature, which cannot be installed and cannot be uploaded.
 * That is safe but silent, and a green "Built app-release.apk" at the end of
 * CI is exactly the kind of success message nobody reads twice. Failing here,
 * at configuration time, says what is wrong and how to fix it.
 *
 * Only release assembly is gated: debug and profile builds are untouched, so
 * day-to-day development and `flutter run` need no keystore at all.
 */
gradle.taskGraph.whenReady {
    val assemblingRelease = allTasks.any {
        it.name.contains("Release") && (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    if (assemblingRelease && !hasReleaseKeystore) {
        throw GradleException(
            """
            |Release build refused: no signing configuration.
            |
            |android/key.properties is missing, so this build would produce an
            |unsigned APK/AAB. It will not install and Play will not accept it.
            |
            |This project no longer falls back to the Android SDK's debug
            |keystore. That key is public and identical on every machine, so a
            |release signed with it can be modified and re-signed by anyone and
            |still be accepted by Android as the same application.
            |
            |To fix:
            |  1. cp android/key.properties.example android/key.properties
            |  2. Create a keystore (the example file has the keytool command)
            |  3. Fill in the path and passwords
            |
            |key.properties and *.jks are git-ignored. Back the keystore up:
            |losing it means never being able to update this app again.
            """.trimMargin()
        )
    }
}

// Applied only once a real Firebase project's config file is present, so a
// build with push not yet configured still builds cleanly. Add
// google-services.json here (see NOTIFICATIONS_INTEGRATION.md §4) to enable it.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.scenario.scenario_mobile"
    // Flutter's own bundled default (flutter.compileSdkVersion) is 36 as of
    // this SDK, but flutter_secure_storage 11.x's Android plugin requires
    // compiling against 37 — see its own AAR metadata check.
    //
    // API level 37 has NOT been finalized/published by Google as a plain
    // "android-37" platform — verified directly against Google's own SDK
    // repository manifest (dl.google.com/android/repository/repository2-3.xml)
    // and https://developer.android.com/tools/releases/platforms, which still
    // lists API 36 as latest. Only sub-revisions exist: android-37.0,
    // android-37.1, android-37.2 (the "SDK extension" scheme Google uses for
    // an API level before it gets a stable integer release). `compileSdk = 37`
    // alone asks AGP for the literal, nonexistent target hash "android-37" —
    // most tasks resolve this leniently against the closest 37.x install, but
    // R8's own classpath resolution (minifyReleaseWithR8) does not, which is
    // the exact "Failed to find target with hash string 'android-37'"
    // failure on Codemagic's fresh SDK install. `compileSdkMinor` asks AGP
    // for the exact, real target "android-37.0" everywhere, closing that gap.
    compileSdk = 37
    compileSdkMinor = 0
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.scenario.scenario_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            /*
             * This used to read `signingConfigs.getByName("debug")`.
             *
             * The debug keystore is not a placeholder — it is a specific,
             * publicly known key that ships with the Android SDK and is
             * byte-identical on every developer machine in the world. Anything
             * signed with it can be reproduced by anyone: an attacker can take
             * this APK, modify it, re-sign it with the same key, and the OS
             * treats the result as a legitimate update to the same app,
             * because signature identity is how Android decides that. On a
             * sideloaded install that is a silent takeover; it also grants any
             * such build access to data guarded by signature-level permissions.
             *
             * Google Play refuses debug-signed uploads, so this could only ever
             * have shipped outside the store — which is exactly the
             * distribution channel where signature identity is the only
             * protection there is.
             */
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                null
            }

            /*
             * R8 in full mode: shrink, optimise and obfuscate the Java/Kotlin
             * half of the app, and strip the Android log calls listed in
             * proguard-rules.pro from the release binary.
             *
             * Defence in depth, not a secret store. It raises the cost of
             * reading the app's structure in JADX; it does not make anything
             * inside the APK confidential, and nothing in this project's
             * threat model depends on it.
             */
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
