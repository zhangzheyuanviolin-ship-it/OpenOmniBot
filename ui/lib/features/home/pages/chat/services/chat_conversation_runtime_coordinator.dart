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
  bool isContextCompressing = false;
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

class _PendingPersistenceRequest {
  _PendingPersistenceRequest({
    required this.conversationId,
    required this.mode,
    required this.timer,
    this.generateSummary = false,
    this.markComplete = false,
  });

  final int conversationId;
  final String mode;
  final Timer timer;
  final bool generateSummary;
  final bool markComplete;
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
        '应用列表读取权限': kInstalledAppsPermissionId,
        '公共文件访问': kPublicStoragePermissionId,
      };

  String _agentTextBaseId(String taskId) => '$taskId-text';

  final Map<String, ChatConversationRuntimeState> _runtimes =
      <String, ChatConversationRuntimeState>{};
  final Map<String, _TaskBinding> _taskBindings = <String, _TaskBinding>{};
  final Map<String, _PendingPersistenceRequest> _pendingPersistence =
      <String, _PendingPersistenceRequest>{};

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
    AssistsMessageService.setOnAgentPromptTokenUsageCallback(
      _handleAgentPromptTokenUsageChanged,
    );
    AssistsMessageService.setOnAgentContextCompactionStateCallback(
      _handleAgentContextCompactionStateChanged,
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
    ChatIslandDisplayLayer? initialChatIslandDisplayLayer,
  }) {
    final key = _runtimeKey(conversationId: conversationId, mode: mode);
    final existing = _runtimes[key];
    final runtime =
        existing ??
        ChatConversationRuntimeState(
          conversationId: conversationId,
          mode: mode,
        );
    if (existing == null) {
      if (initialChatIslandDisplayLayer != null) {
        runtime.chatIslandDisplayLayer = initialChatIslandDisplayLayer;
      }
      _runtimes[key] = runtime;
    }
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
    bool isContextCompressing = false,
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
    runtime.isContextCompressing = isContextCompressing;
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
    for (final request in _pendingPersistence.values) {
      request.timer.cancel();
    }
    _pendingPersistence.clear();
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
    runtime.isContextCompressing = false;
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

  void discardConversationRuntime({
    required int conversationId,
    required String mode,
  }) {
    _cancelPendingPersistence(conversationId: conversationId, mode: mode);
    _taskBindings.removeWhere(
      (_, binding) =>
          binding.conversationId == conversationId && binding.mode == mode,
    );
    final removed = _runtimes.remove(
      _runtimeKey(conversationId: conversationId, mode: mode),
    );
    if (removed != null) {
      notifyListeners();
    }
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
    _cancelPendingPersistence(conversationId: conversationId, mode: mode);
    final runtime = runtimeFor(conversationId: conversationId, mode: mode);
    if (runtime == null || runtime.messages.isEmpty) return;

    final snapshotMessages = List<ChatMessageModel>.from(runtime.messages);
    final snapshotConversation = runtime.conversation;
    final conversationMode = _conversationModeFromRuntimeMode(mode);
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

    final baseConversation =
        (snapshotConversation?.mode == conversationMode
            ? snapshotConversation
            : snapshotConversation?.copyWith(mode: conversationMode)) ??
        ConversationModel(
          id: conversationId,
          mode: conversationMode,
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
      await ConversationService.completeConversation(
        conversationId,
        mode: conversationMode,
      );
    }
  }

  void schedulePersistRuntimeConversation({
    required int conversationId,
    required String mode,
    bool generateSummary = false,
    bool markComplete = false,
    Duration delay = const Duration(milliseconds: 350),
  }) {
    final key = _runtimeKey(conversationId: conversationId, mode: mode);
    _pendingPersistence[key]?.timer.cancel();
    final timer = Timer(delay, () {
      _pendingPersistence.remove(key);
      unawaited(
        persistRuntimeConversation(
          conversationId: conversationId,
          mode: mode,
          generateSummary: generateSummary,
          markComplete: markComplete,
        ),
      );
    });
    _pendingPersistence[key] = _PendingPersistenceRequest(
      conversationId: conversationId,
      mode: mode,
      timer: timer,
      generateSummary: generateSummary,
      markComplete: markComplete,
    );
  }

  Future<void> flushPendingPersistence({
    required int conversationId,
    required String mode,
  }) async {
    final key = _runtimeKey(conversationId: conversationId, mode: mode);
    final request = _pendingPersistence.remove(key);
    if (request == null) {
      return;
    }
    request.timer.cancel();
    await persistRuntimeConversation(
      conversationId: request.conversationId,
      mode: request.mode,
      generateSummary: request.generateSummary,
      markComplete: request.markComplete,
    );
  }

  Future<void> flushAllPendingPersistence() async {
    final requests = _pendingPersistence.values.toList(growable: false);
    _pendingPersistence.clear();
    for (final request in requests) {
      request.timer.cancel();
      await persistRuntimeConversation(
        conversationId: request.conversationId,
        mode: request.mode,
        generateSummary: request.generateSummary,
        markComplete: request.markComplete,
      );
    }
  }

  void _handleChatTaskMessage(String taskId, String content, String? type) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

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
      runtime.isContextCompressing = false;
      runtime.currentAiMessages.remove(taskId);
    } else if (isErrorMessage) {
      messageText = kNetworkErrorMessage;
      isError = true;
      isSummarizing = false;
      runtime.isContextCompressing = false;
      runtime.currentAiMessages.remove(taskId);
    } else if (isSummaryStart) {
      messageText = '';
      isError = false;
      isSummarizing = true;
      runtime.isContextCompressing = true;
      runtime.currentAiMessages[taskId] = '';
    } else if (isOpenClawAttachment) {
      messageText = runtime.currentAiMessages[taskId] ?? '';
      isError = false;
      isSummarizing = false;
      runtime.isContextCompressing = false;
    } else {
      final text = (payload['text'] ?? '').toString();
      runtime.currentAiMessages[taskId] =
          (runtime.currentAiMessages[taskId] ?? '') + text;
      messageText = runtime.currentAiMessages[taskId] ?? '';
      isError = false;
      isSummarizing = false;
      runtime.isContextCompressing = false;
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
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleChatTaskMessageEnd(String taskId) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

    runtime.isAiResponding = false;
    runtime.isContextCompressing = false;
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
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

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
      schedulePersistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
      );
      return;
    }

    runtime.pendingThinkingRoundSplit = true;
    notifyListeners();
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleAgentThinkingUpdate(String taskId, String thinking) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;
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
      schedulePersistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
      );
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
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleAgentToolCallStart(AgentToolEventData event) {
    final binding = _taskBindings[event.taskId];
    final runtime = _runtimeForTask(event.taskId);
    if (binding == null || runtime == null) return;
    final taskId = runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (taskId == null || taskId != event.taskId) return;

    _updateToolLayerState(runtime, event);

    _finalizePendingAgentTextIfNeeded(runtime, taskId);
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
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleAgentToolCallProgress(AgentToolEventData event) {
    final binding = _taskBindings[event.taskId];
    final runtime = _runtimeForTask(event.taskId);
    if (binding == null || runtime == null) return;
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
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleAgentToolCallComplete(AgentToolEventData event) {
    final binding = _taskBindings[event.taskId];
    final runtime = _runtimeForTask(event.taskId);
    if (binding == null || runtime == null) return;
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
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleAgentChatMessage(
    String taskId,
    String message, {
    bool isFinal = true,
  }) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;
    final resolvedTaskId =
        runtime.currentDispatchTaskId ?? runtime.lastAgentTaskId;
    if (resolvedTaskId == null || resolvedTaskId != taskId) return;

    final aiTextMessageId =
        _resolvePendingAgentTextMessageId(runtime, taskId) ??
        _nextAgentTextMessageId(runtime, taskId);
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
      unawaited(
        persistRuntimeConversation(
          conversationId: binding.conversationId,
          mode: binding.mode,
          markComplete: true,
        ),
      );
    } else {
      schedulePersistRuntimeConversation(
        conversationId: binding.conversationId,
        mode: binding.mode,
      );
    }
  }

  void _handleAgentContextCompactionStateChanged(
    String taskId,
    bool isCompacting,
    int? latestPromptTokens,
    int? promptTokenThreshold,
  ) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

    _applyPromptTokenUsageUpdate(
      runtime,
      latestPromptTokens: latestPromptTokens,
      promptTokenThreshold: promptTokenThreshold,
    );
    runtime.isContextCompressing = isCompacting;
    notifyListeners();
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
  }

  void _handleAgentPromptTokenUsageChanged(
    String taskId,
    int latestPromptTokens,
    int? promptTokenThreshold,
  ) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;

    _applyPromptTokenUsageUpdate(
      runtime,
      latestPromptTokens: latestPromptTokens,
      promptTokenThreshold: promptTokenThreshold,
    );
    notifyListeners();
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
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

    final textId =
        _resolvePendingAgentTextMessageId(runtime, taskId) ??
        _nextAgentTextMessageId(runtime, taskId);
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
    int? latestPromptTokens,
    int? promptTokenThreshold,
  ) {
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;
    _applyPromptTokenUsageUpdate(
      runtime,
      latestPromptTokens: latestPromptTokens,
      promptTokenThreshold: promptTokenThreshold,
    );

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
        final fallbackId = _nextAgentTextMessageId(runtime, taskId);
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

  void _applyPromptTokenUsageUpdate(
    ChatConversationRuntimeState runtime, {
    int? latestPromptTokens,
    int? promptTokenThreshold,
  }) {
    final conversation = runtime.conversation;
    if (conversation == null ||
        (latestPromptTokens == null && promptTokenThreshold == null)) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    runtime.conversation = conversation.copyWith(
      latestPromptTokens:
          latestPromptTokens ?? conversation.latestPromptTokens,
      promptTokenThreshold:
          promptTokenThreshold ?? conversation.promptTokenThreshold,
      latestPromptTokensUpdatedAt: latestPromptTokens != null
          ? now
          : conversation.latestPromptTokensUpdatedAt,
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

    final textId =
        _resolvePendingAgentTextMessageId(runtime, taskId) ??
        _nextAgentTextMessageId(runtime, taskId);
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
    runtime.pendingAgentTextTaskId = null;
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

    final textMessageId = _nextAgentTextMessageId(runtime, taskId);
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
    final binding = _taskBindings[taskId];
    final runtime = _runtimeForTask(taskId);
    if (binding == null || runtime == null) return;
    runtime.vlmInfoQuestion = question;
    runtime.isSubmittingVlmReply = false;
    notifyListeners();
    schedulePersistRuntimeConversation(
      conversationId: binding.conversationId,
      mode: binding.mode,
    );
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
        createAt: DateTime.fromMillisecondsSinceEpoch(startTime),
      ),
    );
    _persistDeepThinkingCardIfNeeded(
      conversationId: runtime.conversationId,
      mode: runtime.mode,
      message: runtime.messages.first,
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
    _persistDeepThinkingCardIfNeeded(
      conversationId: runtime.conversationId,
      mode: runtime.mode,
      message: runtime.messages[index],
    );
  }

  void _persistDeepThinkingCardIfNeeded({
    required int conversationId,
    required String mode,
    required ChatMessageModel message,
  }) {
    final cardData = message.cardData;
    if (message.type != 2 || cardData?['type'] != 'deep_thinking') {
      return;
    }
    unawaited(
      ConversationHistoryService.upsertConversationUiCard(
        conversationId,
        entryId: message.id,
        cardData: Map<String, dynamic>.from(cardData!),
        createdAtMillis: message.createAt.millisecondsSinceEpoch,
        mode: _conversationModeFromRuntimeMode(mode),
      ),
    );
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

  String? _resolvePendingAgentTextMessageId(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    if (runtime.pendingAgentTextTaskId != taskId) return null;
    for (final message in runtime.messages) {
      if (_isAgentTextMessageForTask(message, taskId)) {
        return message.id;
      }
    }
    return null;
  }

  String _nextAgentTextMessageId(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    final baseId = _agentTextBaseId(taskId);
    var maxSequence = 0;
    for (final message in runtime.messages) {
      final sequence = _agentTextMessageSequence(message.id, taskId);
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    if (maxSequence == 0) {
      return baseId;
    }
    return '$baseId-${maxSequence + 1}';
  }

  bool _isAgentTextMessageForTask(ChatMessageModel message, String taskId) {
    if (message.type != 1 || message.user != 2) {
      return false;
    }
    return _agentTextMessageSequence(message.id, taskId) > 0;
  }

  int _agentTextMessageSequence(String messageId, String taskId) {
    final baseId = _agentTextBaseId(taskId);
    if (messageId == baseId) {
      return 1;
    }
    if (!messageId.startsWith('$baseId-')) {
      return 0;
    }
    return int.tryParse(messageId.substring(baseId.length + 1)) ?? 0;
  }

  void _finalizePendingAgentTextIfNeeded(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    final pendingTextMessageId = _resolvePendingAgentTextMessageId(
      runtime,
      taskId,
    );
    if (pendingTextMessageId == null) {
      runtime.pendingAgentTextTaskId = null;
      return;
    }
    runtime.messages.removeWhere(
      (msg) =>
          msg.id == pendingTextMessageId && (msg.text?.trim().isEmpty ?? true),
    );
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
      'toolTitle': event.toolTitle.isNotEmpty
          ? event.toolTitle
          : (existingCardData['toolTitle'] ?? '').toString(),
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

  ConversationMode _conversationModeFromRuntimeMode(String mode) {
    return mode == kChatRuntimeModeOpenClaw
        ? ConversationMode.openclaw
        : ConversationMode.normal;
  }

  void _cancelPendingPersistence({
    required int conversationId,
    required String mode,
  }) {
    final key = _runtimeKey(conversationId: conversationId, mode: mode);
    final request = _pendingPersistence.remove(key);
    request?.timer.cancel();
  }

  String _runtimeKey({required int conversationId, required String mode}) {
    return '$mode:$conversationId';
  }
}
