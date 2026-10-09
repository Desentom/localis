pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk не задан в local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // AGP зафиксирован на 8.11.1, а не на 9.x из шаблона Flutter 3.47.
    //
    // Причина: плагин llama_flutter_android написан под старый Gradle DSL
    // (`kotlinOptions { jvmTarget }`). В AGP 9 старый DSL не читается вообще,
    // и модуль плагина просто не конфигурируется. 8.11.1 — это ровно та
    // минимальная версия, которую принимает Flutter 3.47, поэтому она
    // официально поддерживается.
    //
    // Когда плагин переедет на новый DSL, версию AGP можно поднять до 9.x.
    id("com.android.application") version "8.11.1" apply false

    // Kotlin не ниже 2.2.20 — этот минимум проверяет сам Flutter при старте
    // сборки. При этом версия 2.2.x полностью совместима с AGP 8.11.1,
    // поэтому «старый DSL плагина» и «свежий Kotlin» уживаются.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false

    // Раскомментировать вместе с плагином в app/build.gradle.kts,
    // после добавления android/app/google-services.json:
    // id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
