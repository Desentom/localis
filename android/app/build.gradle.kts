plugins {
    id("com.android.application")
    // Flutter Gradle Plugin применяется строго после Android и Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
    // Раскомментировать после добавления android/app/google-services.json:
    // id("com.google.gms.google-services")
}

android {
    namespace = "ru.localis.ai"
    compileSdk = flutter.compileSdkVersion

    // NDK нужен: плагин llama_flutter_android компилирует llama.cpp из
    // исходников C++ через CMake, а не везёт готовые .so. Без NDK Gradle
    // падает на этапе конфигурации с «Android sdkmanager did not install NDK».
    // Ставится скриптом tool\install_native_tools.ps1.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ru.localis.ai"

        // Android 8.0. Ниже рынок давно пустой, а тянуть четыре лишние
        // версии дороже, чем получить установки. Плюс ровно эту границу
        // требует движок llama.cpp в плагине.
        minSdk = 26

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // R8 включён: без него AAB заметно больше, а правила
            // для JNI и Pigeon лежат в proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Ключ для релиза задаётся в android/key.properties,
            // см. раздел «Выпуск в Google Play» в README.
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

dependencies {
    // Google-вход. Плагин google_sign_in_android тянет эту же библиотеку
    // сам, но явное объявление избавляет от несовпадений версий.
    implementation("com.google.android.gms:play-services-auth:21.2.0")
}
