const String kConversationModeNormal = 'normal';
const String kConversationModeOpenClaw = 'openclaw';

String normalizeConversationMode(String? rawMode) {
  final normalized = rawMode?.trim().toLowerCase() ?? '';
  return normalized == kConversationModeOpenClaw
      ? kConversationModeOpenClaw
      : kConversationModeNormal;
}

class ConversationModel {
  final int id;
  final String title;
  final String? summary;
  final String? mode;
  final int status; // 0: 进行中, 1: 已完成
  final String? lastMessage;
  final int messageCount;
  final int createdAt;
  final int updatedAt;

  ConversationModel({
    required this.id,
    required this.title,
    this.summary,
    this.mode,
    required this.status,
    this.lastMessage,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode']?.toString().trim();
    return ConversationModel(
      id: json['id'] as int,
      title: json['title'] as String,
      summary: json['summary'] as String?,
      mode: rawMode == null || rawMode.isEmpty ? null : rawMode,
      status: json['status'] as int? ?? 0,
      lastMessage: json['lastMessage'] as String?,
      messageCount: json['messageCount'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      if (hasExplicitMode) 'mode': resolvedMode,
      'status': status,
      'lastMessage': lastMessage,
      'messageCount': messageCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  ConversationModel copyWith({
    int? id,
    String? title,
    String? summary,
    String? mode,
    int? status,
    String? lastMessage,
    int? messageCount,
    int? createdAt,
    int? updatedAt,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      lastMessage: lastMessage ?? this.lastMessage,
      messageCount: messageCount ?? this.messageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // 获取格式化的时间显示（今天/昨天/日期）
  String get timeDisplay {
    final now = DateTime.now();
    updatedDate;
    final today = DateTime(now.year, now.month, now.day);
    final updatedDay = DateTime(updatedDate.year, updatedDate.month, updatedDate.day);

    final difference = today.difference(updatedDay).inDays;

    if (difference == 0) {
      return '今天';
    } else if (difference == 1) {
      return '昨天';
    } else if (difference < 7) {
      // 显示星期几
      const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
      return '周${weekdays[updatedDate.weekday - 1]}';
    } else {
      // 显示月-日
      return '${updatedDate.month}-${updatedDate.day}';
    }
  }

  DateTime get updatedDate => DateTime.fromMillisecondsSinceEpoch(updatedAt);

  bool get isActive => status == 0;

  String get resolvedMode => normalizeConversationMode(mode);

  bool get hasExplicitMode => (mode?.trim().isNotEmpty ?? false);

  bool get isOpenClawConversation =>
      resolvedMode == kConversationModeOpenClaw;

  List<String> buildChatPageArgs() {
    final args = <String>[id.toString()];
    if (hasExplicitMode) {
      args.add('mode:$resolvedMode');
    }
    return args;
  }
}
