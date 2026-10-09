/// Сообщение чата. Роли хранятся строками, потому что именно их ожидает
/// плагин llama_flutter_android в `generateChat`.
library;

enum Role { system, user, assistant }

extension RoleX on Role {
  String get wire => name;

  static Role parse(String value) =>
      Role.values.firstWhere((r) => r.name == value, orElse: () => Role.user);
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.createdAt,
    this.tokensPerSecond,
  });

  final Role role;
  final String text;
  final DateTime? createdAt;

  /// Заполняется после генерации — показывается под ответом как метрика.
  final double? tokensPerSecond;

  bool get isUser => role == Role.user;

  ChatMessage copyWith({String? text, double? tokensPerSecond}) => ChatMessage(
    role: role,
    text: text ?? this.text,
    createdAt: createdAt,
    tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
  );

  Map<String, dynamic> toJson() => {
    if (createdAt != null) 'at': createdAt!.toIso8601String(),
    'role': role.name,
    'text': text,
    if (tokensPerSecond != null) 'tps': tokensPerSecond,
  };

  static ChatMessage fromJson(Map<String, dynamic> json) => ChatMessage(
    role: RoleX.parse(json['role'] as String? ?? 'user'),
    text: json['text'] as String? ?? '',
    createdAt: DateTime.tryParse(json['at'] as String? ?? ''),
    tokensPerSecond: (json['tps'] as num?)?.toDouble(),
  );
}

/// Один диалог в истории.
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.modelId,
  });

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime updatedAt;

  /// Какая модель отвечала. Иначе вернувшись к старому диалогу, человек
  /// увидит другой стиль ответа и решит, что история «сломалась».
  final String? modelId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    if (modelId != null) 'modelId': modelId,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  static ChatSession fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Диалог',
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    modelId: json['modelId'] as String?,
    messages: (json['messages'] as List? ?? const [])
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
}
