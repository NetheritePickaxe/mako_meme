import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    load(file("key.properties").inputStream())
}

    android {
        namespace = "com.mako.mako_meme"
        compileSdk = 37
        ndkVersion = flutter.ndkVersion

        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }

        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }

        defaultConfig {
            applicationId = "com.mako.mako_meme"
            minSdk = 24
            targetSdk = 37
            versionCode = flutter.versionCode
            versionName = flutter.versionName
        }

        buildTypes {
            release {
                signingConfig = signingConfigs.getByName("release")
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

    dependencies {
        // IME 表情包输入法网格列表所需（不引入第三方图片库，仅用 Android 原生 API）
        implementation("androidx.recyclerview:recyclerview:1.3.2")
        // 拼音搜索
        implementation("com.belerweb:pinyin4j:2.5.1")
    }

flutter {
    source = "../.."
}
