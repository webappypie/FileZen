import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.webappypie.filezen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.webappypie.filezen"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyStorePath = keystoreProperties.getProperty("storeFile")
                ?: System.getenv("FILEZEN_KEYSTORE_PATH")
            val keyStorePassword = keystoreProperties.getProperty("storePassword")
                ?: System.getenv("FILEZEN_KEYSTORE_PASSWORD")
            val keyAliasName = keystoreProperties.getProperty("keyAlias")
                ?: System.getenv("FILEZEN_KEY_ALIAS")
            val keyPasswordVal = keystoreProperties.getProperty("keyPassword")
                ?: System.getenv("FILEZEN_KEY_PASSWORD")

            if (!keyStorePath.isNullOrBlank()) {
                val resolvedStoreFile = if (file(keyStorePath).isAbsolute) {
                    file(keyStorePath)
                } else {
                    rootProject.file(keyStorePath)
                }
                if (resolvedStoreFile.exists()) {
                    storeFile = resolvedStoreFile
                    storePassword = keyStorePassword
                    keyAlias = keyAliasName
                    keyPassword = keyPasswordVal
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
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
