package ru.localis.ai

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Единственная нативная логика во всём приложении.
 *
 * Из Dart нельзя узнать, сколько свободно места на телефоне, а без этого
 * нельзя честно сказать «нужно 4 ГБ, свободно 1,2 ГБ» перед скачиванием
 * модели весом в два гигабайта. Метод один и намеренно крошечный.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "freeBytes" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            result.success(freeBytes(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun freeBytes(path: String): Long = try {
        val stat = StatFs(path)
        stat.availableBytes
    } catch (e: IllegalArgumentException) {
        // Путь не существует — сообщаем «неизвестно», а не врём нулём.
        -1L
    } catch (e: SecurityException) {
        -1L
    }

    private companion object {
        const val CHANNEL = "localis/device"
    }
}
