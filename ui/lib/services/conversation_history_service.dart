import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';

/// 对话历史持久化服务
class ConversationHistoryService {
  static const MethodChannel _assistCore = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );
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
      for (final mode in ConversationMode.values) {
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
    final lastUnderscoreIndex = suffix.lastIndexOf('_');
    if (lastUnderscoreIndex < 0) {
      final conversationId = int.tryParse(suffix);
      if (conversationId == null) {
        return null;
      }
      return ConversationMessageStorageKey(
        conversationId: conversationId,
        mode: ConversationMode.normal,
      );
    }

    final modeStorageValue = suffix.substring(0, lastUnderscoreIndex);
    final conversationId = int.tryParse(
      suffix.substring(lastUnderscoreIndex + 1),
    );
    if (modeStorageValue.isEmpty || conversationId == null) {
      return null;
    }
    return ConversationMessageStorageKey(
      conversationId: conversationId,
      mode: ConversationMode.fromStorageValue(modeStorageValue),
    );
  }

  /// 保存对话消息列表
  static Future<void> saveConversationMessages(
    int conversationId,
    List<ChatMessageModel> messages, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final jsonList = messages.map((m) => m.toJson()).toList();
    try {
      await _assistCore.invokeMethod('replaceConversationMessages', {
        'conversationId': conversationId,
        'mode': mode.storageValue,
        'messages': jsonList,
      });
    } on PlatformException catch (e) {
      print('保存对话历史失败: ${e.message}');
    } catch (e) {
      print('保存对话历史异常: $e');
    }
  }

  /// 获取对话消息列表
  static Future<List<ChatMessageModel>> getConversationMessages(
    int conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    try {
      final result = await _assistCore.invokeMethod<List<dynamic>>(
        'getConversationMessages',
        {'conversationId': conversationId, 'mode': mode.storageValue},
      );
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map(
            (json) => ChatMessageModel.fromJson(
              Map<String, dynamic>.from(json.cast<String, dynamic>()),
            ),
          )
          .toList();
    } on PlatformException catch (e) {
      print('获取对话历史失败: ${e.message}');
      return [];
    } catch (e) {
      print('解析对话历史失败: $e');
      return [];
    }
  }

  static Future<void> upsertConversationUiCard(
    int conversationId, {
    required String entryId,
    required Map<String, dynamic> cardData,
    int? createdAtMillis,
    ConversationMode mode = ConversationMode.normal,
  }) async {
    final normalizedEntryId = entryId.trim();
    if (normalizedEntryId.isEmpty) return;
    try {
      await _assistCore.invokeMethod('upsertConversationUiCard', {
        'conversationId': conversationId,
        'mode': mode.storageValue,
        'entryId': normalizedEntryId,
        'cardData': cardData,
        'createdAt': createdAtMillis,
      });
    } on PlatformException catch (e) {
      print('保存 UI 卡片失败: ${e.message}');
    } catch (e) {
      print('保存 UI 卡片异常: $e');
    }
  }

  /// 清除对话消息
  static Future<void> clearConversationMessages(
    int conversationId, {
    ConversationMode mode = ConversationMode.normal,
  }) async {
    try {
      await _assistCore.invokeMethod('clearConversationMessages', {
        'conversationId': conversationId,
        'mode': mode.storageValue,
      });
    } on PlatformException catch (e) {
      print('清理对话历史失败: ${e.message}');
    } catch (e) {
      print('清理对话历史异常: $e');
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
