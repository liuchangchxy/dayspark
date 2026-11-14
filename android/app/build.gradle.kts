import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("app/key.properties")
val keystoreProperties = Properties()
val hasProductionKey = keystorePropertiesFile.exists()
if (hasProductionKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// com.dayspark.app 只有一个合法签名身份（`android/expected-signer.sha256`）。
// 缺 keystore 时若照常产出 unsigned release，那个包装不上、也覆盖不了已安装的
// 正式版，唯一结局是被误发出去；所以这里直接拒绝构建。
val releaseTaskRequested = gradle.startParameter.taskNames.any { name ->
    val leaf = name.substringAfterLast(':')
    leaf.startsWith("assembleRelease") ||
        leaf.startsWith("bundleRelease") ||
        leaf.startsWith("packageRelease")
}
if (releaseTaskRequested && !hasProductionKey) {
    throw GradleException(
        "Production signing key is missing: android/app/key.properties not found. " +
            "A release artifact for com.dayspark.app must be signed with the production " +
            "keystore, so an unsigned release build is refused. " +
            "For local testing build a debug APK; to build a release, restore " +
            "android/app/key.properties (storeFile, storePassword, keyAlias, keyPassword). " +
            "Never sign an already-built release APK afterwards with apksigner.",
    )
}

android {
    namespace = "com.dayspark.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasProductionKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        applicationId = "com.dayspark.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasProductionKey) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // JVM unit tests for the widget snapshot codec. org.json comes from the
    // real artifact here — android.jar's copy is stubbed in unit tests.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
