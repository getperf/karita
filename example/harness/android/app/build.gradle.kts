plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "net.getperf.karita.dev"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // **17 にする。** Flutter 3.47.4 の template がこの値であり、AGP 9.1 / KGP 2.4 の組で 11 を
    // 指すと Kotlin と Java の jvmTarget が噛み合わない。JDK は 21 なので上限は掛からない。
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // **`net.getperf.karita` は本番（`apps/karita`）へ渡した**（2026-09-23。決定 A）。
        // P4a・P4b の実機証拠が乗った名前を、焼き込まれて配布に乗る側が継ぐ。
        //
        // **この名前は OAuth Android client を1件必要とする**（SHA-1 はこの機械の debug
        // keystore のまま。変えたのはパッケージ名だけである）。
        //
        // **データ領域も別になる。** Android は applicationId ごとにサンドボックスが分かれる
        // ので、改名後の harness は台帳も deviceId も token も持たない新しい端末である。
        // P4b の観測はここで切れており、続けるなら `adopt` から入れ直す。
        // → docs/architecture/production-app-composition.md「applicationId は本番が継ぐ」
        applicationId = "net.getperf.karita.dev"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // **debug 署名のままである。** release 署名と専用 keystore は P5c で作る。
            signingConfig = signingConfigs.getByName("debug")
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
