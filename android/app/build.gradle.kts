import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // 推播：版本在 settings.gradle.kts，這裡先不套用，下面確定有 google-services.json 才套用
    id("com.google.gms.google-services") apply false
}

// 推播（Firebase Cloud Messaging，見 MainActivity.kt 旁的 Push.kt）：android/app/google-services.json 不進 git，
// 有這個檔案才套用 google-services plugin；沒有時照樣能建置，只是沒有推播（Push.available 回傳 false）。
// github 與 play 兩種發行管道的 applicationId 相同，共用同一份設定
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// 正式發版金鑰：android/key.properties（不進 git）指向專案外的金鑰檔；沒有這個檔案時用 debug 金鑰簽，`flutter run --release` 照樣能跑
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// 發行管道：github（預設，App 自己下載、驗證並安裝更新）或 play（上架 Google Play，不含自我更新）。
// play 版：flutter build appbundle --android-project-arg=distribution=play（make aab-play）。
// 不用 product flavor：flavor 會讓每次 flutter run／build 都得加 --flavor，pubspec 的 default-flavor 又會套到 macOS、iOS 而建置失敗
val distribution = (project.findProperty("distribution") as String?) ?: "github"
require(distribution == "github" || distribution == "play") { "distribution 只能是 github 或 play" }

android {
    namespace = "com.bityo.securibit"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.bityo.securibit"
        // cryptography_flutter and local_auth_android need API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // GitHub 的 APK 依處理器是 1000／2000／4000 加 build 號（flutter build apk --split-per-abi）；
        // play 版加 5000，比同一版的 APK 都大，裝過 GitHub 版的手機才能從 Play 直接覆蓋安裝
        versionCode = if (distribution == "play") 5000 + flutter.versionCode else flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

// GitHub 版才合併 src/selfUpdate/AndroidManifest.xml（REQUEST_INSTALL_PACKAGES 與 FileProvider）；
// App 執行時看 manifest 有沒有這個權限決定要不要檢查更新（MainActivity.kt 的 selfUpdate），兩邊不會對不上
androidComponents {
    onVariants { variant ->
        if (distribution == "github") variant.sources.manifests.addStaticManifestFile("src/selfUpdate/AndroidManifest.xml")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // MainActivity is a FlutterFragmentActivity and the themes are AppCompat.
    implementation("androidx.appcompat:appcompat:1.7.0")
    // 推播：只用原生的 Firebase Cloud Messaging，不用 Flutter 的 firebase_messaging（Windows 建置會拉進 Firebase C++ SDK）
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    // Google Play 版的強制更新（PlayUpdate.kt）：Play 的 App 內更新；GitHub 版不會呼叫
    implementation("com.google.android.play:app-update:2.1.0")
}
