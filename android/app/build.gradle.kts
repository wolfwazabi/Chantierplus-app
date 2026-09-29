import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé de signature de production : android/key.properties (jamais dans git).
// Voir la procédure de création dans le README ou l'historique du projet.
val proprietesCle = Properties()
val fichierProprietesCle = rootProject.file("key.properties")
if (fichierProprietesCle.exists()) {
    FileInputStream(fichierProprietesCle).use { proprietesCle.load(it) }
}

android {
    namespace = "app.chantierplus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Exigé par flutter_local_notifications (API java.time sur anciens Android).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Identifiant définitif (Google Play) : domaine chantierplus.app à l'envers.
        applicationId = "app.chantierplus"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (fichierProprietesCle.exists()) {
            create("release") {
                keyAlias = proprietesCle["keyAlias"] as String
                keyPassword = proprietesCle["keyPassword"] as String
                storeFile = file(proprietesCle["storeFile"] as String)
                storePassword = proprietesCle["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sans key.properties, la version release est signée avec la clé de
            // débogage : pratique pour tester, mais refusée par Google Play.
            signingConfig = if (fichierProprietesCle.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("key.properties absent : release signée avec la clé de DÉBOGAGE (non publiable).")
                signingConfigs.getByName("debug")
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
