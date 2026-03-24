import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/conversation_history_service.dart';
import 'package:ui/services/conversation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getConversations':
          return <Object?>[];
        case 'setCurrentConversationId':
        case 'deleteConversation':
          return 'SUCCESS';
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'derives openclaw conversations from mode-aware message storage',
    () async {
      await ConversationHistoryService.saveConversationMessages(
        42,
        <ChatMessageModel>[ChatMessageModel.userMessage('openclaw hello')],
        mode: ConversationMode.openclaw,
      );

      final conversations = await ConversationService.getAllConversations();

      expect(conversations, hasLength(1));
      expect(conversations.single.id, 42);
      expect(conversations.single.mode, ConversationMode.openclaw);
      expect(conversations.single.title, 'openclaw hello');
    },
  );

  test(
    'deletes only the targeted thread metadata and keeps other modes intact',
    () async {
      final conversations = <ConversationModel>[
        ConversationModel(
          id: 1,
          mode: ConversationMode.normal,
          title: 'normal thread',
          status: 0,
          messageCount: 0,
          createdAt: 1,
          updatedAt: 1,
        ),
        ConversationModel(
          id: 2,
          mode: ConversationMode.openclaw,
          title: 'openclaw thread',
          status: 0,
          messageCount: 0,
          createdAt: 2,
          updatedAt: 2,
        ),
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'local_conversation_list': jsonEncode(
          conversations.map((conversation) => conversation.toJson()).toList(),
        ),
      });
      await ConversationHistoryService.saveCurrentConversationId(
        1,
        mode: ConversationMode.normal,
      );
      await ConversationHistoryService.saveCurrentConversationId(
        2,
        mode: ConversationMode.openclaw,
      );
      await ConversationHistoryService.saveLastVisibleThreadTarget(
        const ConversationThreadTarget.existing(
          conversationId: 2,
          mode: ConversationMode.openclaw,
        ),
      );

      final deleted = await ConversationService.deleteConversation(
        2,
        mode: ConversationMode.openclaw,
      );

      expect(deleted, isTrue);
      expect(
        await ConversationHistoryService.getCurrentConversationId(
          mode: ConversationMode.normal,
        ),
        1,
      );
      expect(
        await ConversationHistoryService.getCurrentConversationId(
          mode: ConversationMode.openclaw,
        ),
        isNull,
      );
      expect(
        await ConversationHistoryService.getLastVisibleThreadTarget(),
        const ConversationThreadTarget.existing(
          conversationId: 1,
          mode: ConversationMode.normal,
        ),
      );

      final remaining = await ConversationService.getAllConversations();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, 1);
      expect(remaining.single.mode, ConversationMode.normal);
    },
  );
}
