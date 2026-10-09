# Правила R8/R8 для плагина llama.cpp и Google-входа.
# Без них release-сборка падает в рантайме: JNI-методы вырезаются,
# а Kotlin-лямбды ломаются при обфускации.

# --- llama_flutter_android -----------------------------------------------------
-keep class com.write4me.llama_flutter_android.** { *; }

# --- Нативные методы: имена нельзя переименовывать, JNI ищет их по имени -----
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Kotlin: сигнатуры Function1/FunctionN нужны для вызовов из натива ---------
-keep class kotlin.jvm.functions.Function1 { *; }
-keep class kotlin.jvm.functions.Function2 { *; }
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}
-keepclassmembers class * implements kotlin.jvm.functions.Function2 {
    public java.lang.Object invoke(java.lang.Object, java.lang.Object);
}

# --- Pigeon: кодогенерация моста между Dart и Kotlin -------------------------
-keep class io.flutter.plugins.pigeon.** { *; }

# --- Google Sign-In -----------------------------------------------------------
-keep class com.google.android.gms.auth.api.identity.** { *; }

# --- Логирование и отладка ---------------------------------------------------
-dontwarn com.google.android.gms.**
-dontwarn org.conscrypt.**
