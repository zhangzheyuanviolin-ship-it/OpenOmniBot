import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/conversation_history_service.dart';
import 'package:ui/services/conversation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Map<String, dynamic>> nativeConversations;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    nativeConversations = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args =
          Map<String, dynamic>.from((call.arguments as Map?) ?? const {});
      switch (call.method) {
        case 'getConversations':
          return nativeConversations;
        case 'createConversation':
          final nextId = nativeConversations.fold<int>(
                0,
                (maxId, item) => item['id'] as int > maxId
                    ? item['id'] as int
                    : maxId,
              ) +
              1;
          nativeConversations.add({
            'id': nextId,
            'title': args['title'] ?? '新对话',
            'mode': args['mode'] ?? ConversationMode.normal.storageValue,
            'summary': args['summary'],
            'status': 0,
            'lastMessage': null,
            'messageCount': 0,
            'createdAt': 1,
            'updatedAt': 1,
          });
          return nextId;
        case 'updateConversation':
        case 'updateConversationTitle':
        case 'completeConversation':
        case 'setCurrentConversationId':
          return 'SUCCESS';
        case 'deleteConversation':
          final conversationId = (args['conversationId'] as num?)?.toInt();
          nativeConversations.removeWhere(
            (item) => item['id'] == conversationId,
          );
          return 'SUCCESS';
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('loads conversations from native source', () async {
    nativeConversations = <Map<String, dynamic>>[
      {
        'id': 42,
        'title': 'openclaw hello',
        'mode': ConversationMode.openclaw.storageValue,
        'summary': null,
        'status': 0,
        'lastMessage': 'openclaw hello',
        'messageCount': 2,
        'createdAt': 1,
        'updatedAt': 2,
      },
    ];

    final conversations = await ConversationService.getAllConversations();

    expect(conversations, hasLength(1));
    expect(conversations.single.id, 42);
    expect(conversations.single.mode, ConversationMode.openclaw);
    expect(conversations.single.title, 'openclaw hello');
  });

  test('parses context compaction metadata from native source', () async {
    nativeConversations = <Map<String, dynamic>>[
      {
        'id': 7,
        'title': 'normal hello',
        'mode': ConversationMode.normal.storageValue,
        'summary': '摘要',
        'contextSummary': '【用户目标与约束】\n- 测试',
        'contextSummaryCutoffEntryDbId': 33,
        'contextSummaryUpdatedAt': 101,
        'status': 0,
        'lastMessage': 'hello',
        'messageCount': 9,
        'latestPromptTokens': 64000,
        'promptTokenThreshold': 128000,
        'latestPromptTokensUpdatedAt': 202,
        'createdAt': 1,
        'updatedAt': 2,
      },
    ];

    final conversations = await ConversationService.getAllConversations();

    expect(conversations, hasLength(1));
    expect(conversations.single.contextSummary, contains('用户目标'));
    expect(conversations.single.contextSummaryCutoffEntryDbId, 33);
    expect(conversations.single.latestPromptTokens, 64000);
    expect(conversations.single.promptTokenThreshold, 128000);
    expect(conversations.single.contextUsageRatio, closeTo(0.5, 0.0001));
  });

  test(
    'deletes only the targeted thread metadata and keeps other modes intact',
    () async {
      nativeConversations = <Map<String, dynamic>>[
        {
          'id': 1,
          'title': 'normal thread',
          'mode': ConversationMode.normal.storageValue,
          'summary': null,
          'status': 0,
          'lastMessage': null,
          'messageCount': 0,
          'createdAt': 1,
          'updatedAt': 1,
        },
        {
          'id': 2,
          'title': 'openclaw thread',
          'mode': ConversationMode.openclaw.storageValue,
          'summary': null,
          'status': 0,
          'lastMessage': null,
          'messageCount': 0,
          'createdAt': 2,
          'updatedAt': 2,
        },
      ];
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
