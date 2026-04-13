import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/services/conversation_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, List<Map<String, dynamic>>> nativeMessages;

  String threadKey(int conversationId, ConversationMode mode) {
    return '${mode.storageValue}:$conversationId';
  }

  List<Map<String, dynamic>> normalizeMessageList(dynamic raw) {
    return ((raw as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
        .toList();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    nativeMessages = <String, List<Map<String, dynamic>>>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args =
          Map<String, dynamic>.from((call.arguments as Map?) ?? const {});
      final conversationId = (args['conversationId'] as num?)?.toInt() ?? 0;
      final mode = ConversationMode.fromStorageValue(args['mode'] as String?);
      final key = threadKey(conversationId, mode);
      switch (call.method) {
        case 'replaceConversationMessages':
          nativeMessages[key] = normalizeMessageList(args['messages']);
          return 'SUCCESS';
        case 'getConversationMessages':
          return nativeMessages[key] ?? <Map<String, dynamic>>[];
        case 'clearConversationMessages':
          nativeMessages.remove(key);
          return 'SUCCESS';
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
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

  test('stores blank current thread targets independently per mode', () async {
    const normalTarget = ConversationThreadTarget.newConversation(
      mode: ConversationMode.normal,
    );
    const chatOnlyTarget = ConversationThreadTarget.newConversation(
      mode: ConversationMode.chatOnly,
    );
    const openClawTarget = ConversationThreadTarget.existing(
      conversationId: 22,
      mode: ConversationMode.openclaw,
    );

    await ConversationHistoryService.saveCurrentConversationTarget(
      normalTarget,
      mode: ConversationMode.normal,
    );
    await ConversationHistoryService.saveCurrentConversationTarget(
      chatOnlyTarget,
      mode: ConversationMode.chatOnly,
    );
    await ConversationHistoryService.saveCurrentConversationTarget(
      openClawTarget,
      mode: ConversationMode.openclaw,
    );

    expect(
      await ConversationHistoryService.getCurrentConversationTarget(
        mode: ConversationMode.normal,
      ),
      normalTarget,
    );
    expect(
      await ConversationHistoryService.getCurrentConversationTarget(
        mode: ConversationMode.chatOnly,
      ),
      chatOnlyTarget,
    );
    expect(
      await ConversationHistoryService.getCurrentConversationTarget(
        mode: ConversationMode.openclaw,
      ),
      openClawTarget,
    );
    expect(
      await ConversationHistoryService.getCurrentConversationId(
        mode: ConversationMode.normal,
      ),
      isNull,
    );
  });

  test('round-trips chat_only storage keys through parser', () {
    final parsed = ConversationHistoryService.tryParseConversationMessagesKey(
      ConversationHistoryService.conversationMessagesKey(
        9,
        mode: ConversationMode.chatOnly,
      ),
    );

    expect(parsed, isNotNull);
    expect(parsed!.conversationId, 9);
    expect(parsed.mode, ConversationMode.chatOnly);
    expect(parsed.threadKey, 'chat_only:9');
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

  test(
    'falls back to current thread target when last visible is absent',
    () async {
      const target = ConversationThreadTarget.newConversation(
        mode: ConversationMode.normal,
      );

      await ConversationHistoryService.saveCurrentConversationTarget(
        target,
        mode: ConversationMode.normal,
      );

      expect(
        await ConversationHistoryService.getLastVisibleThreadTarget(),
        target,
      );
    },
  );

  test('stores conversation messages independently per mode through native', () async {
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

  test('clears conversation messages through native', () async {
    await ConversationHistoryService.saveConversationMessages(
      7,
      <ChatMessageModel>[ChatMessageModel.userMessage('to be cleared')],
      mode: ConversationMode.subagent,
    );

    await ConversationHistoryService.clearConversationMessages(
      7,
      mode: ConversationMode.subagent,
    );

    final messages = await ConversationHistoryService.getConversationMessages(
      7,
      mode: ConversationMode.subagent,
    );
    expect(messages, isEmpty);
  });
}
