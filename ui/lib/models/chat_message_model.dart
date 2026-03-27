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
    return ChatMessageModel(
      id: json['id']?.toString() ?? '',
      type: _asNullableInt(json['type']) ?? 1,
      user: _asNullableInt(json['user']) ?? 1,
      content: normalizedContent is Map<String, dynamic>
          ? normalizedContent
          : null,
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
      content: {
        'text': text,
        'id': messageId,
      },
    );
  }
  
  /// 创建AI回复的消息
  factory ChatMessageModel.assistantMessage(String text, {String? id, bool isLoading = false}) {
    final messageId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    return ChatMessageModel(
      id: messageId,
      type: 1, // 普通消息
      user: 2, // AI
      content: {
        'text': text,
        'id': messageId,
      },
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
      content: {
        'cardData': cardData,
        'id': messageId,
      },
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

