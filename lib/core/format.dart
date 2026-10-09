/// Форматирование байтов в виде, привычный пользователю.
///
/// Считаем в десятичных единицах (1 КБ = 1000 Б), а не в кибибайтах.
/// Android в настройках показывает память именно так, и Hugging Face тоже
/// так подписывает размер моделей. Считать в 1024 было бы формально верно,
/// но человек увидел бы у себя «свободно 3,7 ГБ», а приложение написало бы
/// «нужно 3,7 ГБ» — и не понял бы, хватает места или нет.
String formatBytes(num bytes, {int decimals = 2}) {
  if (bytes <= 0) return '0 Б';
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }

  if (unit == 0) return '${value.round()} ${units[0]}';

  var text = value.toStringAsFixed(decimals).replaceAll('.', ',');
  // Убираем хвостовые нули: «2,00 КБ» выглядит как калькулятор, а не
  // как интерфейс приложения. Дробная часть при этом не исчезает целиком:
  // 2,50 МБ должно стать 2,5 МБ, а не 2 МБ.
  if (text.contains(',')) {
    final parts = text.split(',');
    final fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
    text = fraction.isEmpty ? parts[0] : '${parts[0]},$fraction';
  }
  return '$text ${units[unit]}';
}

/// «1 мин 12 с», «4 с» — для замеров скорости генерации.
String formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} мс';
  if (d.inSeconds < 60) return '${(d.inSeconds * 10) ~/ 10} с';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m мин $s с';
}

/// Склонение: 1 модель, 2 модели, 5 моделей.
String plural(int count, String one, String few, String many) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
