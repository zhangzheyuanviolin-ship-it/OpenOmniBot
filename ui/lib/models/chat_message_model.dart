import 'dart:convert';

/// AI聊天消息模型
///
/// 支持不同类型的消息：用户消息、AI回复消息，以及卡片类型消息

/// 聊天消息模型
class ChatMessageModel {
  /// 消息唯一标识
  final String id;

  /// 消息类型：1=普通消息, 2=卡片消息
  final int type;

  /// 发送方：1=用户, 2=AI, 3=系统（卡片消息）
  final int user;

  /// 内容数据（包含text、cardData、id等）
  final Map<String, dynamic>? content;

  /// 是否为加载中状态
  final bool isLoading;

  /// 是否为第一个切片（用于流式消息持久化）
  final bool isFirst;

  /// 是否为错误消息
  final bool isError;

  /// 是否为总结中状态
  final bool isSummarizing;

  /// 创建时间
  final DateTime createAt;

  ChatMessageModel({
    required this.id,
    required this.type,
    required this.user,
    this.content,
    this.isLoading = false,
    this.isFirst = false,
    this.isError = false,
    this.isSummarizing = false,
    DateTime? createAt,
  }) : createAt = createAt ?? DateTime.now();

  /// 获取文本内容
  String? get text {
    final value = content?['text'];
    return value == null ? null : value.toString();
  }

  /// 获取卡片数据
  Map<String, dynamic>? get cardData {
    final value = content?['cardData'];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return _normalizeMap(value);
    }
    return null;
  }

  /// 获取内容ID（用于卡片）
  String? get contentId {
    final value = content?['id'];
    return value == null ? null : value.toString();
  }

  /// 获取数据库ID（用于本地存储和渲染key）
  int? get dbId => _asNullableInt(content?['dbId']);

  /// 从JSON创建
  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final normalizedContent = _normalizeDynamic(json['content']);
    final normalizedType = _asNullableInt(json['type']) ?? 1;
    final normalizedUser = _asNullableInt(json['user']) ?? 1;
    final contentMap = normalizedContent is Map<String, dynamic>
        ? _normalizeAssistantTextContent(
            normalizedContent,
            type: normalizedType,
            user: normalizedUser,
          )
        : null;
    return ChatMessageModel(
      id: json['id']?.toString() ?? '',
      type: normalizedType,
      user: normalizedUser,
      content: contentMap,
      isLoading: json['isLoading'] as bool? ?? false,
      isFirst: json['isFirst'] as bool? ?? false,
      isError: json['isError'] as bool? ?? false,
      isSummarizing: json['isSummarizing'] as bool? ?? false,
      createAt: _parseCreateAt(json['createAt']),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'user': user,
      'content': content,
      'isLoading': isLoading,
      'isFirst': isFirst,
      'isError': isError,
      'isSummarizing': isSummarizing,
      'createAt': createAt.toIso8601String(),
    };
  }

  /// 创建用户发送的消息
  factory ChatMessageModel.userMessage(String text, {String? id}) {
    final messageId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    return ChatMessageModel(
      id: messageId,
      type: 1, // 普通消息
      user: 1, // 用户
      content: {'text': text, 'id': messageId},
    );
  }

  /// 创建AI回复的消息
  factory ChatMessageModel.assistantMessage(
    String text, {
    String? id,
    bool isLoading = false,
  }) {
    final messageId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    return ChatMessageModel(
      id: messageId,
      type: 1, // 普通消息
      user: 2, // AI
      content: {'text': text, 'id': messageId},
      isLoading: isLoading,
    );
  }

  /// 创建卡片消息
  factory ChatMessageModel.cardMessage(
    Map<String, dynamic> cardData, {
    String? id,
  }) {
    final messageId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    return ChatMessageModel(
      id: messageId,
      type: 2, // 卡片消息
      user: 3, // 系统
      content: {'cardData': cardData, 'id': messageId},
    );
  }

  /// 复制消息并更新字段（用于流式更新）
  ChatMessageModel copyWith({
    String? id,
    int? type,
    int? user,
    Map<String, dynamic>? content,
    bool? isLoading,
    bool? isFirst,
    bool? isError,
    bool? isSummarizing,
    DateTime? createAt,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      type: type ?? this.type,
      user: user ?? this.user,
      content: content ?? this.content,
      isLoading: isLoading ?? this.isLoading,
      isFirst: isFirst ?? this.isFirst,
      isError: isError ?? this.isError,
      isSummarizing: isSummarizing ?? this.isSummarizing,
      createAt: createAt ?? this.createAt,
    );
  }

  static int? _asNullableInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) {
      final asDouble = raw.toDouble();
      if (asDouble.isFinite && asDouble == asDouble.truncateToDouble()) {
        return raw.toInt();
      }
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      final parsedInt = int.tryParse(trimmed);
      if (parsedInt != null) {
        return parsedInt;
      }
      final parsedDouble = double.tryParse(trimmed);
      if (parsedDouble != null &&
          parsedDouble.isFinite &&
          parsedDouble == parsedDouble.truncateToDouble()) {
        return parsedDouble.toInt();
      }
    }
    return null;
  }

  static DateTime _parseCreateAt(dynamic raw) {
    if (raw is DateTime) {
      return raw;
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return DateTime.now();
      }
      final parsedDateTime = DateTime.tryParse(trimmed);
      if (parsedDateTime != null) {
        return parsedDateTime;
      }
      final millis = int.tryParse(trimmed);
      if (millis != null) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }
    return DateTime.now();
  }

  static Map<String, dynamic> _normalizeAssistantTextContent(
    Map<String, dynamic> content, {
    required int type,
    required int user,
  }) {
    if (type != 1 || user != 2) {
      return content;
    }
    final rawText = content['text']?.toString() ?? '';
    if (rawText.trim().isEmpty || !rawText.contains('{')) {
      return content;
    }
    final sanitized = _sanitizePersistedAssistantText(rawText);
    if (sanitized == rawText) {
      return content;
    }
    return <String, dynamic>{...content, 'text': sanitized};
  }

  static String _sanitizePersistedAssistantText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !trimmed.contains('{')) {
      return raw;
    }

    final buffer = StringBuffer();
    var cursor = 0;
    while (cursor < raw.length) {
      if (raw[cursor] == '{') {
        final jsonEnd = _findBalancedJsonObjectEnd(raw, cursor);
        if (jsonEnd != null) {
          final extracted = _extractStructuredAssistantText(
            raw.substring(cursor, jsonEnd + 1),
          );
          if (extracted.isNotEmpty) {
            buffer.write(extracted);
          }
          cursor = jsonEnd + 1;
          continue;
        }
      }
      buffer.write(raw[cursor]);
      cursor += 1;
    }

    final sanitized = buffer.toString().trim();
    if (sanitized.isEmpty && trimmed.startsWith('{')) {
      return '';
    }
    return sanitized.isEmpty ? raw : sanitized;
  }

  static int? _findBalancedJsonObjectEnd(String raw, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < raw.length; index++) {
      final char = raw[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (inString && char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  static String _extractStructuredAssistantText(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty || !normalized.startsWith('{')) {
      return '';
    }

    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map) {
        if (decoded.containsKey('text')) {
          return _extractTextPayload(decoded['text']).trim();
        }
        if (decoded.containsKey('output_text')) {
          return _extractTextPayload(decoded['output_text']).trim();
        }
        if (decoded.containsKey('content')) {
          return _extractTextPayload(decoded['content']).trim();
        }
        final message = decoded['message'];
        if (message is String) {
          return message.trim();
        }
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final firstChoice = choices.first;
          if (firstChoice is Map) {
            final delta = firstChoice['delta'];
            if (delta is Map) {
              return _extractTextPayload(delta['content']).trim();
            }
            final choiceMessage = firstChoice['message'];
            if (choiceMessage is Map) {
              return _extractTextPayload(choiceMessage['content']).trim();
            }
          }
        }
        final output = decoded['output'];
        if (output is List) {
          return output.map(_extractTextPayload).join().trim();
        }
      }
    } catch (_) {}

    final contentMatch = RegExp(
      r'"(?:content|text)"\s*:\s*"((?:\\.|[^"\\])*)"',
    ).firstMatch(normalized);
    final encodedText = contentMatch?.group(1);
    if (encodedText == null || encodedText.isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode('{"text":"$encodedText"}') as Map;
      return (decoded['text'] ?? '').toString().trim();
    } catch (_) {
      return encodedText.trim();
    }
  }

  static String _extractTextPayload(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is List) {
      return raw.map(_extractTextPayload).join().trim();
    }
    if (raw is Map) {
      final type = raw['type']?.toString().trim().toLowerCase();
      if (type == 'text' || type == 'output_text') {
        return _extractTextPayload(raw['text']).trim();
      }
      if (raw.containsKey('text')) {
        return _extractTextPayload(raw['text']).trim();
      }
      if (raw.containsKey('content')) {
        return _extractTextPayload(raw['content']).trim();
      }
    }
    return '';
  }

  static Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> source) {
    return source.map(
      (key, value) => MapEntry(key.toString(), _normalizeDynamic(value)),
    );
  }

  static dynamic _normalizeDynamic(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value.map(
        (key, nestedValue) => MapEntry(key, _normalizeDynamic(nestedValue)),
      );
    }
    if (value is Map) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeDynamic).toList();
    }
    if (value is double && value.isFinite) {
      final integral = value.toInt();
      if (value == integral.toDouble()) {
        return integral;
      }
    }
    return value;
  }
}
