import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Values are read from a `key.properties` file (gitignored,
// never committed) OR from environment variables. If neither provides a valid
// keystore, the build falls back to debug keys so local `--release` runs still
// work — but you MUST configure real keys before uploading to the Play Store.
fun releaseStoreFile(): File? {
    val envFile = System.getenv("TRIPORA_RELEASE_STORE_FILE")
    if (!envFile.isNullOrBlank()) return File(envFile)
    val propsFile = rootProject.file("key.properties")
    if (propsFile.exists()) {
        val props = Properties()
        props.load(FileInputStream(propsFile))
        val path = props.getProperty("storeFile")
        if (!path.isNullOrBlank()) return rootProject.file(path)
    }
    return null
}

val releaseStore = releaseStoreFile()

fun loadReleaseProp(name: String): String? {
    if (releaseStore == null) return null
    val props = Properties()
    props.load(FileInputStream(rootProject.file("key.properties")))
    return props.getProperty(name) ?: System.getenv(name)
}

val releaseKeystorePassword = loadReleaseProp("storePassword")
val releaseKeyAlias = loadReleaseProp("keyAlias")
val releaseKeyPassword = loadReleaseProp("keyPassword")

android {
    namespace = "com.tripora.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tripora.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (releaseStore != null && releaseKeystorePassword != null && releaseKeyAlias != null && releaseKeyPassword != null) {
                signingConfig = signingConfigs.create("release") {
                    storeFile = releaseStore
                    storePassword = releaseKeystorePassword
                    keyAlias = releaseKeyAlias
                    keyPassword = releaseKeyPassword
                }
            } else {
                // No release credentials configured — fall back to debug keys so
                // `flutter run --release` works during development.
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
