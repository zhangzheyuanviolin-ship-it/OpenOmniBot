import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/conversation_history_service.dart';

class ConversationService {
  static const MethodChannel _assistCore = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );
  static const String _localConversationListKey = 'local_conversation_list';

  static Future<List<ConversationModel>> _loadLocalConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_localConversationListKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List;
      return jsonList
          .map((json) => ConversationModel.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } catch (e) {
      print('[ConversationService] 本地对话列表解析失败: $e');
      return [];
    }
  }

  static Future<List<ConversationModel>> _deriveConversationsFromMessages({
    List<ConversationModel>? localConversations,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final messageKeys = keys.where(
      (k) => k.startsWith(ConversationHistoryService.conversationMessagesKeyPrefix),
    );

    final baseConversations = localConversations ?? await _loadLocalConversations();
    if (messageKeys.isEmpty) return _sortConversations([...baseConversations]);

    final List<ConversationModel> conversations = [];
    final Set<int> existingIds = baseConversations.map((c) => c.id).toSet();

    for (final key in messageKeys) {
      final idStr = key.substring(ConversationHistoryService.conversationMessagesKeyPrefix.length);
      final conversationId = int.tryParse(idStr);
      if (conversationId == null) continue;

      // 跳过已存在于本地列表的对话
      if (existingIds.contains(conversationId)) continue;

      final messages = await ConversationHistoryService.getConversationMessages(conversationId);
      if (messages.isEmpty) continue;

      // 确保消息列表中有有效的用户消息
      final userMessage = messages.firstWhere(
        (m) => m.user == 1 && (m.text ?? '').isNotEmpty,
        orElse: () => ChatMessageModel.userMessage("新对话"),
      );

      final titleText = userMessage.text ?? '新对话';
      final title = titleText.length > 20 ? '${titleText.substring(0, 20)}...' : titleText;

      final newest = messages.isNotEmpty ? messages.first : null;
      final oldest = messages.isNotEmpty ? messages.last : null;
      final lastText = newest?.text ?? '';
      final createdAt = oldest?.createAt.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      final updatedAt = newest?.createAt.millisecondsSinceEpoch ?? createdAt;

      conversations.add(
        ConversationModel(
          id: conversationId,
          title: title,
          summary: null,
          mode: null,
          status: 0,
          lastMessage: lastText,
          messageCount: messages.length,
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }

    return _sortConversations([...baseConversations, ...conversations]);
  }

  static Future<void> _saveLocalConversations(List<ConversationModel> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = conversations.map((c) => c.toJson()).toList();
    await prefs.setString(_localConversationListKey, jsonEncode(jsonList));
  }

  static bool _shouldPersistMerged(
    List<ConversationModel> local,
    List<ConversationModel> merged,
  ) {
    if (merged.isEmpty) return false;
    if (local.isEmpty) return true;
    if (merged.length != local.length) return true;
    final localIds = local.map((c) => c.id).toSet();
    for (final conversation in merged) {
      if (!localIds.contains(conversation.id)) return true;
    }
    return false;
  }

  static List<ConversationModel> _sortConversations(List<ConversationModel> conversations) {
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  static int _nextConversationId(List<ConversationModel> conversations) {
    if (conversations.isEmpty) return 1;
    int maxId = conversations.first.id;
    for (final conv in conversations) {
      if (conv.id > maxId) maxId = conv.id;
    }
    return maxId + 1;
  }

  /// 获取所有对话列表
  static Future<List<ConversationModel>> getAllConversations() async {
    // 本地为主，确保多引擎一致性，同时合并消息派生的对话
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final localConversations = await _loadLocalConversations();
    final merged = await _deriveConversationsFromMessages(
      localConversations: localConversations,
    );
    if (merged.isNotEmpty) {
      if (_shouldPersistMerged(localConversations, merged)) {
        await _saveLocalConversations(merged);
      }
      return merged;
    }

    // 本地为空时尝试原生（兼容旧数据）
    try {
      final result = await _assistCore.invokeMethod('getConversations');
      if (result != null && result is List) {
        final conversations = result
            .map((json) => ConversationModel.fromJson(Map<String, dynamic>.from(json as Map)))
            .toList();
        if (conversations.isNotEmpty) {
          await _saveLocalConversations(conversations);
          return _sortConversations(conversations);
        }
      }
    } on PlatformException catch (e) {
      print('[ConversationService] 获取对话列表失败: ${e.message}');
    } catch (e) {
      print('[ConversationService] 获取对话列表异常: $e');
    }

    return [];
  }

  /// 分页获取对话列表
  static Future<List<ConversationModel>> getConversationsByPage({
    required int offset,
    required int limit,
  }) async {
    final all = await getAllConversations();
    if (all.isEmpty) return [];
    final start = offset < 0 ? 0 : offset;
    if (start >= all.length) return [];
    final end = (start + limit) > all.length ? all.length : (start + limit);
    return all.sublist(start, end);
  }

  /// 创建新对话
  static Future<int?> createConversation({
    required String title,
    String? summary,
    String? mode,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final conversations = await _loadLocalConversations();
      final newId = _nextConversationId(conversations);
      final conversation = ConversationModel(
        id: newId,
        title: title,
        summary: summary,
        mode: mode,
        status: 0,
        lastMessage: null,
        messageCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      conversations.add(conversation);
      await _saveLocalConversations(_sortConversations(conversations));
      return newId;
    } catch (e) {
      print('创建对话失败: $e');
      return null;
    }
  }

  /// 更新对话
  static Future<bool> updateConversation(ConversationModel conversation) async {
    try {
      final conversations = await _loadLocalConversations();
      final index = conversations.indexWhere((c) => c.id == conversation.id);
      if (index == -1) {
        conversations.add(conversation);
      } else {
        conversations[index] = conversation;
      }
      await _saveLocalConversations(_sortConversations(conversations));
      return true;
    } catch (e) {
      print('更新对话失败: $e');
      return false;
    }
  }

  /// 删除对话
  static Future<bool> deleteConversation(int conversationId) async {
    try {
      // 1. 先删除消息
      await ConversationHistoryService.clearConversationMessages(conversationId);

      // 2. 从本地列表中删除对话
      final conversations = await _loadLocalConversations();
      conversations.removeWhere((c) => c.id == conversationId);
      await _saveLocalConversations(_sortConversations(conversations));

      // 3. 如果删除的是当前对话，清除当前对话ID
      final currentId = await ConversationHistoryService.getCurrentConversationId();
      if (currentId == conversationId) {
        await ConversationHistoryService.saveCurrentConversationId(null);
        await setCurrentConversationId(null);
      }

      // 4. 尝试删除原生层数据（如果原生层实现了该方法）
      try {
        await _assistCore.invokeMethod('deleteConversation', {
          'conversationId': conversationId,
        });
      } catch (e) {
        // 忽略原生层删除失败，可能未实现该方法
        print('[ConversationService] 原生层删除失败或未实现: $e');
      }

      return true;
    } catch (e) {
      print('删除对话失败: $e');
      return false;
    }
  }

  /// 更新对话标题
  static Future<bool> updateConversationTitle({
    required int conversationId,
    required String newTitle,
  }) async {
    try {
      final conversations = await _loadLocalConversations();
      final index = conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1) return false;
      final updated = conversations[index].copyWith(
        title: newTitle,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      conversations[index] = updated;
      await _saveLocalConversations(_sortConversations(conversations));
      return true;
    } catch (e) {
      print('更新对话标题失败: $e');
      return false;
    }
  }

  /// 生成对话摘要
  /// 使用云端 qwen-plus 模型生成 6 字左右的摘要
  static Future<String?> generateConversationSummary({
    required String conversationHistory,
  }) async {
    try {
      final result = await _assistCore.invokeMethod('generateConversationSummary', {
        'conversationHistory': conversationHistory,
      });
      return result as String?;
    } on PlatformException catch (e) {
      print('生成对话摘要失败: ${e.message}');
      return null;
    } catch (e) {
      print('生成对话摘要失败: $e');
      return null;
    }
  }

  /// 完成对话（设置状态为已完成）
  static Future<bool> completeConversation(int conversationId) async {
    try {
      final conversations = await _loadLocalConversations();
      final index = conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1) return false;
      final updated = conversations[index].copyWith(
        status: 1,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      conversations[index] = updated;
      await _saveLocalConversations(_sortConversations(conversations));
      return true;
    } catch (e) {
      print('完成对话失败: $e');
      return false;
    }
  }

  /// 设置当前活跃的对话ID（用于任务完成后跳转）
  static Future<bool> setCurrentConversationId(int? conversationId) async {
    try {
      final result = await _assistCore.invokeMethod('setCurrentConversationId', {
        'conversationId': conversationId ?? 0,
      });
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('设置当前对话ID失败: ${e.message}');
      return false;
    } catch (e) {
      print('设置当前对话ID失败: $e');
      return false;
    }
  }
}
