import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/conversation_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores current conversation ids independently per mode', () async {
    await ConversationHistoryService.saveCurrentConversationId(
      11,
      mode: ConversationMode.normal,
    );
    await ConversationHistoryService.saveCurrentConversationId(
      22,
      mode: ConversationMode.openclaw,
    );

    expect(
      await ConversationHistoryService.getCurrentConversationId(
        mode: ConversationMode.normal,
      ),
      11,
    );
    expect(
      await ConversationHistoryService.getCurrentConversationId(
        mode: ConversationMode.openclaw,
      ),
      22,
    );
  });

  test('round-trips last visible thread target with mode metadata', () async {
    const target = ConversationThreadTarget.existing(
      conversationId: 42,
      mode: ConversationMode.openclaw,
    );

    await ConversationHistoryService.saveLastVisibleThreadTarget(target);
    final restored =
        await ConversationHistoryService.getLastVisibleThreadTarget();

    expect(restored, target);
  });

  test('supports legacy normal-mode storage fallback', () async {
    final legacyMessages = <Map<String, dynamic>>[
      ChatMessageModel.userMessage('legacy normal message').toJson(),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'current_conversation_id': 15,
      'conversation_messages_15': jsonEncode(legacyMessages),
    });

    expect(
      await ConversationHistoryService.getCurrentConversationId(
        mode: ConversationMode.normal,
      ),
      15,
    );
    final messages = await ConversationHistoryService.getConversationMessages(
      15,
      mode: ConversationMode.normal,
    );
    expect(messages, hasLength(1));
    expect(messages.single.text, 'legacy normal message');
  });

  test('stores conversation messages independently per mode', () async {
    await ConversationHistoryService.saveConversationMessages(
      1,
      <ChatMessageModel>[ChatMessageModel.userMessage('normal thread')],
      mode: ConversationMode.normal,
    );
    await ConversationHistoryService.saveConversationMessages(
      2,
      <ChatMessageModel>[ChatMessageModel.userMessage('openclaw thread')],
      mode: ConversationMode.openclaw,
    );

    final normalMessages =
        await ConversationHistoryService.getConversationMessages(
          1,
          mode: ConversationMode.normal,
        );
    final openClawMessages =
        await ConversationHistoryService.getConversationMessages(
          2,
          mode: ConversationMode.openclaw,
        );

    expect(normalMessages.single.text, 'normal thread');
    expect(openClawMessages.single.text, 'openclaw thread');
  });
}
