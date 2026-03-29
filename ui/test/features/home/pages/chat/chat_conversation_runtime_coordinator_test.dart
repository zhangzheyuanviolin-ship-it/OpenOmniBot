import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'cn.com.omnimind.bot/AssistCoreEvent';
  const codec = StandardMethodCodec();
  const methodChannel = MethodChannel(channelName);
  final coordinator = ChatConversationRuntimeCoordinator.instance;
  final recordedMethodCalls = <MethodCall>[];

  Future<void> emitPlatformEvent(String method, [dynamic arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (ByteData? _) {},
        );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    coordinator.resetForTest();
    coordinator.ensureInitialized();
    recordedMethodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          recordedMethodCalls.add(call);
          return 'SUCCESS';
        });
  });

  tearDown(() async {
    coordinator.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('routes agent chat updates to the bound conversation only', () async {
    const conversationA = 1001;
    const conversationB = 1002;
    const taskId = 'agent-task-a';

    coordinator.ensureRuntime(
      conversationId: conversationA,
      mode: kChatRuntimeModeNormal,
    );
    coordinator.ensureRuntime(
      conversationId: conversationB,
      mode: kChatRuntimeModeNormal,
    );
    coordinator.registerTask(
      taskId: taskId,
      conversationId: conversationA,
      mode: kChatRuntimeModeNormal,
    );

    final runtimeA = coordinator.runtimeFor(
      conversationId: conversationA,
      mode: kChatRuntimeModeNormal,
    )!;
    runtimeA.currentDispatchTaskId = taskId;

    await emitPlatformEvent('onAgentChatMessage', <String, dynamic>{
      'taskId': taskId,
      'message': 'hello from agent',
      'isFinal': false,
    });

    final runtimeB = coordinator.runtimeFor(
      conversationId: conversationB,
      mode: kChatRuntimeModeNormal,
    )!;

    expect(runtimeA.messages, hasLength(1));
    expect(runtimeA.messages.first.id, '$taskId-text');
    expect(runtimeA.messages.first.text, 'hello from agent');
    expect(runtimeB.messages, isEmpty);
  });

  test('routes chat task chunks to the bound conversation only', () async {
    const conversationA = 2001;
    const conversationB = 2002;
    const taskId = 'chat-task-a';

    coordinator.ensureRuntime(
      conversationId: conversationA,
      mode: kChatRuntimeModeOpenClaw,
    );
    coordinator.ensureRuntime(
      conversationId: conversationB,
      mode: kChatRuntimeModeOpenClaw,
    );
    coordinator.registerTask(
      taskId: taskId,
      conversationId: conversationA,
      mode: kChatRuntimeModeOpenClaw,
    );

    await emitPlatformEvent('onChatMessage', <String, dynamic>{
      'taskID': taskId,
      'content': '{"text":"hello from openclaw"}',
      'type': null,
    });

    final runtimeA = coordinator.runtimeFor(
      conversationId: conversationA,
      mode: kChatRuntimeModeOpenClaw,
    )!;
    final runtimeB = coordinator.runtimeFor(
      conversationId: conversationB,
      mode: kChatRuntimeModeOpenClaw,
    )!;

    expect(runtimeA.messages, hasLength(1));
    expect(runtimeA.messages.first.id, taskId);
    expect(runtimeA.messages.first.text, 'hello from openclaw');
    expect(runtimeB.messages, isEmpty);
  });

  test(
    'routes VLM request-input state to the bound conversation only',
    () async {
      const conversationA = 3001;
      const conversationB = 3002;
      const taskId = 'vlm-task-a';

      coordinator.ensureRuntime(
        conversationId: conversationA,
        mode: kChatRuntimeModeNormal,
      );
      coordinator.ensureRuntime(
        conversationId: conversationB,
        mode: kChatRuntimeModeNormal,
      );
      coordinator.registerTask(
        taskId: taskId,
        conversationId: conversationA,
        mode: kChatRuntimeModeNormal,
      );

      await emitPlatformEvent('onVLMRequestUserInput', <String, dynamic>{
        'taskId': taskId,
        'question': 'Need more info',
      });

      final runtimeA = coordinator.runtimeFor(
        conversationId: conversationA,
        mode: kChatRuntimeModeNormal,
      )!;
      final runtimeB = coordinator.runtimeFor(
        conversationId: conversationB,
        mode: kChatRuntimeModeNormal,
      )!;

      expect(runtimeA.vlmInfoQuestion, 'Need more info');
      expect(runtimeB.vlmInfoQuestion, isNull);
    },
  );

  test('clears transient agent thinking state when a session ends', () {
    const conversationId = 4001;

    final runtime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );
    runtime.currentDispatchTaskId = 'agent-task';
    runtime.deepThinkingContent = 'old thinking';
    runtime.isDeepThinking = true;
    runtime.currentThinkingStage = 4;
    runtime.lastAgentTaskId = 'agent-task';
    runtime.activeToolCardId = 'agent-task-tool-1';
    runtime.activeThinkingCardId = 'agent-task-thinking';
    runtime.pendingAgentTextTaskId = 'agent-task';
    runtime.pendingThinkingRoundSplit = true;
    runtime.toolCardSequence = 3;
    runtime.thinkingRound = 2;

    coordinator.clearConversationRuntimeSession(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );

    expect(runtime.currentDispatchTaskId, isNull);
    expect(runtime.deepThinkingContent, isEmpty);
    expect(runtime.isDeepThinking, isFalse);
    expect(runtime.currentThinkingStage, 1);
    expect(runtime.lastAgentTaskId, isNull);
    expect(runtime.activeToolCardId, isNull);
    expect(runtime.activeThinkingCardId, isNull);
    expect(runtime.pendingAgentTextTaskId, isNull);
    expect(runtime.pendingThinkingRoundSplit, isFalse);
    expect(runtime.toolCardSequence, 0);
    expect(runtime.thinkingRound, 0);
  });

  test(
    'keeps assistant content visible when tool calls start afterwards',
    () async {
      const conversationId = 4501;
      const taskId = 'agent-task-with-content';

      final runtime = coordinator.ensureRuntime(
        conversationId: conversationId,
        mode: kChatRuntimeModeNormal,
      );
      runtime.currentDispatchTaskId = taskId;
      coordinator.registerTask(
        taskId: taskId,
        conversationId: conversationId,
        mode: kChatRuntimeModeNormal,
      );

      await emitPlatformEvent('onAgentChatMessage', <String, dynamic>{
        'taskId': taskId,
        'message': '看起来克隆还没完全完成，只有 `.git` 目录。让我再等待一下，然后重新检查。',
        'isFinal': false,
      });

      await emitPlatformEvent('onAgentToolCallStart', <String, dynamic>{
        'taskId': taskId,
        'toolName': 'terminal_execute',
        'displayName': 'terminal_execute',
        'toolType': 'terminal',
        'summary': '检查 git 状态',
      });

      final textMessage = runtime.messages.firstWhere(
        (msg) => msg.id == '$taskId-text',
      );
      final toolMessage = runtime.messages.firstWhere(
        (msg) => msg.cardData?['type'] == 'agent_tool_summary',
      );

      expect(textMessage.text, contains('克隆还没完全完成'));
      expect(toolMessage.cardData?['toolType'], 'terminal');
      expect(runtime.pendingAgentTextTaskId, isNull);
    },
  );

  test('stores toolTitle from agent tool events on tool cards', () async {
    const conversationId = 4555;
    const taskId = 'agent-task-title';

    final runtime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );
    runtime.currentDispatchTaskId = taskId;
    coordinator.registerTask(
      taskId: taskId,
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );

    await emitPlatformEvent('onAgentToolCallStart', <String, dynamic>{
      'taskId': taskId,
      'toolName': 'file_read',
      'displayName': '读取文件',
      'toolType': 'workspace',
      'toolTitle': '查看配置',
      'summary': '查看配置',
      'argsJson': jsonEncode({'tool_title': '查看配置', 'path': 'README.md'}),
    });

    final toolMessage = runtime.messages.firstWhere(
      (msg) => msg.cardData?['type'] == 'agent_tool_summary',
    );

    expect(toolMessage.cardData?['toolTitle'], '查看配置');
  });

  test('persists deep thinking cards for history restoration', () async {
    const conversationId = 4666;
    const taskId = 'agent-task-thinking-persist';

    final runtime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );
    runtime.currentDispatchTaskId = taskId;
    coordinator.registerTask(
      taskId: taskId,
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );

    await emitPlatformEvent('onAgentThinkingStart', <String, dynamic>{
      'taskId': taskId,
    });
    await emitPlatformEvent('onAgentThinkingUpdate', <String, dynamic>{
      'taskId': taskId,
      'thinking': '恢复后也要能看到这段思考',
    });
    await Future<void>.delayed(Duration.zero);

    final upsertCall = recordedMethodCalls.lastWhere(
      (call) => call.method == 'upsertConversationUiCard',
    );
    final arguments = Map<String, dynamic>.from(
      upsertCall.arguments as Map<dynamic, dynamic>,
    );
    final cardData = Map<String, dynamic>.from(
      arguments['cardData'] as Map<dynamic, dynamic>,
    );
    final thinkingMessage = runtime.messages.firstWhere(
      (message) => message.id == '$taskId-thinking',
    );

    expect(arguments['conversationId'], conversationId);
    expect(arguments['mode'], 'normal');
    expect(arguments['entryId'], '$taskId-thinking');
    expect(
      arguments['createdAt'],
      thinkingMessage.createAt.millisecondsSinceEpoch,
    );
    expect(cardData['type'], 'deep_thinking');
    expect(cardData['thinkingContent'], '恢复后也要能看到这段思考');
  });

  test(
    'renders later content plus tool-call rounds as new assistant messages instead of overwriting earlier ones',
    () async {
      const conversationId = 4601;
      const taskId = 'agent-task-multi-round';

      final runtime = coordinator.ensureRuntime(
        conversationId: conversationId,
        mode: kChatRuntimeModeNormal,
      );
      runtime.currentDispatchTaskId = taskId;
      coordinator.registerTask(
        taskId: taskId,
        conversationId: conversationId,
        mode: kChatRuntimeModeNormal,
      );

      await emitPlatformEvent('onAgentChatMessage', <String, dynamic>{
        'taskId': taskId,
        'message': '第一轮：先检查仓库状态。',
        'isFinal': false,
      });

      await emitPlatformEvent('onAgentToolCallStart', <String, dynamic>{
        'taskId': taskId,
        'toolName': 'terminal_execute',
        'displayName': 'terminal_execute',
        'toolType': 'terminal',
        'summary': '检查 git 状态',
      });

      await emitPlatformEvent('onAgentToolCallComplete', <String, dynamic>{
        'taskId': taskId,
        'toolName': 'terminal_execute',
        'displayName': 'terminal_execute',
        'toolType': 'terminal',
        'summary': 'git 状态已返回',
        'success': true,
      });

      await emitPlatformEvent('onAgentChatMessage', <String, dynamic>{
        'taskId': taskId,
        'message': '第二轮：继续等待克隆完成。',
        'isFinal': false,
      });

      await emitPlatformEvent('onAgentChatMessage', <String, dynamic>{
        'taskId': taskId,
        'message': '第二轮：继续等待克隆完成，然后再次检查。',
        'isFinal': false,
      });

      final firstRoundMessage = runtime.messages.firstWhere(
        (msg) => msg.id == '$taskId-text',
      );
      final secondRoundMessage = runtime.messages.firstWhere(
        (msg) => msg.id == '$taskId-text-2',
      );

      expect(firstRoundMessage.text, '第一轮：先检查仓库状态。');
      expect(secondRoundMessage.text, '第二轮：继续等待克隆完成，然后再次检查。');
      expect(runtime.pendingAgentTextTaskId, taskId);
    },
  );

  test('forces tools layer when browser or terminal tools start', () async {
    const conversationId = 5001;
    const taskId = 'agent-tool-task';

    final runtime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );
    runtime.currentDispatchTaskId = taskId;
    coordinator.registerTask(
      taskId: taskId,
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );

    await emitPlatformEvent('onAgentToolCallStart', <String, dynamic>{
      'taskId': taskId,
      'toolName': 'browser_use',
      'displayName': 'browser_use',
      'toolType': 'browser',
      'summary': 'open browser',
    });

    expect(runtime.chatIslandDisplayLayer, ChatIslandDisplayLayer.tools);
    expect(runtime.lastAgentToolType, 'browser');

    await emitPlatformEvent('onAgentToolCallStart', <String, dynamic>{
      'taskId': taskId,
      'toolName': 'terminal_execute',
      'displayName': 'terminal_execute',
      'toolType': 'terminal',
      'summary': 'run terminal',
    });

    expect(runtime.chatIslandDisplayLayer, ChatIslandDisplayLayer.tools);
    expect(runtime.lastAgentToolType, 'terminal');
  });

  test('stores browser session snapshot when browser tool completes', () async {
    const conversationId = 6001;
    const taskId = 'agent-browser-task';
    const workspaceId = 'conversation_6001';

    final runtime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );
    runtime.currentDispatchTaskId = taskId;
    coordinator.registerTask(
      taskId: taskId,
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
    );

    await emitPlatformEvent('onAgentToolCallStart', <String, dynamic>{
      'taskId': taskId,
      'toolName': 'browser_use',
      'displayName': 'browser_use',
      'toolType': 'browser',
      'summary': 'browser start',
    });

    await emitPlatformEvent('onAgentToolCallComplete', <String, dynamic>{
      'taskId': taskId,
      'toolName': 'browser_use',
      'displayName': 'browser_use',
      'toolType': 'browser',
      'summary': 'browser ready',
      'workspaceId': workspaceId,
      'success': true,
      'rawResultJson': jsonEncode(<String, dynamic>{
        'activeTabId': 7,
        'currentUrl': 'https://example.com/login',
        'pageTitle': 'Sign In',
        'userAgentProfile': 'desktop_safari',
      }),
    });

    final snapshot = runtime.browserSessionSnapshot;
    expect(runtime.chatIslandDisplayLayer, ChatIslandDisplayLayer.tools);
    expect(runtime.lastAgentToolType, 'browser');
    expect(snapshot, isNotNull);
    expect(snapshot?.workspaceId, workspaceId);
    expect(snapshot?.activeTabId, 7);
    expect(snapshot?.currentUrl, 'https://example.com/login');
    expect(snapshot?.title, 'Sign In');
    expect(snapshot?.userAgentProfile, 'desktop_safari');
  });

  test('applies initial island layer when a runtime is created late', () {
    const conversationId = 7001;

    final runtime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
      initialChatIslandDisplayLayer: ChatIslandDisplayLayer.mode,
    );

    expect(runtime.chatIslandDisplayLayer, ChatIslandDisplayLayer.mode);

    final reused = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeNormal,
      initialChatIslandDisplayLayer: ChatIslandDisplayLayer.model,
    );

    expect(identical(runtime, reused), isTrue);
    expect(reused.chatIslandDisplayLayer, ChatIslandDisplayLayer.mode);
  });
}
