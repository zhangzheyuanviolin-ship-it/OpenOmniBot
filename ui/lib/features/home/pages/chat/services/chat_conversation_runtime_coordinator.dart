import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/features/home/pages/authorize/authorize_page_args.dart';
import 'package:ui/features/home/pages/command_overlay/constants/messages.dart';
import 'package:ui/features/home/pages/chat/mixins/agent_stream_handler.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/conversation_history_service.dart';
import 'package:ui/services/conversation_service.dart';
import 'package:ui/utils/data_parser.dart';

const String kChatRuntimeModeNormal = 'normal';
const String kChatRuntimeModeOpenClaw = 'openclaw';

class ChatConversationRuntimeState {
  ChatConversationRuntimeState({
    required this.conversationId,
    required this.mode,
  }) : chatIslandDisplayLayer = mode == kChatRuntimeModeNormal
           ? ChatIslandDisplayLayer.model
           : ChatIslandDisplayLayer.mode;

  final int conversationId;
  final String mode;

  ConversationModel? conversation;
  final List<ChatMessageModel> messages = <ChatMessageModel>[];
  final Map<String, String> currentAiMessages = <String, String>{};
  bool isAiResponding = false;
  bool isCheckingExecutableTask = false;
  bool isSubmittingVlmReply = false;
  String? vlmInfoQuestion;
  String deepThinkingContent = '';
  bool isDeepThinking = false;
  String? currentDispatchTaskId;
  int currentThinkingStage = 1;
  bool isInputAreaVisible = true;
  bool isExecutingTask = false;

  String? lastAgentTaskId;
  String? activeToolCardId;
  String? activeThinkingCardId;
  String? pendingAgentTextTaskId;
  bool pendingThinkingRoundSplit = false;
  int toolCardSequence = 0;
  int thinkingRound = 0;
  ChatIslandDisplayLayer chatIslandDisplayLayer;
  String? lastAgentToolType;
  ChatBrowserSessionSnapshot? browserSessionSnapshot;

  bool get hasInFlightTask =>
      isAiResponding ||
      isCheckingExecutableTask ||
      isExecutingTask ||
      currentDispatchTaskId != null ||
      currentAiMessages.isNotEmpty;
}

class _TaskBinding {
  const _TaskBinding({required this.conversationId, required this.mode});

  final int conversationId;
  final String mode;
}

class ChatConversationRuntimeCoordinator extends ChangeNotifier {
  ChatConversationRuntimeCoordinator._();

  static final ChatConversationRuntimeCoordinator instance =
      ChatConversationRuntimeCoordinator._();

  static const int _maxTerminalOutputChars = 64 * 1024;
  static const int _maxTerminalOutputLines = 600;
  static const Map<String, String> _executionPermissionNameToId =
      <String, String>{
        '无障碍权限': kAccessibilityPermissionId,
        '悬浮窗权限': kOverlayPermissionId,
      };

  final Map<String, ChatConversationRuntimeState> _runtimes =
      <String, ChatConversationRuntimeState>{};
  final Map<String, _TaskBinding> _taskBindings = <String, _TaskBinding>{};

  bool _initialized = false;

  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    AssistsMessageService.initialize();
    AssistsMessageService.setOnChatTaskMessageCallBack(_handleChatTaskMessage);
    AssistsMessageService.setOnChatTaskMessageEndCallBack(
      _handleChatTaskMessageEnd,
    );
    AssistsMessageService.setOnAgentThinkingStartCallback(
      _handleAgentThinkingStart,
    );
    AssistsMessageService.setOnAgentThinkingUpdateCallback(
      _handleAgentThinkingUpdate,
    );
    AssistsMessageService.setOnAgentToolCallStartCallback(
      _handleAgentToolCallStart,
    );
    AssistsMessageService.setOnAgentToolCallProgressCallback(
      _handleAgentToolCallProgress,
    );
    AssistsMessageService.setOnAgentToolCallCompleteCallback(
      _handleAgentToolCallComplete,
    );
    AssistsMessageService.setOnAgentChatMessageCallback(
      _handleAgentChatMessage,
    );
    AssistsMessageService.setOnAgentClarifyCallback(_handleAgentClarify);
    AssistsMessageService.setOnAgentCompleteCallback(_handleAgentComplete);
    AssistsMessageService.setOnAgentErrorCallback(_handleAgentError);
    AssistsMessageService.setOnAgentPermissionRequiredCallback(
      _handleAgentPermissionRequired,
    );
    AssistsMessageService.setOnVLMRequestUserInputCallBack(
      _handleVlmRequestUserInput,
    );
    AssistsMessageService.setOnVLMTaskFinishCallBack(_handleVlmTaskFinish);
  }

  ChatConversationRuntimeState? runtimeFor({
    required int conversationId,
    required String mode,
  }) {
    return _runtimes[_runtimeKey(conversationId: conversationId, mode: mode)];
  }

  ChatConversationRuntimeState ensureRuntime({
    required int conversationId,
    required String mode,
    List<ChatMessageModel>? initialMessages,
    ConversationModel? conversation,
  }) {
    final key = _runtimeKey(conversationId: conversationId, mode: mode);
    final runtime = _runtimes.putIfAbsent(
      key,
      () => ChatConversationRuntimeState(
        conversationId: conversationId,
        mode: mode,
      ),
    );
    if (runtime.messages.isEmpty && initialMessages != null) {
      runtime.messages
        ..clear()
        ..addAll(initialMessages);
    }
    if (conversation != null) {
      runtime.conversation = conversation;
    }
    return runtime;
  }

  void replaceConversationSnapshot({
    required int conversationId,
    required String mode,
    required List<ChatMessageModel> messages,
    ConversationModel? conversation,
    bool isAiResponding = false,
    bool isCheckingExecutableTask = false,
    bool isSubmittingVlmReply = false,
    String? vlmInfoQuestion,
    Map<String, String>? currentAiMessages,
    String deepThinkingContent = '',
    bool isDeepThinking = false,
    String? currentDispatchTaskId,
    int currentThinkingStage = 1,
    bool isInputAreaVisible = true,
    bool isExecutingTask = false,
    String? lastAgentTaskId,
    String? activeToolCardId,
    String? activeThinkingCardId,
    String? pendingAgentTextTaskId,
    bool pendingThinkingRoundSplit = false,
    int toolCardSequence = 0,
    int thinkingRound = 0,
    ChatIslandDisplayLayer chatIslandDisplayLayer = ChatIslandDisplayLayer.mode,
    String? lastAgentToolType,
    ChatBrowserSessionSnapshot? browserSessionSnapshot,
  }) {
    final runtime = ensureRuntime(
      conversationId: conversationId,
      mode: mode,
      conversation: conversation,
    );
    runtime.messages
      ..clear()
      ..addAll(messages);
    runtime.conversation = conversation ?? runtime.conversation;
    runtime.isAiResponding = isAiResponding;
    runtime.isCheckingExecutableTask = isCheckingExecutableTask;
    runtime.isSubmittingVlmReply = isSubmittingVlmReply;
    runtime.vlmInfoQuestion = vlmInfoQuestion;
    runtime.currentAiMessages
      ..clear()
      ..addAll(currentAiMessages ?? const <String, String>{});
    runtime.deepThinkingContent = deepThinkingContent;
    runtime.isDeepThinking = isDeepThinking;
    runtime.currentDispatchTaskId = currentDispatchTaskId;
    runtime.currentThinkingStage = currentThinkingStage;
    runtime.isInputAreaVisible = isInputAreaVisible;
    runtime.isExecutingTask = isExecutingTask;
    runtime.lastAgentTaskId = lastAgentTaskId;
    runtime.activeToolCardId = activeToolCardId;
    runtime.activeThinkingCardId = activeThinkingCardId;
    runtime.pendingAgentTextTaskId = pendingAgentTextTaskId;
    runtime.pendingThinkingRoundSplit = pendingThinkingRoundSplit;
    runtime.toolCardSequence = toolCardSequence;
    runtime.thinkingRound = thinkingRound;
    runtime.chatIslandDisplayLayer = chatIslandDisplayLayer;
    runtime.lastAgentToolType = lastAgentToolType;
    runtime.browserSessionSnapshot = browserSessionSnapshot;
    notifyListeners();
  }

  void registerTask({
    required String taskId,
    required int conversationId,
    required String mode,
  }) {
    ensureInitialized();
    ensureRuntime(conversationId: conversationId, mode: mode);
    _taskBindings[taskId] = _TaskBinding(
      conversationId: conversationId,
      mode: mode,
    );
  }

  void unregisterTask(String taskId) {
    _taskBindings.remove(taskId);
  }

  @visibleForTesting
  void resetForTest() {
    _runtimes.clear();
    _taskBindings.clear();
  }

  void clearConversationRuntimeSession({
    required int conversationId,
    required String mode,
  }) {
    final runtime = runtimeFor(conversationId: conversationId, mode: mode);
    if (runtime == null) return;
    runtime.currentDispatchTaskId = null;
    runtime.deepThinkingContent = '';
    runtime.isDeepThinking = false;
    runtime.currentThinkingStage = ThinkingStage.thinking.value;
    runtime.lastAgentTaskId = null;
    runtime.pendingAgentTextTaskId = null;
    runtime.activeToolCardId = null;
    runtime.activeThinkingCardId = null;
    runtime.pendingThinkingRoundSplit = false;
    runtime.toolCardSequence = 0;
    runtime.thinkingRound = 0;
    notifyListeners();
  }

  void interruptActiveToolCard({
    required int conversationId,
    required String mode,
    String? summary,
  }) {
    final runtime = runtimeFor(conversationId: conversationId, mode: mode);
    if (runtime == null) return;
    final cardId = runtime.activeToolCardId;
    if (cardId == null) return;

    final index = runtime.messages.indexWhere((msg) => msg.id == cardId);
    if (index == -1) {
      runtime.activeToolCardId = null;
      notifyListeners();
      return;
    }

    final existingCardData = Map<String, dynamic>.from(
      runtime.messages[index].cardData ?? const {},
    );
    existingCardData['status'] = 'interrupted';
    existingCardData['success'] = false;
    if (summary != null && summary.trim().isNotEmpty) {
      existingCardData['summary'] = summary.trim();
    }
    runtime.messages[index] = runtime.messages[index].copyWith(
      content: {'cardData': existingCardData, 'id': cardId},
    );
    runtime.activeToolCardId = null;
    notifyListeners();
  }

  Future<void> persistRuntimeConversation({
    required int conversationId,
    required String mode,
    bool generateSummary = false,
    bool markComplete = false,
  }) async {
    final runtime = runtimeFor(conversationId: conversationId, mode: mode);
    if (runtime == null || runtime.messages.isEmpty) return;

    final snapshotMessages = List<ChatMessageModel>.from(runtime.messages);
    final snapshotConversation = runtime.conversation;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastMessage = snapshotMessages.isNotEmpty
        ? (snapshotMessages[0].text ?? '')
        : '';
    final messageCount = snapshotMessages.length;
    final firstUserMessage = snapshotMessages.firstWhere(
      (m) => m.user == 1,
      orElse: () => ChatMessageModel.userMessage("default"),
    );
    final userText = firstUserMessage.text ?? 'conversation';
    final title = userText.length > 20
        ? '${userText.substring(0, 20)}...'
        : userText;

    String? summary = snapshotConversation?.summary;
    if (generateSummary) {
      final history = _buildConversationHistoryText(snapshotMessages);
      summary = history.isEmpty
          ? null
          : await ConversationService.generateConversationSummary(
              conversationHistory: history,
            );
    }

    await ConversationHistoryService.saveConversationMessages(
      conversationId,
      snapshotMessages,
    );

    final baseConversation =
        snapshotConversation ??
        ConversationModel(
          id: conversationId,
          title: title,
          summary: summary,
          status: 0,
          lastMessage: lastMessage,
          messageCount: messageCount,
          createdAt: now,
          updatedAt: now,
        );

    final updatedConversation = baseConversation.copyWith(
      title: baseConversation.title.isEmpty ? title : baseConversation.title,
      summary: summary ?? baseConversation.summary,
      lastMessage: lastMessage,
      messageCount: messageCount,
      updatedAt: now,
    );

    await ConversationService.updateConversation(updatedConversation);
    runtime.conversation = updatedConversation;
    if (markComplete) {
      await ConversationService.completeConversation(conversationId);
    }
  }

  void _handleChatTaskMessage(String taskId, String content, String? type) {
    final runtime = _runtimeForTask(taskId);
    if (runtime == null) return;

    final isErrorMessage = type == 'error';
    final isRateLimited = type == 'rate_limited';
    final isSummaryStart = type == 'summary_start';
    final isOpenClawAttachment = type == 'openclaw_attachment';
    final payload = safeDecodeMap(content);
    final payloadAttachments = _parseAttachments(payload['attachments']);

    String messageText;
    bool isError;
    bool isSummarizing;

    final isFirstChunk = !runtime.currentAiMessages.containsKey(taskId);
    if (isFirstChunk) {
      _removeLatestLoadingIfExists(runtime);
    }

    if (isRateLimited) {
      messageText = kRateLimitErrorMessage;
      isError = true;
      isSummarizing = false;
      runtime.currentAiMessages.remove(taskId);
    } else if (isErrorMessage &&
        _isOpenClawGatewayInitializingError(runtime, content)) {
      messageText = kOpenClawGatewayInitializingMessage;
      isError = false;
      isSummarizing = false;
      runtime.currentAiMessages.remove(taskId);
    } else if (isErrorMessage) {
      messageText = kNetworkErrorMessage;
      isError = true;
      isSummarizing = false;
      runtime.currentAiMessages.remove(taskId);
    } else if (isSummaryStart) {
      messageText = '';
      isError = false;
      isSummarizing = true;
      runtime.currentAiMessages[taskId] = '';
    } else if (isOpenClawAttachment) {
      messageText = runtime.currentAiMessages[taskId] ?? '';
      isError = false;
      isSummarizing = false;
    } else {
      final text = (payload['text'] ?? '').toString();
      runtime.currentAiMessages[taskId] =
          (runtime.currentAiMessages[taskId] ?? '') + text;
      messageText = runtime.currentAiMessages[taskId] ?? '';
      isError = false;
      isSummarizing = false;
    }

    _removeOpenClawWaitingCard(runtime, taskId);
    _updateOrAddAiMessage(
      runtime,
      taskId,
      messageText,
      isError,
      isSummarizing: isSummarizing,
      attachments: payloadAttachments,
    );
    runtime.isAiResponding = true;
    notifyListeners();
  }

  void _handleChatTaskMessageEnd(String taskId) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

    runtime.isAiResponding = false;
    final index = runtime.messages.indexWhere((msg) => msg.id == taskId);
    final isErrorMessage = index != -1 && runtime.messages[index].isError;
    final messageText = isErrorMessage
        ? (runtime.messages[index].content?['text'] as String? ?? '')
        : (runtime.currentAiMessages[taskId] ?? '');

    if (messageText.isNotEmpty && index != -1) {
      final existing = runtime.messages[index];
      runtime.messages[index] = existing.copyWith(content: existing.content);
    }
    runtime.currentAiMessages.remove(taskId);
    _taskBindings.remove(taskId);
    notifyListeners();
    unawaited(
      persistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
        markComplete: true,
      ),
    );
  }

  void _handleAgentThinkingStart(String taskId) {
    final runtime = _runtimeForTask(taskId);
    if (runtime == null) return;

    final resolvedTaskId =
        runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (resolvedTaskId == null || resolvedTaskId != taskId) return;

    runtime.lastAgentTaskId = taskId;
    runtime.currentThinkingStage = ThinkingStage.thinking.value;
    runtime.isDeepThinking = true;

    if (runtime.thinkingRound == 0) {
      runtime.thinkingRound = 1;
      runtime.activeThinkingCardId = _baseThinkingCardId(taskId);
      final exists = runtime.messages.any(
        (msg) => msg.id == runtime.activeThinkingCardId,
      );
      if (exists) {
        _updateThinkingCard(
          runtime,
          taskId,
          cardId: runtime.activeThinkingCardId,
          isLoading: true,
          stage: ThinkingStage.thinking.value,
        );
      } else {
        _createThinkingCard(
          runtime,
          taskId,
          cardId: runtime.activeThinkingCardId,
          isLoading: true,
          stage: ThinkingStage.thinking.value,
        );
      }
      notifyListeners();
      return;
    }

    runtime.pendingThinkingRoundSplit = true;
    notifyListeners();
  }

  void _handleAgentThinkingUpdate(String taskId, String thinking) {
    final runtime = _runtimeForTask(taskId);
    if (runtime == null) return;
    final resolvedTaskId =
        runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (resolvedTaskId == null || resolvedTaskId != taskId) return;

    if (runtime.pendingThinkingRoundSplit) {
      if (thinking.trim().isEmpty) {
        return;
      }

      final previousThinkingCardId = _resolveThinkingCardId(runtime, taskId);
      if (previousThinkingCardId != null) {
        _updateThinkingCard(
          runtime,
          taskId,
          cardId: previousThinkingCardId,
          isLoading: false,
          stage: ThinkingStage.complete.value,
          lockCompleted: false,
        );
      }

      runtime.thinkingRound += 1;
      runtime.activeThinkingCardId =
          '$taskId-thinking-${runtime.thinkingRound}';
      _createThinkingCard(
        runtime,
        taskId,
        cardId: runtime.activeThinkingCardId,
        thinkingContent: thinking,
        isLoading: true,
        stage: ThinkingStage.thinking.value,
      );
      runtime.deepThinkingContent = thinking;
      runtime.pendingThinkingRoundSplit = false;
      notifyListeners();
      return;
    }

    runtime.deepThinkingContent = thinking;
    final thinkingCardId = _resolveThinkingCardId(runtime, taskId);
    if (thinkingCardId == null) return;

    _updateThinkingCard(
      runtime,
      taskId,
      cardId: thinkingCardId,
      thinkingContent: thinking,
      isLoading: true,
      stage: runtime.currentThinkingStage,
    );
    notifyListeners();
  }

  void _handleAgentToolCallStart(AgentToolEventData event) {
    final runtime = _runtimeForTask(event.taskId);
    if (runtime == null) return;
    final taskId = runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (taskId == null || taskId != event.taskId) return;

    _updateToolLayerState(runtime, event);

    _clearPendingAgentTextIfNeeded(runtime, taskId);
    runtime.currentThinkingStage = ThinkingStage.toolCall.value;
    runtime.toolCardSequence += 1;
    runtime.activeToolCardId = '$taskId-tool-${runtime.toolCardSequence}';
    _upsertToolCard(
      runtime: runtime,
      taskId: taskId,
      cardId: runtime.activeToolCardId!,
      event: event,
      status: 'running',
      summary: event.summary.isNotEmpty ? event.summary : '正在调用工具',
      progress: event.progress,
      resultPreviewJson: event.resultPreviewJson,
      rawResultJson: event.rawResultJson,
    );
    final thinkingCardId = _resolveThinkingCardId(runtime, taskId);
    if (thinkingCardId != null) {
      _updateThinkingCard(
        runtime,
        taskId,
        cardId: thinkingCardId,
        isLoading: runtime.isDeepThinking,
        stage: ThinkingStage.toolCall.value,
      );
    }
    notifyListeners();
  }

  void _handleAgentToolCallProgress(AgentToolEventData event) {
    final runtime = _runtimeForTask(event.taskId);
    if (runtime == null) return;
    final taskId = runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (taskId == null || taskId != event.taskId) return;

    _updateToolLayerState(runtime, event);

    final cardId = runtime.activeToolCardId;
    if (cardId == null) return;
    _upsertToolCard(
      runtime: runtime,
      taskId: taskId,
      cardId: cardId,
      event: event,
      status: 'running',
      summary: event.summary.isNotEmpty ? event.summary : '正在调用工具',
      progress: event.progress,
      resultPreviewJson: event.resultPreviewJson,
      rawResultJson: event.rawResultJson,
    );
    notifyListeners();
  }

  void _handleAgentToolCallComplete(AgentToolEventData event) {
    final runtime = _runtimeForTask(event.taskId);
    if (runtime == null) return;
    final taskId = runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    final cardId = runtime.activeToolCardId;
    if (taskId == null || taskId != event.taskId || cardId == null) return;

    _updateToolLayerState(runtime, event);

    _upsertToolCard(
      runtime: runtime,
      taskId: taskId,
      cardId: cardId,
      event: event,
      status: _resolveToolStatus(event),
      summary: event.summary,
      progress: event.progress,
      resultPreviewJson: event.resultPreviewJson,
      rawResultJson: event.rawResultJson,
    );
    runtime.activeToolCardId = null;
    _updateBrowserSessionSnapshot(runtime, event);
    notifyListeners();
  }

  void _handleAgentChatMessage(
    String taskId,
    String message, {
    bool isFinal = true,
  }) {
    final runtime = _runtimeForTask(taskId);
    if (runtime == null) return;
    final resolvedTaskId =
        runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (resolvedTaskId == null || resolvedTaskId != taskId) return;

    final aiTextMessageId = '$taskId-text';
    final index = runtime.messages.indexWhere(
      (msg) => msg.id == aiTextMessageId,
    );
    if (index == -1) {
      runtime.messages.insert(
        0,
        ChatMessageModel(
          id: aiTextMessageId,
          type: 1,
          user: 2,
          content: {'text': message, 'id': aiTextMessageId},
        ),
      );
    } else {
      final existing = runtime.messages[index];
      final content = Map<String, dynamic>.from(existing.content ?? {});
      content['text'] = message;
      runtime.messages[index] = existing.copyWith(content: content);
    }
    if (isFinal) {
      runtime.isAiResponding = false;
    }
    runtime.pendingAgentTextTaskId = isFinal ? null : taskId;
    if (isFinal && runtime.currentDispatchTaskId == null) {
      runtime.lastAgentTaskId = null;
    }
    notifyListeners();
    if (isFinal) {
      final binding = _taskBindings[taskId];
      if (binding != null) {
        unawaited(
          persistRuntimeConversation(
            conversationId: binding.conversationId,
            mode: binding.mode,
            markComplete: true,
          ),
        );
      }
    }
  }

  void _handleAgentClarify(
    String taskId,
    String question,
    List<String> missingFields,
  ) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null ||
        runtime == null ||
        runtime.currentDispatchTaskId == null) {
      return;
    }

    runtime.currentThinkingStage = ThinkingStage.complete.value;
    runtime.isDeepThinking = false;
    final thinkingCardId = _resolveThinkingCardId(runtime, taskId);
    if (thinkingCardId != null) {
      _updateThinkingCard(
        runtime,
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    final textId = '$taskId-text';
    final index = runtime.messages.indexWhere((msg) => msg.id == textId);
    if (index == -1) {
      runtime.messages.insert(
        0,
        ChatMessageModel(
          id: textId,
          type: 1,
          user: 2,
          content: {'text': question, 'id': textId},
        ),
      );
    } else {
      runtime.messages[index] = runtime.messages[index].copyWith(
        content: {'text': question, 'id': textId},
      );
    }
    runtime.isAiResponding = false;
    runtime.currentDispatchTaskId = null;
    clearConversationRuntimeSession(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
    notifyListeners();
    unawaited(
      persistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
        markComplete: true,
      ),
    );
  }

  void _handleAgentComplete(
    String taskId,
    bool success,
    String outputKind,
    bool hasUserVisibleOutput,
  ) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

    runtime.currentThinkingStage = ThinkingStage.complete.value;
    runtime.isDeepThinking = false;
    final thinkingCardId = _resolveThinkingCardId(runtime, taskId);
    if (thinkingCardId != null) {
      _updateThinkingCard(
        runtime,
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    if (success) {
      final normalizedOutputKind = outputKind.trim().toLowerCase();
      final hasVisibleOutput = runtime.messages.any((msg) {
        if (!msg.id.startsWith(taskId)) return false;
        if (msg.type == 1 && msg.user == 2) return true;
        final cardType = msg.cardData?['type'] as String?;
        return cardType == 'agent_tool_summary' ||
            cardType == 'permission_section';
      });
      final shouldInjectFallback =
          normalizedOutputKind == 'none' &&
          !hasUserVisibleOutput &&
          !hasVisibleOutput;
      if (shouldInjectFallback) {
        final fallbackId = '$taskId-text';
        final index = runtime.messages.indexWhere(
          (msg) => msg.id == fallbackId,
        );
        if (index == -1) {
          runtime.messages.insert(
            0,
            ChatMessageModel(
              id: fallbackId,
              type: 1,
              user: 2,
              content: {'text': '暂时无法生成回复，请重试。', 'id': fallbackId},
            ),
          );
        }
      }
      runtime.isAiResponding = false;
      runtime.currentDispatchTaskId = null;
      clearConversationRuntimeSession(
        conversationId: binding.conversationId,
        mode: binding.mode,
      );
      _taskBindings.remove(taskId);
      notifyListeners();
      unawaited(
        persistRuntimeConversation(
          conversationId: binding.conversationId,
          mode: binding.mode,
          markComplete: true,
        ),
      );
      return;
    }

    runtime.isAiResponding = false;
    runtime.currentDispatchTaskId = null;
    clearConversationRuntimeSession(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
    _taskBindings.remove(taskId);
    notifyListeners();
    unawaited(
      persistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
        markComplete: true,
      ),
    );
  }

  void _handleAgentError(String taskId, String error) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

    runtime.currentThinkingStage = ThinkingStage.complete.value;
    runtime.isDeepThinking = false;
    final thinkingCardId = _resolveThinkingCardId(runtime, taskId);
    if (thinkingCardId != null) {
      _updateThinkingCard(
        runtime,
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    final textId = '$taskId-text';
    final message = error.trim().isEmpty
        ? '暂时无法生成回复，请重试。'
        : '暂时无法生成回复，请重试。${error.trim()}';
    final index = runtime.messages.indexWhere((msg) => msg.id == textId);
    if (index == -1) {
      runtime.messages.insert(
        0,
        ChatMessageModel(
          id: textId,
          type: 1,
          user: 2,
          content: {'text': message, 'id': textId},
          isError: true,
        ),
      );
    } else {
      runtime.messages[index] = runtime.messages[index].copyWith(
        content: {'text': message, 'id': textId},
        isError: true,
      );
    }
    runtime.isAiResponding = false;
    runtime.currentDispatchTaskId = null;
    clearConversationRuntimeSession(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
    _taskBindings.remove(taskId);
    notifyListeners();
    unawaited(
      persistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
        markComplete: true,
      ),
    );
  }

  void _handleAgentPermissionRequired(String taskId, List<String> missing) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null ||
        runtime == null ||
        runtime.currentDispatchTaskId == null) {
      return;
    }

    runtime.currentThinkingStage = ThinkingStage.complete.value;
    runtime.isDeepThinking = false;
    final thinkingCardId = _resolveThinkingCardId(runtime, taskId);
    if (thinkingCardId != null) {
      _updateThinkingCard(
        runtime,
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    final executionPermissionIds = missing
        .map((item) => item.trim())
        .map((item) => _executionPermissionNameToId[item])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final shouldShowPermissionCard =
        executionPermissionIds.isNotEmpty &&
        executionPermissionIds.length == missing.length;
    final names = missing.join('、');
    final message = names.isEmpty ? '执行任务前需要先开启权限' : '执行任务前，请先开启：$names';

    interruptActiveToolCard(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );

    final textMessageId = '$taskId-text';
    final cardMessageId = '$taskId-permission';
    runtime.messages.insert(
      0,
      ChatMessageModel(
        id: textMessageId,
        type: 1,
        user: 2,
        content: {'text': message, 'id': textMessageId},
      ),
    );
    if (shouldShowPermissionCard) {
      runtime.messages.insert(
        0,
        ChatMessageModel(
          id: cardMessageId,
          type: 2,
          user: 3,
          content: {
            'cardData': {
              'type': 'permission_section',
              'requiredPermissionIds': executionPermissionIds,
            },
            'id': cardMessageId,
          },
        ),
      );
    }
    runtime.isAiResponding = false;
    runtime.currentDispatchTaskId = null;
    clearConversationRuntimeSession(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
    _taskBindings.remove(taskId);
    notifyListeners();
    unawaited(
      persistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
        markComplete: true,
      ),
    );
  }

  void _handleVlmTaskFinish(String? taskId) {
    if (taskId == null || taskId.isEmpty) return;
    final binding = _taskBindings[taskId];
    if (binding == null) return;
    final runtime = _runtimeForTask(taskId);
    if (runtime == null) return;
    runtime.isExecutingTask = false;
    runtime.isInputAreaVisible = true;
    runtime.vlmInfoQuestion = null;
    runtime.isSubmittingVlmReply = false;
    _taskBindings.remove(taskId);
    notifyListeners();
    unawaited(
      persistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
        generateSummary: true,
        markComplete: true,
      ),
    );
  }

  void _handleVlmRequestUserInput(String question, String? taskId) {
    if (taskId == null || taskId.isEmpty) return;
    final runtime = _runtimeForTask(taskId);
    if (runtime == null) return;
    runtime.vlmInfoQuestion = question;
    runtime.isSubmittingVlmReply = false;
    notifyListeners();
  }

  ChatConversationRuntimeState? _runtimeForTask(String taskId) {
    final binding = _taskBindings[taskId];
    if (binding == null) return null;
    return ensureRuntime(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _removeLatestLoadingIfExists(ChatConversationRuntimeState runtime) {
    if (runtime.messages.isNotEmpty && runtime.messages[0].isLoading) {
      runtime.messages.removeAt(0);
    }
  }

  void _updateOrAddAiMessage(
    ChatConversationRuntimeState runtime,
    String taskId,
    String text,
    bool isError, {
    bool isSummarizing = false,
    List<Map<String, dynamic>> attachments = const [],
  }) {
    final index = runtime.messages.indexWhere((msg) => msg.id == taskId);
    if (index == -1) {
      final content = <String, dynamic>{'text': text, 'id': taskId};
      if (attachments.isNotEmpty) {
        content['attachments'] = attachments;
      }
      runtime.messages.insert(
        0,
        ChatMessageModel(
          id: taskId,
          type: 1,
          user: 2,
          content: content,
          isLoading: false,
          isError: isError,
          isSummarizing: isSummarizing,
        ),
      );
      return;
    }

    final existing = runtime.messages[index];
    final content = Map<String, dynamic>.from(existing.content ?? {});
    final existingText = content['text'] as String? ?? '';
    content['text'] = text.isNotEmpty ? text : existingText;
    final mergedAttachments = _mergeAttachments(
      _parseAttachments(content['attachments']),
      attachments,
    );
    if (mergedAttachments.isNotEmpty) {
      content['attachments'] = mergedAttachments;
    }
    runtime.messages[index] = existing.copyWith(
      content: content,
      isLoading: false,
      isError: isError,
      isSummarizing: isSummarizing,
    );
  }

  List<Map<String, dynamic>> _parseAttachments(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  List<Map<String, dynamic>> _mergeAttachments(
    List<Map<String, dynamic>> previous,
    List<Map<String, dynamic>> latest,
  ) {
    if (previous.isEmpty) return latest;
    if (latest.isEmpty) return previous;
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addAll(List<Map<String, dynamic>> source) {
      for (final item in source) {
        final key = _attachmentIdentity(item);
        if (!seen.add(key)) continue;
        merged.add(item);
      }
    }

    addAll(previous);
    addAll(latest);
    return merged;
  }

  String _attachmentIdentity(Map<String, dynamic> item) {
    final id = (item['id'] as String? ?? '').trim();
    if (id.isNotEmpty) return id;
    final path = (item['path'] as String? ?? '').trim();
    if (path.isNotEmpty) return path;
    final url = (item['url'] as String? ?? '').trim();
    if (url.isNotEmpty) return url;
    final name = (item['name'] as String? ?? '').trim();
    final fileName = (item['fileName'] as String? ?? '').trim();
    return '$name|$fileName|${item['size']}';
  }

  void _createThinkingCard(
    ChatConversationRuntimeState runtime,
    String taskId, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
  }) {
    final loadingIndex = runtime.messages.indexWhere((msg) => msg.id == taskId);
    if (loadingIndex != -1) {
      runtime.messages.removeAt(loadingIndex);
    }

    final startTime = DateTime.now().millisecondsSinceEpoch;
    final thinkingCardId = cardId ?? '$taskId-thinking';
    final cardData = {
      'type': 'deep_thinking',
      'isLoading': isLoading ?? runtime.isDeepThinking,
      'thinkingContent': thinkingContent ?? '',
      'stage': stage ?? runtime.currentThinkingStage,
      'taskID': taskId,
      'startTime': startTime,
      'endTime': null,
    };

    runtime.messages.removeWhere((msg) => msg.id == thinkingCardId);
    runtime.messages.insert(
      0,
      ChatMessageModel(
        id: thinkingCardId,
        type: 2,
        user: 3,
        content: {'cardData': cardData, 'id': thinkingCardId},
      ),
    );
  }

  void _updateThinkingCard(
    ChatConversationRuntimeState runtime,
    String taskId, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
    bool lockCompleted = true,
  }) {
    final thinkingCardId = cardId ?? '$taskId-thinking';
    final index = runtime.messages.indexWhere(
      (msg) => msg.id == thinkingCardId,
    );
    if (index == -1) return;

    final existing = runtime.messages[index];
    final content = Map<String, dynamic>.from(existing.content ?? {});
    final cardData = Map<String, dynamic>.from(content['cardData'] ?? {});

    final currentStage = cardData['stage'] as int? ?? 1;
    final targetStage = stage ?? runtime.currentThinkingStage;
    final newStage = (lockCompleted && currentStage == 4) ? 4 : targetStage;

    final startTime = cardData['startTime'] as int?;
    int? endTime = cardData['endTime'] as int?;
    if (newStage == 4 && endTime == null) {
      endTime = DateTime.now().millisecondsSinceEpoch;
    }

    cardData['thinkingContent'] =
        thinkingContent ?? runtime.deepThinkingContent;
    cardData['isLoading'] = isLoading ?? runtime.isDeepThinking;
    cardData['stage'] = newStage;
    cardData['taskID'] = taskId;
    cardData['startTime'] = startTime;
    cardData['endTime'] = endTime;

    content['cardData'] = cardData;
    runtime.messages[index] = existing.copyWith(content: content);
  }

  String _baseThinkingCardId(String taskId) => '$taskId-thinking';

  String? _resolveThinkingCardId(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    if (runtime.activeThinkingCardId != null) {
      return runtime.activeThinkingCardId;
    }
    final baseId = _baseThinkingCardId(taskId);
    final exists = runtime.messages.any((msg) => msg.id == baseId);
    return exists ? baseId : null;
  }

  void _clearPendingAgentTextIfNeeded(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    if (runtime.pendingAgentTextTaskId != taskId) return;
    final pendingTextMessageId = '$taskId-text';
    runtime.messages.removeWhere((msg) => msg.id == pendingTextMessageId);
    runtime.pendingAgentTextTaskId = null;
  }

  void _upsertToolCard({
    required ChatConversationRuntimeState runtime,
    required String taskId,
    required String cardId,
    required AgentToolEventData event,
    required String status,
    required String summary,
    required String progress,
    required String resultPreviewJson,
    required String rawResultJson,
  }) {
    final index = runtime.messages.indexWhere((msg) => msg.id == cardId);
    final existingCardData = index == -1
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(
            runtime.messages[index].cardData ?? const {},
          );
    final existingTerminalOutput = (existingCardData['terminalOutput'] ?? '')
        .toString();
    final terminalOutput = event.toolType == 'terminal'
        ? _resolveTerminalOutput(existing: existingTerminalOutput, event: event)
        : '';
    final cardData = {
      'type': 'agent_tool_summary',
      'taskId': taskId,
      'cardId': cardId,
      'toolName': event.toolName,
      'displayName': event.displayName,
      'toolType': event.toolType,
      'serverName': event.serverName,
      'status': status,
      'summary': summary.isNotEmpty
          ? summary
          : (existingCardData['summary'] ?? '').toString(),
      'progress': progress.isNotEmpty
          ? progress
          : (existingCardData['progress'] ?? '').toString(),
      'argsJson': event.argsJson.isNotEmpty
          ? event.argsJson
          : (existingCardData['argsJson'] ?? '').toString(),
      'resultPreviewJson': resultPreviewJson.isNotEmpty
          ? resultPreviewJson
          : (existingCardData['resultPreviewJson'] ?? '').toString(),
      'rawResultJson': rawResultJson.isNotEmpty
          ? rawResultJson
          : (existingCardData['rawResultJson'] ?? '').toString(),
      'terminalOutput': terminalOutput,
      'terminalOutputDelta': event.terminalOutputDelta,
      'terminalSessionId':
          event.terminalSessionId ?? existingCardData['terminalSessionId'],
      'terminalStreamState': event.terminalStreamState.isNotEmpty
          ? event.terminalStreamState
          : (existingCardData['terminalStreamState'] ?? '').toString(),
      'workspaceId': event.workspaceId ?? existingCardData['workspaceId'],
      'artifacts': event.artifacts.isNotEmpty
          ? event.artifacts
          : (existingCardData['artifacts'] ?? const []),
      'actions': event.actions.isNotEmpty
          ? event.actions
          : (existingCardData['actions'] ?? const []),
      'success': event.success,
      'showTerminalOutput': event.toolType == 'terminal',
      'showRawResult': event.rawResultJson.isNotEmpty,
      'showArtifactAction': event.artifacts.isNotEmpty,
      'showScheduleAction': event.toolType == 'schedule',
      'showAlarmAction': event.toolType == 'alarm',
    };

    if (index == -1) {
      runtime.messages.insert(
        0,
        ChatMessageModel.cardMessage(cardData, id: cardId),
      );
    } else {
      runtime.messages[index] = runtime.messages[index].copyWith(
        content: {'cardData': cardData, 'id': cardId},
      );
    }
  }

  String _resolveTerminalOutput({
    required String existing,
    required AgentToolEventData event,
  }) {
    if (event.terminalOutput.isNotEmpty) {
      return _trimTerminalOutput(event.terminalOutput);
    }
    if (event.terminalOutputDelta.isNotEmpty) {
      return _trimTerminalOutput(existing + event.terminalOutputDelta);
    }
    return existing;
  }

  String _resolveToolStatus(AgentToolEventData event) {
    final normalized = event.status.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return event.success ? 'success' : 'error';
  }

  void updateChatIslandDisplayLayer({
    required int conversationId,
    required String mode,
    required ChatIslandDisplayLayer layer,
  }) {
    final runtime = runtimeFor(conversationId: conversationId, mode: mode);
    if (runtime == null || runtime.chatIslandDisplayLayer == layer) {
      return;
    }
    runtime.chatIslandDisplayLayer = layer;
    notifyListeners();
  }

  void _updateToolLayerState(
    ChatConversationRuntimeState runtime,
    AgentToolEventData event,
  ) {
    final toolType = event.toolType.trim();
    if (toolType != 'terminal' && toolType != 'browser') {
      return;
    }
    runtime.lastAgentToolType = toolType;
    runtime.chatIslandDisplayLayer = ChatIslandDisplayLayer.tools;
  }

  void _updateBrowserSessionSnapshot(
    ChatConversationRuntimeState runtime,
    AgentToolEventData event,
  ) {
    if (event.toolType.trim() != 'browser') {
      return;
    }
    final workspaceId = (event.workspaceId ?? '').trim();
    if (!event.success || workspaceId.isEmpty) {
      return;
    }
    final snapshot =
        ChatBrowserSessionSnapshot.tryParseBrowserToolJson(
          rawJson: event.rawResultJson,
          workspaceId: workspaceId,
        ) ??
        ChatBrowserSessionSnapshot.tryParseBrowserToolJson(
          rawJson: event.resultPreviewJson,
          workspaceId: workspaceId,
        );
    if (snapshot == null) {
      return;
    }
    runtime.browserSessionSnapshot = snapshot;
  }

  String _trimTerminalOutput(String value) {
    if (value.isEmpty) return value;

    var candidate = value;
    if (candidate.length > _maxTerminalOutputChars) {
      candidate = candidate.substring(
        candidate.length - _maxTerminalOutputChars,
      );
    }

    final lines = candidate.split('\n');
    if (lines.length > _maxTerminalOutputLines) {
      candidate = lines
          .sublist(lines.length - _maxTerminalOutputLines)
          .join('\n');
    }

    final wasTrimmed =
        candidate.length < value.length ||
        lines.length > _maxTerminalOutputLines;
    if (!wasTrimmed) {
      return candidate;
    }

    const notice = '[只显示最近的部分终端输出]\n';
    final body = candidate.startsWith(notice)
        ? candidate.substring(notice.length)
        : candidate;
    final remaining = _maxTerminalOutputChars - notice.length;
    return '$notice${body.substring(body.length > remaining ? body.length - remaining : 0)}';
  }

  void _removeOpenClawWaitingCard(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    final waitingCardId = '$taskId-openclaw-waiting';
    runtime.messages.removeWhere((msg) => msg.id == waitingCardId);
  }

  bool _isOpenClawGatewayInitializingError(
    ChatConversationRuntimeState runtime,
    String rawContent,
  ) {
    if (runtime.mode != kChatRuntimeModeOpenClaw) {
      return false;
    }
    final payload = safeDecodeMap(rawContent);
    final text = (payload['text'] ?? payload['message'] ?? rawContent)
        .toString()
        .trim()
        .toLowerCase();
    if (text.isEmpty) {
      return false;
    }

    final hasOpenClawContext =
        text.contains('openclaw') ||
        text.contains('gateway') ||
        text.contains('127.0.0.1') ||
        text.contains('localhost') ||
        text.contains('18789');
    if (!hasOpenClawContext) {
      return false;
    }

    return text.contains('econnrefused') ||
        text.contains('connection refused') ||
        text.contains('fetch failed') ||
        text.contains('connect error') ||
        text.contains('socket hang up') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('initializing') ||
        text.contains('not ready') ||
        text.contains('starting') ||
        text.contains('restarting') ||
        text.contains('初始化') ||
        text.contains('启动中');
  }

  String _buildConversationHistoryText(List<ChatMessageModel> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      if (message.user != 1) continue;
      final text = message.content?['text'] as String? ?? '';
      if (text.isEmpty) continue;
      buffer.write('用户: $text\n');
    }
    return buffer.toString().trim();
  }

  String _runtimeKey({required int conversationId, required String mode}) {
    return '$mode:$conversationId';
  }
}
