import 'package:ui/models/conversation_model.dart';
import 'package:ui/services/cache_service.dart';
import 'package:ui/services/conversation_history_service.dart';

class ConversationArchiveService {
  static const String _archivedConversationKeysKey =
      'archived_conversation_keys_v1';

  static String keyForConversationId({
    required int conversationId,
    required ConversationMode mode,
  }) {
    return '${mode.storageValue}:$conversationId';
  }

  static String keyForConversation(ConversationModel conversation) {
    return keyForConversationId(
      conversationId: conversation.id,
      mode: conversation.mode,
    );
  }

  static Future<Set<String>> getArchivedConversationKeys() async {
    final keys = await CacheService.getStringList(
      _archivedConversationKeysKey,
      defaultValue: const [],
    );
    return keys.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
  }

  static Future<void> _saveArchivedConversationKeys(Set<String> keys) async {
    final sortedKeys = keys.toList()..sort();
    await CacheService.setStringList(_archivedConversationKeysKey, sortedKeys);
  }

  static Future<List<ConversationModel>> applyArchiveState(
    List<ConversationModel> conversations,
  ) async {
    if (conversations.isEmpty) {
      return conversations;
    }
    final archivedKeys = await getArchivedConversationKeys();
    return conversations
        .map(
          (conversation) => conversation.copyWith(
            isArchived: archivedKeys.contains(keyForConversation(conversation)),
          ),
        )
        .toList();
  }

  static Future<bool> setConversationArchived(
    ConversationModel conversation, {
    required bool archived,
  }) async {
    try {
      final archivedKeys = await getArchivedConversationKeys();
      final key = keyForConversation(conversation);
      if (archived) {
        archivedKeys.add(key);
      } else {
        archivedKeys.remove(key);
      }
      await _saveArchivedConversationKeys(archivedKeys);
      if (archived) {
        await ConversationHistoryService.clearConversationThreadReferences(
          conversation.id,
          mode: conversation.mode,
        );
      }
      return true;
    } catch (error) {
      print('[ConversationArchiveService] 更新归档状态失败: $error');
      return false;
    }
  }

  static Future<void> forgetConversation({
    required int conversationId,
    ConversationMode? mode,
  }) async {
    try {
      final archivedKeys = await getArchivedConversationKeys();
      if (archivedKeys.isEmpty) {
        return;
      }
      if (mode != null) {
        archivedKeys.remove(
          keyForConversationId(conversationId: conversationId, mode: mode),
        );
      } else {
        archivedKeys.removeWhere(
          (item) => item.endsWith(':$conversationId'),
        );
      }
      await _saveArchivedConversationKeys(archivedKeys);
    } catch (error) {
      print('[ConversationArchiveService] 清理归档状态失败: $error');
    }
  }
}
