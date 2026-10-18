import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// karita 専用の release keystore（P5c。ptune-release-key.jks は流用しない）。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "net.getperf.karita"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // **17 にする。** Flutter 3.47.4 の template がこの値であり、AGP 9.1 / KGP 2.4 の組で 11 を
    // 指すと Kotlin と Java の jvmTarget が噛み合わない。JDK は 21 なので上限は掛からない。
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // **package name は net.getperf.karita である**（P4a で決めた）。OAuth Android client が
        // この名前と debug keystore の SHA-1 に紐付き、P4a・P4b の実機証拠が全部この組で取れて
        // いる。**P5b で本番がこれを継ぎ、harness を net.getperf.karita.dev へ動かした**
        // （決定 A）。**追加登録は要らない** — 名前も SHA-1 も変わっていない。
        // → docs/architecture/production-app-composition.md「applicationId は本番が継ぐ」
        applicationId = "net.getperf.karita"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// **`kotlinOptions` は使わない。** KGP 2.x で非推奨になり、AGP 9 の android 拡張から外れた。
// Flutter 3.47.4 の template と同じ形で、トップレベルの `kotlin` ブロックへ書く。
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// **受理規則が Kotlin 側へ漏れていないこと**を測るためだけの依存である（`HandoffTest`）。
// 見るのは「URL がちょうど1件か」だけで、ISBN の規則は `karita_handoff` にしか無い。
dependencies { testImplementation("junit:junit:4.13.2") }
