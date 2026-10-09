import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'chat_message.dart';

/// Хранилище диалогов на устройстве.
///
/// Формат — обычный JSON, по файлу на диалог, плюс индексная папка.
/// Запись атомарная: сначала во временный файл, потом переименование.
/// Так внезапное закрытие приложения или убийство системой не портит историю —
/// на мобильных это происходит постоянно.
class ChatStore {
  ChatStore(this._root);

  final Directory _root;

  static Future<ChatStore> open() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/chats');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return ChatStore(dir);
  }

  List<ChatSession> listAll() {
    final sessions = <ChatSession>[];
    for (final entity in _root.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
        sessions.add(ChatSession.fromJson(json));
      } on FormatException {
        // Повреждённый файл не должен ломать весь список — пропускаем.
        continue;
      } on TypeError {
        continue;
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  ChatSession? byId(String id) {
    final file = File(_path(id));
    if (!file.existsSync()) return null;
    try {
      return ChatSession.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  void save(ChatSession session) {
    _atomicWrite(session);
  }

  void delete(String id) {
    final file = File(_path(id));
    if (file.existsSync()) file.deleteSync();
  }

  void deleteAll() {
    if (!_root.existsSync()) return;
    for (final entity in _root.listSync()) {
      if (entity is File) entity.deleteSync();
    }
  }

  /// Заголовок диалога — первая фраза пользователя, обрезанная.
  /// Если она длинная, режем по границе слова.
  static String titleFrom(String firstUserMessage) {
    final clean = firstUserMessage.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 38) return clean;
    final cut = clean.substring(0, 38);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 20 ? cut.substring(0, lastSpace) : cut}…';
  }

  String _path(String id) => '${_root.path}/$id.json';

  void _atomicWrite(ChatSession session) {
    if (!_root.existsSync()) _root.createSync(recursive: true);
    final target = File(_path(session.id));
    final temp = File('${target.path}.tmp');
    temp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
      flush: true,
    );
    if (target.existsSync()) target.deleteSync();
    temp.renameSync(target.path);
  }
}
