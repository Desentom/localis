import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Снимок возможностей устройства.
///
/// Считывается ДО скачивания модели: задача — не дать человеку загрузить
/// 2.5 ГБ на телефон с 3 ГБ оперативной памяти и получить вылет приложения,
/// а заодно — показать честную ожидаемую скорость генерации.
class DeviceCapability {
  const DeviceCapability({
    required this.cores,
    required this.freeRamBytes,
    required this.totalRamBytes,
    required this.vulkanSupported,
    required this.gpuName,
    required this.recommendedGpuLayers,
    this.gpuProbeFailed = false,
  });

  final int cores;
  final int freeRamBytes;
  final int totalRamBytes;
  final bool vulkanSupported;
  final String gpuName;
  final int recommendedGpuLayers;

  /// Плагин не ответил — считаем устройство «неизвестным» и не блокируем выбор.
  final bool gpuProbeFailed;

  static Future<DeviceCapability> probe() async {
    var vulkan = false;
    var gpu = '';
    var layers = 0;
    var freeRam = 0;
    var totalRam = 0;
    var failed = false;

    try {
      final gpu0 = await LlamaController().detectGpu();
      vulkan = gpu0.vulkanSupported;
      gpu = gpu0.gpuName;
      layers = gpu0.recommendedGpuLayers;
      freeRam = gpu0.freeRamBytes;
      totalRam = gpu0.deviceLocalMemoryBytes;
    } on Object {
      failed = true;
    }

    return DeviceCapability(
      cores: Platform.numberOfProcessors,
      freeRamBytes: freeRam,
      totalRamBytes: totalRam,
      vulkanSupported: vulkan,
      gpuName: gpu,
      recommendedGpuLayers: layers,
      gpuProbeFailed: failed,
    );
  }

  /// Короткое описание для карточки «о телефоне» в настройках.
  String get summary {
    final ram = totalRamBytes > 0 ? '${(totalRamBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} ГБ' : '?';
    final gpu = vulkanSupported ? gpuName : 'только процессор';
    return '$cores ядра · $ram ОЗУ · $gpu';
  }
}
