import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de distribution.
//
// Les éléments sensibles ne sont jamais versionnés : ils viennent de
// `android/key.properties`, ignoré par git, ou de l'environnement pour
// l'intégration continue. Les valeurs elles-mêmes ne sont ni affichées ni
// consignées, seule leur présence l'est.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun signingSecret(property: String, variable: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(variable)

val releaseStorePath = signingSecret("storeFile", "FOXLLM_RELEASE_KEYSTORE")
val releaseStorePassword =
    signingSecret("storePassword", "FOXLLM_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = signingSecret("keyAlias", "FOXLLM_RELEASE_KEY_ALIAS")
val releaseKeyPassword =
    signingSecret("keyPassword", "FOXLLM_RELEASE_KEY_PASSWORD")

val releaseKeystore = releaseStorePath?.let(::file)?.takeIf { it.exists() }

// Tout ou rien : une signature à moitié renseignée produirait un échec de
// compilation obscur plutôt qu'un message clair.
val hasReleaseSigning =
    releaseKeystore != null &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

android {
    namespace = "com.ghostpunishr.foxllm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ghostpunishr.foxllm"
        // llama.cpp's supported Android NDK configuration uses API 28 as the baseline.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Sans clé de distribution, l'APK sort non signé plutôt que signé
            // avec la clé de développement. Un APK signé en debug ne se
            // distribue pas : sa clé est publique, connue de tous, et une
            // application installée avec elle ne pourra jamais être mise à
            // jour par une version signée pour de bon.
            signingConfig =
                if (hasReleaseSigning) signingConfigs.getByName("release") else null
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
