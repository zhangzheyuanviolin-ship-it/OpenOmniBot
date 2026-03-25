import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';

/// 对话历史持久化服务
class ConversationHistoryService {
  static const String _legacyConversationIdKey = 'current_conversation_id';
  static const String _conversationIdKeyPrefix = 'current_conversation_id_';
  static const String _conversationTargetKeyPrefix =
      'current_conversation_target_';
  static const String _lastVisibleThreadTargetKey =
      'last_visible_conversation_target';
  static const String _conversationMessagesKey = 'conversation_messages_';
  static const String conversationMessagesKeyPrefix = _conversationMessagesKey;

  static String _conversationIdKeyForMode(ConversationMode mode) {
    return '$_conversationIdKeyPrefix${mode.storageValue}';
  }

  static String _conversationTargetKeyForMode(ConversationMode mode) {
    return '$_conversationTargetKeyPrefix${mode.storageValue}';
  }

  /// 保存当前对话ID
  static Future<void> saveCurrentConversationId(
    int? conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final modeKey = _conversationIdKeyForMode(mode);
    if (conversationId == null) {
      await prefs.remove(modeKey);
      if (mode == ConversationMode.normal) {
        await prefs.remove(_legacyConversationIdKey);
      }
    } else {
      await prefs.setInt(modeKey, conversationId);
      if (mode == ConversationMode.normal) {
        await prefs.setInt(_legacyConversationIdKey, conversationId);
      }
    }
  }

  /// 获取当前对话ID
  static Future<int?> getCurrentConversationId({
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id =
        prefs.getInt(_conversationIdKeyForMode(mode)) ??
        (mode == ConversationMode.normal
            ? prefs.getInt(_legacyConversationIdKey)
            : null);
    return id == 0 ? null : id;
  }

  static Future<ConversationThreadTarget?> getCurrentConversationTarget({
    required ConversationMode mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationTargetKeyForMode(mode));
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final target = ConversationThreadTarget.fromEncodedJson(raw);
        return target.copyWith(
          mode: mode,
          fromNativeRoute: false,
          clearRequestKey: true,
        );
      } catch (e) {
        print('解析当前线程目标失败: $e');
      }
    }
    final conversationId = await getCurrentConversationId(mode: mode);
    if (conversationId == null) {
      return null;
    }
    return ConversationThreadTarget.existing(
      conversationId: conversationId,
      mode: mode,
    );
  }

  static Future<void> saveCurrentConversationTarget(
    ConversationThreadTarget? target, {
    required ConversationMode mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _conversationTargetKeyForMode(mode);
    if (target == null) {
      await prefs.remove(key);
      await saveCurrentConversationId(null, mode: mode);
      return;
    }

    final sanitized = target.copyWith(
      mode: mode,
      fromNativeRoute: false,
      clearRequestKey: true,
    );
    await prefs.setString(key, sanitized.toEncodedJson());
    await saveCurrentConversationId(sanitized.conversationId, mode: mode);
  }

  static Future<void> saveLastVisibleThreadTarget(
    ConversationThreadTarget? target,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (target == null) {
      await prefs.remove(_lastVisibleThreadTargetKey);
      return;
    }
    final sanitized = target.copyWith(
      fromNativeRoute: false,
      clearRequestKey: true,
    );
    await prefs.setString(
      _lastVisibleThreadTargetKey,
      sanitized.toEncodedJson(),
    );
  }

  static Future<ConversationThreadTarget?> getLastVisibleThreadTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastVisibleThreadTargetKey);
    if (raw == null || raw.trim().isEmpty) {
      for (final mode in const <ConversationMode>[
        ConversationMode.normal,
        ConversationMode.openclaw,
        ConversationMode.subagent,
      ]) {
        final target = await getCurrentConversationTarget(mode: mode);
        if (target == null) {
          continue;
        }
        return target;
      }
      return null;
    }
    try {
      return ConversationThreadTarget.fromEncodedJson(raw);
    } catch (e) {
      print('解析上次可见线程失败: $e');
      return null;
    }
  }

  static Future<void> clearConversationThreadReferences(
    int conversationId, {
    ConversationMode? mode,
  }) async {
    final modes = mode == null
        ? ConversationMode.values
        : <ConversationMode>[mode];
    for (final entryMode in modes) {
      final currentTarget = await getCurrentConversationTarget(mode: entryMode);
      if (currentTarget?.conversationId == conversationId) {
        await saveCurrentConversationTarget(null, mode: entryMode);
      }
    }

    final lastVisible = await getLastVisibleThreadTarget();
    if (lastVisible != null &&
        lastVisible.conversationId == conversationId &&
        (mode == null || lastVisible.mode == mode)) {
      await saveLastVisibleThreadTarget(null);
    }
  }

  /// 重新加载本地存储（用于多引擎/跨隔离同步）
  static Future<void> reloadLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
    } catch (e) {
      print('刷新本地缓存失败: $e');
    }
  }

  static String conversationMessagesKey(
    int conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) {
    return '$_conversationMessagesKey${mode.storageValue}_$conversationId';
  }

  static String _legacyConversationMessagesKey(int conversationId) {
    return '$_conversationMessagesKey$conversationId';
  }

  static ConversationMessageStorageKey? tryParseConversationMessagesKey(
    String key,
  ) {
    if (!key.startsWith(conversationMessagesKeyPrefix)) {
      return null;
    }
    final suffix = key.substring(conversationMessagesKeyPrefix.length);
    final parts = suffix.split('_');
    if (parts.length == 1) {
      final conversationId = int.tryParse(parts.first);
      if (conversationId == null) {
        return null;
      }
      return ConversationMessageStorageKey(
        conversationId: conversationId,
        mode: ConversationMode.normal,
      );
    }
    if (parts.length < 2) {
      return null;
    }
    final mode = ConversationMode.fromStorageValue(parts.first);
    final conversationId = int.tryParse(parts.sublist(1).join('_'));
    if (conversationId == null) {
      return null;
    }
    return ConversationMessageStorageKey(
      conversationId: conversationId,
      mode: mode,
    );
  }

  /// 保存对话消息列表
  static Future<void> saveConversationMessages(
    int conversationId,
    List<ChatMessageModel> messages, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = messages.map((m) => m.toJson()).toList();
    if (mode == ConversationMode.normal) {
      await prefs.remove(_legacyConversationMessagesKey(conversationId));
    }
    await prefs.setString(
      conversationMessagesKey(conversationId, mode: mode),
      jsonEncode(jsonList),
    );
  }

  /// 获取对话消息列表
  static Future<List<ChatMessageModel>> getConversationMessages(
    int conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        prefs.getString(conversationMessagesKey(conversationId, mode: mode)) ??
        (mode == ConversationMode.normal
            ? prefs.getString(_legacyConversationMessagesKey(conversationId))
            : null);
    if (jsonStr == null) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList.map((json) => ChatMessageModel.fromJson(json)).toList();
    } catch (e) {
      print('解析对话历史失败: $e');
      return [];
    }
  }

  /// 清除对话消息
  static Future<void> clearConversationMessages(
    int conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(conversationMessagesKey(conversationId, mode: mode));
    if (mode == ConversationMode.normal) {
      await prefs.remove(_legacyConversationMessagesKey(conversationId));
    }
  }
}

class ConversationMessageStorageKey {
  const ConversationMessageStorageKey({
    required this.conversationId,
    required this.mode,
  });

  final int conversationId;
  final ConversationMode mode;

  String get threadKey => '${mode.storageValue}:$conversationId';
}
