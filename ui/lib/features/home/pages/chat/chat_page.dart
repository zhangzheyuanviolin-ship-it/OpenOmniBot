import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../../models/conversation_model.dart';
import '../../../../models/chat_message_model.dart';
import '../../../../services/assists_core_service.dart';
import '../../widgets/home_drawer.dart';
import '../authorize/authorize_page_args.dart';
import '../command_overlay/widgets/chat_input_area.dart';
import '../common/openclaw_connection_checker.dart';
import '../omnibot_workspace/widgets/omnibot_workspace_browser.dart';
import 'services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/constants/openclaw/openclaw_keys.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/widgets/permission_bottom_sheet.dart';
import 'package:ui/services/app_state_service.dart';
import 'package:ui/services/app_update_service.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/services/permission_registry.dart';
import 'package:ui/services/permission_service.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/utils/ui.dart';

// 导入 Mixins
import 'mixins/chat_message_handler.dart';
import 'mixins/dispatch_stream_handler.dart';
import 'mixins/agent_stream_handler.dart';
import 'mixins/task_execution_handler.dart';
import 'mixins/conversation_manager.dart';

// 导入 Widgets
import 'widgets/chat_widgets.dart';
import 'package:ui/widgets/app_update_banner.dart';
import 'package:ui/widgets/app_update_dialog.dart';

enum ChatPageMode { normal, openclaw }

class ChatPage extends StatefulWidget {
  final List<String> args;

  const ChatPage({super.key, this.args = const []});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with
        WidgetsBindingObserver,
        ChatMessageHandler,
        DispatchStreamHandler,
        AgentStreamHandler,
        TaskExecutionHandler,
        ConversationManager {
  static const int kCompanionCountdownDuration = 2;

  // ===================== Controllers =====================
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _normalMessageScrollController = ScrollController();
  final ScrollController _openClawMessageScrollController = ScrollController();
  final PageController _modePageController = PageController(initialPage: 1);
  final FocusNode _inputFocusNode = FocusNode();
  final TextEditingController _vlmAnswerController = TextEditingController();

  // ===================== Keys =====================
  final GlobalKey<ChatInputAreaState> _chatInputAreaKey =
      GlobalKey<ChatInputAreaState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<HomeDrawerState> _drawerKey = GlobalKey<HomeDrawerState>();

  // ===================== State =====================
  bool _isPopupVisible = false;
  final ChatConversationRuntimeCoordinator _runtimeCoordinator =
      ChatConversationRuntimeCoordinator.instance;

  // OpenClaw 配置与开关
  bool _openClawEnabled = false;
  String _openClawBaseUrl = '';
  String _openClawToken = '';
  String _openClawUserId = '';
  ChatSurfaceMode _activeSurfaceMode = ChatSurfaceMode.normal;
  ChatPageMode _activeConversationMode = ChatPageMode.normal;
  bool _showSlashCommandPanel = false;
  bool _openClawPanelExpanded = false;
  final TextEditingController _openClawBaseUrlController =
      TextEditingController();
  final TextEditingController _openClawTokenController =
      TextEditingController();
  final TextEditingController _openClawUserIdController =
      TextEditingController();
  final GlobalKey _openClawPanelKey = GlobalKey();
  final GlobalKey _inputAreaKey = GlobalKey();
  final Map<ChatPageMode, List<ChatInputAttachment>> _pendingAttachmentsByMode =
      {
        ChatPageMode.normal: <ChatInputAttachment>[],
        ChatPageMode.openclaw: <ChatInputAttachment>[],
      };
  final Map<ChatPageMode, String> _draftMessageByMode = {
    ChatPageMode.normal: '',
    ChatPageMode.openclaw: '',
  };

  // 输入框/任务执行状态
  final Map<ChatPageMode, bool> _isInputAreaVisibleByMode = {
    ChatPageMode.normal: true,
    ChatPageMode.openclaw: true,
  };
  final Map<ChatPageMode, bool> _isExecutingTaskByMode = {
    ChatPageMode.normal: false,
    ChatPageMode.openclaw: false,
  };

  final Map<ChatPageMode, List<ChatMessageModel>> _messagesByMode = {
    ChatPageMode.normal: <ChatMessageModel>[],
    ChatPageMode.openclaw: <ChatMessageModel>[],
  };
  final Map<ChatPageMode, bool> _isAiRespondingByMode = {
    ChatPageMode.normal: false,
    ChatPageMode.openclaw: false,
  };
  final Map<ChatPageMode, bool> _isCheckingExecutableTaskByMode = {
    ChatPageMode.normal: false,
    ChatPageMode.openclaw: false,
  };
  final Map<ChatPageMode, bool> _isSubmittingVlmReplyByMode = {
    ChatPageMode.normal: false,
    ChatPageMode.openclaw: false,
  };
  final Map<ChatPageMode, String?> _vlmInfoQuestionByMode = {
    ChatPageMode.normal: null,
    ChatPageMode.openclaw: null,
  };
  final Map<ChatPageMode, Map<String, String>> _currentAiMessagesByMode = {
    ChatPageMode.normal: <String, String>{},
    ChatPageMode.openclaw: <String, String>{},
  };
  final Map<ChatPageMode, String> _deepThinkingContentByMode = {
    ChatPageMode.normal: '',
    ChatPageMode.openclaw: '',
  };
  final Map<ChatPageMode, bool> _isDeepThinkingByMode = {
    ChatPageMode.normal: false,
    ChatPageMode.openclaw: false,
  };
  final Map<ChatPageMode, String?> _currentDispatchTaskIdByMode = {
    ChatPageMode.normal: null,
    ChatPageMode.openclaw: null,
  };
  final Map<ChatPageMode, int> _currentThinkingStageByMode = {
    ChatPageMode.normal: 1,
    ChatPageMode.openclaw: 1,
  };
  final Map<ChatPageMode, int?> _currentConversationIdByMode = {
    ChatPageMode.normal: null,
    ChatPageMode.openclaw: null,
  };
  final Map<ChatPageMode, ConversationModel?> _currentConversationByMode = {
    ChatPageMode.normal: null,
    ChatPageMode.openclaw: null,
  };
  bool _isAwaitingAuthorizeResult = false;
  bool _isRetryingLatestInstructionAfterAuth = false;
  static const String _openClawWaitingHint = '等待龙虾烹饪';
  static const String _openClawWaitingStatusKey = 'openclaw_waiting';
  int _workspaceSurfaceSeed = 0;
  bool _hasInitializedHalfScreen = false;
  bool _isCompanionModeEnabled = false;
  bool _isCompanionToggleLoading = false;
  int _companionCountdown = kCompanionCountdownDuration;
  bool _showCompanionCountdown = false;
  Timer? _companionCountdownTimer;
  AppUpdateStatus? _appUpdateStatus;

  ChatPageMode get _activeMode => _activeConversationMode;
  String _modeKey(ChatPageMode mode) => switch (mode) {
    ChatPageMode.normal => kChatRuntimeModeNormal,
    ChatPageMode.openclaw => kChatRuntimeModeOpenClaw,
  };
  ChatConversationRuntimeState? _runtimeForMode(ChatPageMode mode) {
    final conversationId = _currentConversationIdByMode[mode];
    if (conversationId == null) return null;
    return _runtimeCoordinator.runtimeFor(
      conversationId: conversationId,
      mode: _modeKey(mode),
    );
  }
  ChatConversationRuntimeState? get _activeRuntime => _runtimeForMode(_activeMode);
  bool get _isOpenClawSurface => _activeSurfaceMode == ChatSurfaceMode.openclaw;
  bool get _isWorkspaceSurface =>
      _activeSurfaceMode == ChatSurfaceMode.workspace;

  List<ChatMessageModel> get _messages =>
      _activeRuntime?.messages ?? _messagesByMode[_activeMode]!;
  bool get _isAiResponding =>
      _activeRuntime?.isAiResponding ??
      (_isAiRespondingByMode[_activeMode] ?? false);
  set _isAiResponding(bool value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.isAiResponding = value;
      return;
    }
    _isAiRespondingByMode[_activeMode] = value;
  }
  bool get _isCheckingExecutableTask =>
      _activeRuntime?.isCheckingExecutableTask ??
      (_isCheckingExecutableTaskByMode[_activeMode] ?? false);
  set _isCheckingExecutableTask(bool value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.isCheckingExecutableTask = value;
      return;
    }
    _isCheckingExecutableTaskByMode[_activeMode] = value;
  }
  bool get _isSubmittingVlmReply =>
      _activeRuntime?.isSubmittingVlmReply ??
      (_isSubmittingVlmReplyByMode[_activeMode] ?? false);
  set _isSubmittingVlmReply(bool value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.isSubmittingVlmReply = value;
      return;
    }
    _isSubmittingVlmReplyByMode[_activeMode] = value;
  }
  String? get _vlmInfoQuestion =>
      _activeRuntime?.vlmInfoQuestion ?? _vlmInfoQuestionByMode[_activeMode];
  set _vlmInfoQuestion(String? value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.vlmInfoQuestion = value;
      return;
    }
    _vlmInfoQuestionByMode[_activeMode] = value;
  }
  Map<String, String> get _currentAiMessages =>
      _activeRuntime?.currentAiMessages ?? _currentAiMessagesByMode[_activeMode]!;
  String get _deepThinkingContent =>
      _activeRuntime?.deepThinkingContent ??
      (_deepThinkingContentByMode[_activeMode] ?? '');
  set _deepThinkingContent(String value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.deepThinkingContent = value;
      return;
    }
    _deepThinkingContentByMode[_activeMode] = value;
  }
  bool get _isDeepThinking =>
      _activeRuntime?.isDeepThinking ?? (_isDeepThinkingByMode[_activeMode] ?? false);
  set _isDeepThinking(bool value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.isDeepThinking = value;
      return;
    }
    _isDeepThinkingByMode[_activeMode] = value;
  }
  String? get _currentDispatchTaskId =>
      _activeRuntime?.currentDispatchTaskId ??
      _currentDispatchTaskIdByMode[_activeMode];
  set _currentDispatchTaskId(String? value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.currentDispatchTaskId = value;
      return;
    }
    _currentDispatchTaskIdByMode[_activeMode] = value;
  }
  int get _currentThinkingStage =>
      _activeRuntime?.currentThinkingStage ??
      (_currentThinkingStageByMode[_activeMode] ?? 1);
  set _currentThinkingStage(int value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.currentThinkingStage = value;
      return;
    }
    _currentThinkingStageByMode[_activeMode] = value;
  }
  bool get _isInputAreaVisible =>
      _activeRuntime?.isInputAreaVisible ??
      (_isInputAreaVisibleByMode[_activeMode] ?? true);
  set _isInputAreaVisible(bool value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.isInputAreaVisible = value;
      return;
    }
    _isInputAreaVisibleByMode[_activeMode] = value;
  }
  bool get _isExecutingTask =>
      _activeRuntime?.isExecutingTask ?? (_isExecutingTaskByMode[_activeMode] ?? false);
  set _isExecutingTask(bool value) {
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.isExecutingTask = value;
      return;
    }
    _isExecutingTaskByMode[_activeMode] = value;
  }
  int? get _currentConversationId => _currentConversationIdByMode[_activeMode];
  set _currentConversationId(int? value) =>
      _currentConversationIdByMode[_activeMode] = value;
  ConversationModel? get _currentConversation =>
      _activeRuntime?.conversation ?? _currentConversationByMode[_activeMode];
  set _currentConversation(ConversationModel? value) {
    _currentConversationByMode[_activeMode] = value;
    final runtime = _activeRuntime;
    if (runtime != null) {
      runtime.conversation = value;
    }
  }
  List<ChatInputAttachment> get _pendingAttachments =>
      _pendingAttachmentsByMode[_activeMode]!;

  // ===================== Mixin 接口实现 =====================

  // ChatMessageHandler
  @override
  List<ChatMessageModel> get messages => _messages;
  @override
  bool get isAiResponding => _isAiResponding;
  @override
  set isAiResponding(bool value) => _isAiResponding = value;
  @override
  Map<String, String> get currentAiMessages => _currentAiMessages;
  @override
  TextEditingController get vlmAnswerController => _vlmAnswerController;
  @override
  String? get vlmInfoQuestion => _vlmInfoQuestion;
  @override
  set vlmInfoQuestion(String? value) => _vlmInfoQuestion = value;
  @override
  bool get isSubmittingVlmReply => _isSubmittingVlmReply;
  @override
  set isSubmittingVlmReply(bool value) => _isSubmittingVlmReply = value;

  // DispatchStreamHandler
  @override
  String get deepThinkingContent => _deepThinkingContent;
  @override
  set deepThinkingContent(String value) => _deepThinkingContent = value;
  @override
  bool get isDeepThinking => _isDeepThinking;
  @override
  set isDeepThinking(bool value) => _isDeepThinking = value;
  @override
  String? get currentDispatchTaskId => _currentDispatchTaskId;
  @override
  set currentDispatchTaskId(String? value) => _currentDispatchTaskId = value;
  @override
  int get currentThinkingStage => _currentThinkingStage;
  @override
  set currentThinkingStage(int value) => _currentThinkingStage = value;

  // TaskExecutionHandler
  @override
  TextEditingController get messageController => _messageController;
  @override
  FocusNode get inputFocusNode => _inputFocusNode;
  @override
  bool get isInputAreaVisible => _isInputAreaVisible;
  @override
  set isInputAreaVisible(bool value) => _isInputAreaVisible = value;
  @override
  bool get isExecutingTask => _isExecutingTask;
  @override
  set isExecutingTask(bool value) => _isExecutingTask = value;
  @override
  bool get isCheckingExecutableTask => _isCheckingExecutableTask;
  @override
  set isCheckingExecutableTask(bool value) => _isCheckingExecutableTask = value;

  @override
  Future<void> handleExecutableTaskExecute(
    String aiMessageId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _ensureActiveConversationReadyForStreaming();
    } catch (_) {
      if (mounted) {
        handleAgentError('Conversation setup failed. Please retry.');
      }
      return;
    }
    _syncRuntimeSnapshotForMode(_activeMode);
    _registerActiveTaskBinding(aiMessageId);
    await super.handleExecutableTaskExecute(aiMessageId, data);
  }

  // ConversationManager
  @override
  int? get currentConversationId => _currentConversationId;
  @override
  set currentConversationId(int? value) => _currentConversationId = value;
  @override
  ConversationModel? get currentConversation => _currentConversation;
  @override
  set currentConversation(ConversationModel? value) =>
      _currentConversation = value;
  @override
  List<String> get widgetArgs => widget.args;

  @override
  Future<void> persistAgentConversation() => saveConversation();

  @override
  void onConversationReset() {
    _resetLocalConversationState(_activeMode);
  }

  @override
  void onConversationLoaded(
    int conversationId,
    ConversationModel? conversation,
    List<ChatMessageModel> messages,
  ) {
    final mode = _activeMode;
    final runtime = _runtimeCoordinator.runtimeFor(
      conversationId: conversationId,
      mode: _modeKey(mode),
    );
    if (runtime == null) {
      _runtimeCoordinator.ensureRuntime(
        conversationId: conversationId,
        mode: _modeKey(mode),
        initialMessages: messages,
        conversation: conversation,
      );
    } else if (conversation != null) {
      runtime.conversation = conversation;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void onConversationPersisted(
    int conversationId,
    ConversationModel conversation,
    List<ChatMessageModel> messages,
  ) {
    _currentConversationIdByMode[_activeMode] = conversationId;
    _currentConversationByMode[_activeMode] = conversation;
    _syncRuntimeSnapshotForMode(
      _activeMode,
      conversation: conversation,
      messages: messages,
    );
  }

  @override
  void createThinkingCard(String taskID) => _createThinkingCard(taskID);

  @override
  void updateThinkingCard(String taskID) => _updateThinkingCard(taskID);

  @override
  void createThinkingCardForAgent(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
  }) => _createThinkingCard(
    taskID,
    cardId: cardId,
    thinkingContent: thinkingContent,
    isLoading: isLoading,
    stage: stage,
  );

  @override
  void updateThinkingCardForAgent(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
    bool lockCompleted = true,
  }) => _updateThinkingCard(
    taskID,
    cardId: cardId,
    thinkingContent: thinkingContent,
    isLoading: isLoading,
    stage: stage,
    lockCompleted: lockCompleted,
  );

  @override
  void clearAgentStreamSessionState() {
    final conversationId = _currentConversationId;
    if (conversationId == null) return;
    _runtimeCoordinator.clearConversationRuntimeSession(
      conversationId: conversationId,
      mode: _modeKey(_activeMode),
    );
  }

  @override
  void interruptActiveToolCard({String? summary}) {
    final conversationId = _currentConversationId;
    if (conversationId == null) return;
    _runtimeCoordinator.interruptActiveToolCard(
      conversationId: conversationId,
      mode: _modeKey(_activeMode),
      summary: summary,
    );
  }

  String _openClawWaitingCardId(String taskId) => '$taskId-openclaw-waiting';

  bool _isOpenClawWaitingCardMessage(ChatMessageModel message) {
    final cardData = message.cardData;
    return message.type == 2 &&
        cardData?['type'] == 'stage_hint' &&
        cardData?['statusKey'] == _openClawWaitingStatusKey;
  }

  void _showOpenClawWaitingCard(String taskId) {
    final waitingCardId = _openClawWaitingCardId(taskId);
    final cardData = {
      'type': 'stage_hint',
      'hint': _openClawWaitingHint,
      'statusKey': _openClawWaitingStatusKey,
      'taskID': taskId,
      'startTime': DateTime.now().millisecondsSinceEpoch,
    };

    setState(() {
      _messages.removeWhere((msg) => msg.id == waitingCardId);
      _messages.insert(
        0,
        ChatMessageModel(
          id: waitingCardId,
          type: 2,
          user: 3,
          content: {'cardData': cardData, 'id': waitingCardId},
        ),
      );
    });
  }

  void _removeOpenClawWaitingCard(String taskId) {
    final waitingCardId = _openClawWaitingCardId(taskId);
    final hasWaitingCard = _messages.any((msg) => msg.id == waitingCardId);
    if (!hasWaitingCard) return;

    setState(() {
      _messages.removeWhere((msg) => msg.id == waitingCardId);
    });
  }

  void _handleRuntimeCoordinatorChanged() {
    if (!mounted || _activeRuntime == null) return;
    setState(() {});
  }

  void _resetLocalConversationState(ChatPageMode mode) {
    _messagesByMode[mode]!.clear();
    _isAiRespondingByMode[mode] = false;
    _isCheckingExecutableTaskByMode[mode] = false;
    _isSubmittingVlmReplyByMode[mode] = false;
    _vlmInfoQuestionByMode[mode] = null;
    _currentAiMessagesByMode[mode]!.clear();
    _deepThinkingContentByMode[mode] = '';
    _isDeepThinkingByMode[mode] = false;
    _currentDispatchTaskIdByMode[mode] = null;
    _currentThinkingStageByMode[mode] = 1;
    _currentConversationIdByMode[mode] = null;
    _currentConversationByMode[mode] = null;
    _isInputAreaVisibleByMode[mode] = true;
    _isExecutingTaskByMode[mode] = false;
    _pendingAttachmentsByMode[mode]!.clear();
    _draftMessageByMode[mode] = '';
  }

  void _syncRuntimeSnapshotForMode(
    ChatPageMode mode, {
    ConversationModel? conversation,
    List<ChatMessageModel>? messages,
  }) {
    final conversationId = _currentConversationIdByMode[mode];
    if (conversationId == null) return;
    final runtime = _runtimeCoordinator.runtimeFor(
      conversationId: conversationId,
      mode: _modeKey(mode),
    );
    _runtimeCoordinator.replaceConversationSnapshot(
      conversationId: conversationId,
      mode: _modeKey(mode),
      messages: List<ChatMessageModel>.from(
        messages ?? runtime?.messages ?? _messagesByMode[mode]!,
      ),
      conversation:
          conversation ?? runtime?.conversation ?? _currentConversationByMode[mode],
      isAiResponding:
          runtime?.isAiResponding ?? (_isAiRespondingByMode[mode] ?? false),
      isCheckingExecutableTask:
          runtime?.isCheckingExecutableTask ??
          (_isCheckingExecutableTaskByMode[mode] ?? false),
      isSubmittingVlmReply:
          runtime?.isSubmittingVlmReply ??
          (_isSubmittingVlmReplyByMode[mode] ?? false),
      vlmInfoQuestion: runtime?.vlmInfoQuestion ?? _vlmInfoQuestionByMode[mode],
      currentAiMessages: Map<String, String>.from(
        runtime?.currentAiMessages ?? _currentAiMessagesByMode[mode]!,
      ),
      deepThinkingContent:
          runtime?.deepThinkingContent ?? (_deepThinkingContentByMode[mode] ?? ''),
      isDeepThinking:
          runtime?.isDeepThinking ?? (_isDeepThinkingByMode[mode] ?? false),
      currentDispatchTaskId:
          runtime?.currentDispatchTaskId ?? _currentDispatchTaskIdByMode[mode],
      currentThinkingStage:
          runtime?.currentThinkingStage ?? (_currentThinkingStageByMode[mode] ?? 1),
      isInputAreaVisible:
          runtime?.isInputAreaVisible ?? (_isInputAreaVisibleByMode[mode] ?? true),
      isExecutingTask:
          runtime?.isExecutingTask ?? (_isExecutingTaskByMode[mode] ?? false),
      lastAgentTaskId: runtime?.lastAgentTaskId,
      activeToolCardId: runtime?.activeToolCardId,
      activeThinkingCardId: runtime?.activeThinkingCardId,
      pendingAgentTextTaskId: runtime?.pendingAgentTextTaskId,
      pendingThinkingRoundSplit: runtime?.pendingThinkingRoundSplit ?? false,
      toolCardSequence: runtime?.toolCardSequence ?? 0,
      thinkingRound: runtime?.thinkingRound ?? 0,
    );
  }

  Future<void> _ensureActiveConversationReadyForStreaming() async {
    if (_currentConversationId == null) {
      await persistConversationSnapshot(
        generateSummary: false,
        markComplete: false,
      );
    }
    if (_currentConversationId == null) {
      throw StateError('conversationId is not ready');
    }
    _syncRuntimeSnapshotForMode(_activeMode);
  }

  void _registerActiveTaskBinding(String taskId) {
    final conversationId = _currentConversationId;
    if (conversationId == null) return;
    _runtimeCoordinator.registerTask(
      taskId: taskId,
      conversationId: conversationId,
      mode: _modeKey(_activeMode),
    );
  }

  void _createThinkingCard(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
  }) {
    final loadingIndex = _messages.indexWhere((msg) => msg.id == taskID);
    if (loadingIndex != -1) {
      setState(() => _messages.removeAt(loadingIndex));
    }

    final startTime = DateTime.now().millisecondsSinceEpoch;
    final thinkingCardId = cardId ?? '$taskID-thinking';
    final cardData = {
      'type': 'deep_thinking',
      'isLoading': isLoading ?? _isDeepThinking,
      'thinkingContent': thinkingContent ?? _deepThinkingContent,
      'stage': stage ?? _currentThinkingStage,
      'taskID': taskID,
      'startTime': startTime,
      'endTime': null,
    };

    setState(() {
      _messages.removeWhere((msg) => msg.id == thinkingCardId);
      _messages.insert(
        0,
        ChatMessageModel(
          id: thinkingCardId,
          type: 2,
          user: 3,
          content: {'cardData': cardData, 'id': thinkingCardId},
        ),
      );
    });
  }

  void _updateThinkingCard(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
    bool lockCompleted = true,
  }) {
    final thinkingCardId = cardId ?? '$taskID-thinking';
    final index = _messages.indexWhere((msg) => msg.id == thinkingCardId);
    if (index == -1) return;

    setState(() {
      final existing = _messages[index];
      final content = Map<String, dynamic>.from(existing.content ?? {});
      final cardData = Map<String, dynamic>.from(content['cardData'] ?? {});

      final currentStage = cardData['stage'] as int? ?? 1;
      final targetStage = stage ?? _currentThinkingStage;
      final newStage = (lockCompleted && currentStage == 4) ? 4 : targetStage;

      final startTime = cardData['startTime'] as int?;
      int? endTime = cardData['endTime'] as int?;
      if (newStage == 4 && endTime == null) {
        endTime = DateTime.now().millisecondsSinceEpoch;
      }

      cardData['thinkingContent'] = thinkingContent ?? _deepThinkingContent;
      cardData['isLoading'] = isLoading ?? _isDeepThinking;
      cardData['stage'] = newStage;
      cardData['taskID'] = taskID;
      cardData['startTime'] = startTime;
      cardData['endTime'] = endTime;

      content['cardData'] = cardData;
      _messages[index] = existing.copyWith(content: content);
    });
  }

  // ===================== Lifecycle =====================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _checkCompanionTaskState();
    AssistsMessageService.setOnTaskFinishCallback(() {
      if (!mounted || _isCompanionToggleLoading) return;
      setState(() {
        _isCompanionModeEnabled = false;
      });
      _resetCompanionCountdown();
    });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      checkConversationExists();
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        unawaited(_initializeHalfScreenEngineIfNeeded());
      });
    });

    _runtimeCoordinator.ensureInitialized();
    _runtimeCoordinator.addListener(_handleRuntimeCoordinatorChanged);
    AppUpdateService.statusNotifier.addListener(_handleAppUpdateStatusChanged);
    _appUpdateStatus = AppUpdateService.statusNotifier.value;
    unawaited(AppUpdateService.initialize());

    _inputFocusNode.addListener(_onFocusChange);
    _messageController.addListener(_handleSlashCommandInput);
    _loadOpenClawConfig();
    initializeConversation();
    _notifySummarySheetReadyIfNeeded();
  }

  void _unusedSetupAiServiceCallbacks() {
  }

  void _setupAssistsCallbacks() {
    /*
    AssistsMessageService.setOnDispatchStreamDataCallBack((
      taskID,
      data,
      fullContent,
    ) {
      if (!mounted) return;
      handleDispatchStreamData(taskID, data, fullContent);
    });
    AssistsMessageService.setOnDispatchStreamEndCallBack((taskID, fullContent) {
      if (!mounted) return;
      handleDispatchStreamEnd(taskID, fullContent);
    });
    AssistsMessageService.setOnDispatchStreamErrorCallBack((
      taskID,
      error,
      fullContent,
      isRateLimited,
    ) {
      if (!mounted) return;
      handleDispatchStreamError(taskID, error, fullContent, isRateLimited);
    });

    AssistsMessageService.setOnVLMRequestUserInputCallBack((question) {
      if (!mounted) return;
      setState(() {
        _vlmInfoQuestion = question;
        _vlmAnswerController.clear();
      });
    });

    AssistsMessageService.setOnVLMTaskFinishCallBack(_onTaskFinish);
    AssistsMessageService.setOnCommonTaskFinishCallBack(_onTaskFinish);

    // Agent 回调（新增）
    AssistsMessageService.setOnAgentThinkingStartCallback(() {
      if (!mounted) return;
      handleAgentThinkingStart();
    });

    AssistsMessageService.setOnAgentThinkingUpdateCallback((thinking) {
      if (!mounted) return;
      handleAgentThinkingUpdate(thinking);
    });

    AssistsMessageService.setOnAgentToolCallStartCallback((event) {
      if (!mounted) return;
      handleAgentToolCallStart(event);
    });

    AssistsMessageService.setOnAgentToolCallProgressCallback((event) {
      if (!mounted) return;
      handleAgentToolCallProgress(event);
    });

    AssistsMessageService.setOnAgentToolCallCompleteCallback((event) {
      if (!mounted) return;
      handleAgentToolCallComplete(event);
    });

    AssistsMessageService.setOnAgentChatMessageCallback((
      message, {
      bool isFinal = true,
    }) {
      if (!mounted) return;
      handleAgentChatMessage(message, isFinal: isFinal);
    });

    AssistsMessageService.setOnAgentClarifyCallback((question, missingFields) {
      if (!mounted) return;
      handleAgentClarifyRequired(question, missingFields);
    });

    AssistsMessageService.setOnAgentCompleteCallback((
      success,
      outputKind,
      hasUserVisibleOutput,
    ) {
      if (!mounted) return;
      handleAgentComplete(
        success,
        outputKind: outputKind,
        hasUserVisibleOutput: hasUserVisibleOutput,
      );
    });

    AssistsMessageService.setOnAgentErrorCallback((error) {
      if (!mounted) return;
      handleAgentError(error);
    });

    AssistsMessageService.setOnAgentPermissionRequiredCallback((missing) {
      if (!mounted) return;
      handleAgentPermissionRequired(missing);
    });
    */
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检测 args 变化，重新加载对话
    if (_argsChanged(oldWidget.args, widget.args)) {
      debugPrint(
        '[ChatPage] args changed: ${oldWidget.args} -> ${widget.args}',
      );
      _resetAndReloadConversation();
      _notifySummarySheetReadyIfNeeded();
    }
  }

  /// 检查 args 是否发生变化
  bool _argsChanged(List<String> oldArgs, List<String> newArgs) {
    if (oldArgs.length != newArgs.length) return true;
    for (int i = 0; i < oldArgs.length; i++) {
      if (oldArgs[i] != newArgs[i]) return true;
    }
    return false;
  }

  /// 重置状态并重新加载对话
  void _resetAndReloadConversation() {
    // 重置 dispatch 状态
    _resetLocalConversationState(_activeMode);

    // 重置 AI 响应状态

    // 重置输入状态
    _vlmAnswerController.clear();
    _messageController.clear();

    // 重新初始化对话
    initializeConversation();
  }

  void _notifySummarySheetReadyIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AssistsMessageService.notifySummarySheetReady();
    });
  }

  Future<void> _initializeHalfScreenEngineIfNeeded() async {
    if (_hasInitializedHalfScreen) return;
    _hasInitializedHalfScreen = true;
    await AppStateService.initHalfScreenEngine();
  }

  Future<void> _checkCompanionTaskState() async {
    try {
      final isRunning = await AssistsMessageService.isCompanionTaskRunning();
      if (!mounted) return;
      setState(() {
        _isCompanionModeEnabled = isRunning;
      });
      if (!isRunning) {
        _resetCompanionCountdown();
      }
    } catch (e) {
      debugPrint('检查陪伴状态失败: $e');
      if (!mounted) return;
      setState(() {
        _isCompanionModeEnabled = false;
      });
      _resetCompanionCountdown();
    }
  }

  Future<void> _toggleCompanionMode() async {
    if (_isCompanionToggleLoading) return;
    if (_isCompanionModeEnabled) {
      await _cancelCompanionMode();
      return;
    }
    await _startCompanionMode();
  }

  Future<void> _startCompanionMode() async {
    setState(() {
      _isCompanionToggleLoading = true;
    });

    try {
      await _initializeHalfScreenEngineIfNeeded();
      final deviceInfo = await DeviceService.getDeviceInfo();
      final brand = (deviceInfo?['brand'] as String?)?.toLowerCase() ?? 'other';
      final missingSpecs = await PermissionService.getMissingByLevel(
        brand: brand,
        level: PermissionLevel.companionAutomation,
      );

      if (missingSpecs.isNotEmpty) {
        if (!mounted) return;
        final permissionDataList = PermissionService.specsToPermissionData(
          missingSpecs,
          context: context,
        );
        await PermissionService.checkPermissions(permissionDataList);
        if (!mounted) return;
        setState(() {
          _isCompanionToggleLoading = false;
        });
        await PermissionBottomSheet.show(
          context,
          initialPermissions: permissionDataList,
          deviceBrand: brand,
          onAllAuthorized: () {
            unawaited(_executeCompanionStart());
          },
        );
        return;
      }

      await _executeCompanionStart();
    } catch (e) {
      debugPrint('开启陪伴前置检查失败: $e');
      if (!mounted) return;
      setState(() {
        _isCompanionToggleLoading = false;
      });
    }
  }

  Future<void> _executeCompanionStart() async {
    if (!_isCompanionToggleLoading && mounted) {
      setState(() {
        _isCompanionToggleLoading = true;
      });
    }

    try {
      final result = await AssistsMessageService.createCompanionTask();
      if (result != true) {
        throw StateError('createCompanionTask returned false');
      }
      if (!mounted) return;
      setState(() {
        _isCompanionModeEnabled = true;
        _isCompanionToggleLoading = false;
        _companionCountdown = kCompanionCountdownDuration;
        _showCompanionCountdown = true;
      });
      _startCompanionCountdown();
    } catch (e) {
      debugPrint('开启陪伴失败: $e');
      showToast('开启陪伴失败', type: ToastType.error);
      if (!mounted) return;
      setState(() {
        _isCompanionToggleLoading = false;
      });
      await _checkCompanionTaskState();
    }
  }

  Future<void> _cancelCompanionMode() async {
    setState(() {
      _isCompanionToggleLoading = true;
    });

    try {
      final result = await AssistsMessageService.cancelTask();
      if (result != true) {
        throw StateError('cancelTask returned false');
      }
      if (!mounted) return;
      setState(() {
        _isCompanionModeEnabled = false;
        _isCompanionToggleLoading = false;
      });
      _resetCompanionCountdown();
    } catch (e) {
      debugPrint('结束陪伴失败: $e');
      showToast('结束陪伴失败', type: ToastType.error);
      if (!mounted) return;
      setState(() {
        _isCompanionToggleLoading = false;
      });
      await _checkCompanionTaskState();
    }
  }

  void _startCompanionCountdown() {
    _companionCountdownTimer?.cancel();
    _companionCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      var shouldPressHome = false;
      setState(() {
        _companionCountdown -= 1;
        if (_companionCountdown <= 0) {
          _showCompanionCountdown = false;
          shouldPressHome = true;
          timer.cancel();
        }
      });

      if (shouldPressHome) {
        unawaited(_pressHomeAfterCompanionCountdown());
      }
    });
  }

  void _resetCompanionCountdown() {
    _companionCountdownTimer?.cancel();
    _companionCountdownTimer = null;
    if (!mounted) {
      _companionCountdown = kCompanionCountdownDuration;
      _showCompanionCountdown = false;
      return;
    }
    setState(() {
      _companionCountdown = kCompanionCountdownDuration;
      _showCompanionCountdown = false;
    });
  }

  void _interruptCompanionAutoHomeIfNeeded() {
    if (!_isCompanionModeEnabled || !_showCompanionCountdown) {
      return;
    }
    _resetCompanionCountdown();
    unawaited(AssistsMessageService.cancelCompanionGoHome());
  }

  Future<void> _pressHomeAfterCompanionCountdown() async {
    if (!_isCompanionModeEnabled) return;
    final success = await AssistsMessageService.pressHome();
    if (!success && mounted) {
      showToast('Auto return home failed', type: ToastType.error);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtimeCoordinator.removeListener(_handleRuntimeCoordinatorChanged);
    AppUpdateService.statusNotifier.removeListener(_handleAppUpdateStatusChanged);
    _messageController.removeListener(_handleSlashCommandInput);
    _messageController.dispose();
    _normalMessageScrollController.dispose();
    _openClawMessageScrollController.dispose();
    _modePageController.dispose();
    _inputFocusNode.dispose();
    _vlmAnswerController.dispose();
    _openClawBaseUrlController.dispose();
    _openClawTokenController.dispose();
    _openClawUserIdController.dispose();
    _companionCountdownTimer?.cancel();

    // 清理 Agent 回调

    super.dispose();
  }

  void _onFocusChange() {}

  void _handleAppUpdateStatusChanged() {
    if (!mounted) return;
    setState(() {
      _appUpdateStatus = AppUpdateService.statusNotifier.value;
    });
  }

  double _popupMenuBottomOffset() {
    final renderObject = _inputAreaKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 72;
    }
    final offset = renderObject.size.height - 8;
    return offset < 72 ? 72 : offset;
  }

  Future<void> _handleAppUpdateBannerTap() async {
    final status = _appUpdateStatus;
    if (status == null || !status.hasUpdate || !mounted) return;
    await showAppUpdateDialog(context, status);
  }

  Widget? _buildAppUpdateBanner() {
    final status = _appUpdateStatus;
    if (status == null || !status.hasUpdate) {
      return null;
    }
    return AppUpdateBanner(
      text: '发现新版本 ${status.latestVersionLabel}，点击更新',
      onTap: () {
        _handleAppUpdateBannerTap();
      },
    );
  }

  Future<void> _loadOpenClawConfig() async {
    try {
      final enabled =
          StorageService.getBool(kOpenClawEnabledKey, defaultValue: false) ??
          false;
      final baseUrl =
          StorageService.getString(kOpenClawBaseUrlKey, defaultValue: '') ?? '';
      final token =
          StorageService.getString(kOpenClawTokenKey, defaultValue: '') ?? '';
      final userId =
          StorageService.getString(kOpenClawUserIdKey, defaultValue: '') ?? '';
      final effectiveEnabled = enabled && baseUrl.trim().isNotEmpty;
      if (enabled && !effectiveEnabled) {
        await StorageService.setBool(kOpenClawEnabledKey, false);
      }
      if (!mounted) return;
      setState(() {
        _openClawEnabled = effectiveEnabled;
        _openClawBaseUrl = baseUrl;
        _openClawToken = token;
        _openClawUserId = userId;
        _activeSurfaceMode = effectiveEnabled
            ? ChatSurfaceMode.openclaw
            : ChatSurfaceMode.normal;
        _activeConversationMode = effectiveEnabled
            ? ChatPageMode.openclaw
            : ChatPageMode.normal;
      });
      _applyDraftForConversationMode(_activeConversationMode);
      _jumpToCurrentModePage(animate: false);
      await _ensureOpenClawUserId();
    } catch (e) {
      debugPrint('加载OpenClaw配置失败: $e');
    }
  }

  Future<void> _ensureOpenClawUserId() async {
    if (_openClawUserId.isNotEmpty) return;
    final existing =
        StorageService.getString(kOpenClawUserIdKey, defaultValue: '') ?? '';
    if (existing.isNotEmpty) {
      if (!mounted) return;
      setState(() => _openClawUserId = existing);
      return;
    }
    final generated = DateTime.now().microsecondsSinceEpoch.toString();
    await StorageService.setString(kOpenClawUserIdKey, generated);
    if (!mounted) return;
    setState(() => _openClawUserId = generated);
  }

  int _pageIndexForSurface(ChatSurfaceMode mode) => switch (mode) {
    ChatSurfaceMode.workspace => 0,
    ChatSurfaceMode.normal => 1,
    ChatSurfaceMode.openclaw => 2,
  };

  ChatSurfaceMode _surfaceForPageIndex(int pageIndex) => switch (pageIndex) {
    0 => ChatSurfaceMode.workspace,
    2 => ChatSurfaceMode.openclaw,
    _ => ChatSurfaceMode.normal,
  };

  ScrollController _scrollControllerForMode(ChatPageMode mode) {
    return mode == ChatPageMode.openclaw
        ? _openClawMessageScrollController
        : _normalMessageScrollController;
  }

  void _jumpToCurrentModePage({bool animate = true}) {
    final targetPage = _pageIndexForSurface(_activeSurfaceMode);
    if (!_modePageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpToCurrentModePage(animate: animate);
      });
      return;
    }
    final currentPage = _modePageController.page?.round();
    if (currentPage == targetPage) return;
    if (animate) {
      _modePageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else {
      _modePageController.jumpToPage(targetPage);
    }
  }

  Future<void> _switchChatMode(
    ChatSurfaceMode targetMode, {
    bool syncPage = true,
  }) async {
    if (!mounted) return;
    if (_activeSurfaceMode == targetMode) {
      if (syncPage) _jumpToCurrentModePage();
      return;
    }

    if ((_isAiResponding || _isCheckingExecutableTask || _isExecutingTask) &&
        targetMode != ChatSurfaceMode.workspace) {
      _showSnackBar('当前会话正在处理中，请稍后再切换模式');
      _jumpToCurrentModePage();
      return;
    }

    _storeDraftForActiveConversationMode();

    if (targetMode == ChatSurfaceMode.workspace) {
      _inputFocusNode.unfocus();
      setState(() {
        _activeSurfaceMode = ChatSurfaceMode.workspace;
        _workspaceSurfaceSeed += 1;
        _messageController.clear();
      });
      _hideSlashCommandPanel();
      if (syncPage) _jumpToCurrentModePage();
      return;
    }

    if (targetMode == ChatSurfaceMode.openclaw) {
      final hasConfig = _openClawBaseUrl.trim().isNotEmpty;
      setState(() {
        _activeSurfaceMode = ChatSurfaceMode.openclaw;
        _activeConversationMode = ChatPageMode.openclaw;
        _openClawEnabled = hasConfig;
      });
      _applyDraftForConversationMode(ChatPageMode.openclaw);
      await StorageService.setBool(kOpenClawEnabledKey, hasConfig);
      if (syncPage) _jumpToCurrentModePage();
      if (!hasConfig) {
        showToast('请先输入 /openclaw 完成配置');
      }
      return;
    }

    setState(() {
      _activeSurfaceMode = ChatSurfaceMode.normal;
      _activeConversationMode = ChatPageMode.normal;
      _openClawEnabled = false;
    });
    _applyDraftForConversationMode(ChatPageMode.normal);
    await StorageService.setBool(kOpenClawEnabledKey, false);
    _hideSlashCommandPanel();
    if (syncPage) _jumpToCurrentModePage();
  }

  void _handleModePageChanged(int pageIndex) {
    final targetMode = _surfaceForPageIndex(pageIndex);
    unawaited(_switchChatMode(targetMode, syncPage: false));
  }

  void _storeDraftForActiveConversationMode() {
    _draftMessageByMode[_activeConversationMode] = _messageController.text;
  }

  void _applyDraftForConversationMode(ChatPageMode mode) {
    final draft = _draftMessageByMode[mode] ?? '';
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      setState(() {
        for (final file in result.files) {
          final path = file.path;
          if (path == null || path.isEmpty) continue;
          final exists = _pendingAttachments.any((item) => item.path == path);
          if (exists) continue;
          final displayName = (file.name.trim().isNotEmpty)
              ? file.name.trim()
              : _fileNameFromPath(path);
          final extension = (file.extension ?? '').toLowerCase();
          final mimeType = _mimeTypeFromExtension(path, extension: extension);
          final isImage = _isImageFilePath(path, mimeType: mimeType);
          _pendingAttachments.add(
            ChatInputAttachment(
              id: '${path}_${DateTime.now().microsecondsSinceEpoch}',
              name: displayName,
              path: path,
              size: file.size > 0 ? file.size : null,
              mimeType: mimeType,
              isImage: isImage,
            ),
          );
        }
      });
    } catch (e) {
      _showSnackBar('添加附件失败：$e');
    }
  }

  void _removePendingAttachment(String id) {
    if (!mounted) return;
    setState(() {
      _pendingAttachments.removeWhere((item) => item.id == id);
    });
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    if (segments.isEmpty) return path;
    return segments.last.isEmpty ? path : segments.last;
  }

  bool _isImageFilePath(String path, {String? mimeType}) {
    final normalizedMime = mimeType?.trim().toLowerCase();
    if (normalizedMime != null && normalizedMime.startsWith('image/')) {
      return true;
    }
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.webp') ||
        lowerPath.endsWith('.gif') ||
        lowerPath.endsWith('.bmp') ||
        lowerPath.endsWith('.heic') ||
        lowerPath.endsWith('.heif');
  }

  String? _mimeTypeFromExtension(String path, {String extension = ''}) {
    final ext = extension.isNotEmpty
        ? extension
        : _fileNameFromPath(path).split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      default:
        return null;
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleSlashCommandInput() {
    final text = _messageController.text.trimLeft();
    final shouldShow = text.startsWith('/');
    if (!mounted) return;
    if (shouldShow != _showSlashCommandPanel) {
      setState(() {
        _showSlashCommandPanel = shouldShow;
        if (!shouldShow) {
          _openClawPanelExpanded = false;
        }
      });
    } else if (!_isOpenClawSurface && _openClawPanelExpanded) {
      setState(() {
        _openClawPanelExpanded = false;
      });
    }
  }

  void _showOpenClawCommandPanel({bool expand = false}) {
    if (!_isOpenClawSurface) {
      _showSnackBar('请先顶部滑动到 OpenClaw 模式');
      return;
    }
    if (!mounted) return;
    setState(() {
      _showSlashCommandPanel = true;
      _openClawPanelExpanded = expand;
      if (expand) {
        _openClawBaseUrlController.text = _openClawBaseUrl;
        _openClawTokenController.text = _openClawToken;
        _openClawUserIdController.text = _openClawUserId;
      }
    });
  }

  void _hideSlashCommandPanel() {
    if (!mounted) return;
    setState(() {
      _showSlashCommandPanel = false;
      _openClawPanelExpanded = false;
    });
  }

  bool _isPointerInside(GlobalKey key, Offset position) {
    final context = key.currentContext;
    if (context == null) return false;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return false;
    final offset = renderBox.localToGlobal(Offset.zero);
    final rect = offset & renderBox.size;
    return rect.contains(position);
  }

  Future<void> _handleOutsideTap(Offset position) async {
    if (!_showSlashCommandPanel && !_openClawPanelExpanded) return;
    if (_isPointerInside(_openClawPanelKey, position) ||
        _isPointerInside(_inputAreaKey, position)) {
      return;
    }
    if (_openClawPanelExpanded) {
      await _applyOpenClawConfig(
        baseUrl: _openClawBaseUrlController.text.trim(),
        token: _openClawTokenController.text.trim(),
        userId: _openClawUserIdController.text.trim(),
        enable: _isOpenClawSurface,
      );
      _checkOpenClawConnection();
    }
    _hideSlashCommandPanel();
  }

  Future<void> _applyOpenClawConfig({
    required String baseUrl,
    required String token,
    String? userId,
    bool enable = true,
  }) async {
    await StorageService.setString(kOpenClawBaseUrlKey, baseUrl);
    await StorageService.setString(kOpenClawTokenKey, token);
    if (userId != null && userId.isNotEmpty) {
      await StorageService.setString(kOpenClawUserIdKey, userId);
    }
    if (!mounted) return;
    setState(() {
      _openClawBaseUrl = baseUrl;
      _openClawToken = token;
      if (userId != null && userId.isNotEmpty) {
        _openClawUserId = userId;
      }
      _openClawEnabled =
          _isOpenClawSurface && enable && baseUrl.trim().isNotEmpty;
    });
    await StorageService.setBool(kOpenClawEnabledKey, _openClawEnabled);
    await _ensureOpenClawUserId();
  }

  Future<bool> _tryHandleSlashCommand(String messageText) async {
    final trimmed = messageText.trim();
    if (!trimmed.startsWith('/')) return false;

    // 只拦截 /openclaw 本地配置命令，其他斜杠命令（如 /model、/help 等）
    // 透传给 OpenClaw 网关或作为普通消息发送
    if (!trimmed.startsWith('/openclaw')) {
      return false;
    }

    if (!_isOpenClawSurface) {
      _showSnackBar('普通聊天模式下已停用 /openclaw，请滑到右侧 OpenClaw 模式');
      return true;
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      _showSnackBar('格式: /openclaw <baseurl> --token <token> <userid>');
      return true;
    }

    final baseUrl = parts[1];
    final tokenIndex = parts.indexOf('--token');
    if (tokenIndex == -1) {
      _showSnackBar('请在命令中显式包含 --token');
      return true;
    }
    String token = '';
    String? userId;
    if (tokenIndex + 1 < parts.length) {
      token = parts[tokenIndex + 1];
    }
    if (token == '-' || token == 'null') {
      token = '';
    }
    if (tokenIndex + 2 < parts.length) {
      userId = parts[tokenIndex + 2];
    }

    if (baseUrl.trim().isEmpty) {
      _showSnackBar('OpenClaw baseurl 不能为空');
      return true;
    }

    await _applyOpenClawConfig(
      baseUrl: baseUrl.trim(),
      token: token.trim(),
      userId: userId?.trim(),
      enable: true,
    );
    _messageController.clear();
    _inputFocusNode.unfocus();
    _hideSlashCommandPanel();
    _showSnackBar('OpenClaw 已配置并启用');
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if ((state == AppLifecycleState.resumed ||
            state == AppLifecycleState.inactive) &&
        _currentConversationId != null) {
      Future.delayed(const Duration(milliseconds: 100), () async {
        if (!mounted) return;
        await checkConversationExists();
      });
    }
    if (state == AppLifecycleState.resumed) {
      _notifySummarySheetReadyIfNeeded();
      unawaited(_checkCompanionTaskState());
      unawaited(AppUpdateService.refreshIfNeeded());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _resetCompanionCountdown();
      unawaited(AssistsMessageService.cancelCompanionGoHome());
    }
  }

  // ===================== 任务完成回调 =====================

  void _resetAllTaskStates() {
    _isExecutingTask = false;
    _isInputAreaVisible = true;
    _isAiResponding = false;
    _isCheckingExecutableTask = false;
    resetDispatchState();
  }

  void _onTaskFinish() {
    if (mounted && _isExecutingTask) {
      setState(_resetAllTaskStates);
    } else {
      _resetAllTaskStates();
    }
    saveConversationWithSummary();
  }

  // ===================== 消息发送 =====================

  Future<void> _sendMessage({String? text}) async {
    final messageText = (text ?? _messageController.text).trim();
    final hasAttachments = _pendingAttachments.isNotEmpty;
    if ((messageText.isEmpty && !hasAttachments) || _isAiResponding) return;

    if (messageText.isNotEmpty) {
      final handledSlash = await _tryHandleSlashCommand(messageText);
      if (handledSlash) return;
    }

    if (_isOpenClawSurface && _openClawBaseUrl.trim().isEmpty) {
      _showSnackBar('请先使用 /openclaw 配置 OpenClaw');
      _showOpenClawCommandPanel(expand: true);
      return;
    }

    final attachments = _pendingAttachments
        .map((item) => item.toMap())
        .toList();
    if (attachments.isNotEmpty && mounted) {
      setState(() => _pendingAttachments.clear());
    }

    _inputFocusNode.unfocus();
    final messageIds = addUserMessage(messageText, attachments: attachments);

    if (_isOpenClawSurface) {
      await _sendChatMessage(messageIds.aiMessageId);
      return;
    }

    // 在启动统一 Agent 前先持久化会话，确保生成并同步 conversationId，
    // 任务完成后的原生回跳才能精准回到当前会话页。
    try {
      await _ensureActiveConversationReadyForStreaming();
    } catch (_) {
      if (mounted) {
        handleAgentError('Conversation setup failed. Please retry.');
      }
      return;
    }

    final handled = await _handleExecutableTaskFlow(
      messageIds.aiMessageId,
      messageIds.userMessageId,
    );
    if (!handled &&
        mounted &&
        _currentDispatchTaskId == messageIds.aiMessageId) {
      handleAgentError('统一 Agent 启动失败，请检查模型提供商与场景模型配置。');
    }
  }

  Future<void> _sendChatMessage(String aiMessageId) async {
    if (!_isOpenClawSurface) {
      handleAgentError('统一 Agent 已启用，旧聊天链路已移除，请检查配置后重试。');
      return;
    }
    final history = buildConversationHistory();
    final openClawConfig = {
      'baseUrl': _openClawBaseUrl,
      if (_openClawToken.isNotEmpty) 'token': _openClawToken,
      if (_openClawUserId.isNotEmpty) 'userId': _openClawUserId,
      if (_openClawUserId.isNotEmpty)
        'sessionKey': 'openclaw:${_openClawUserId.trim()}',
    };
    try {
      await _ensureActiveConversationReadyForStreaming();
    } catch (_) {
      if (mounted) {
        handleAgentError('Conversation setup failed. Please retry.');
      }
      return;
    }
    _showOpenClawWaitingCard(aiMessageId);
    _syncRuntimeSnapshotForMode(_activeMode);
    _registerActiveTaskBinding(aiMessageId);
    final success = await AssistsMessageService.createChatTask(
      aiMessageId,
      history,
      provider: 'openclaw',
      openClawConfig: openClawConfig,
    );
    if (success) return;
    _runtimeCoordinator.unregisterTask(aiMessageId);

    try {
      throw Exception('createChatTask returned false');
    } catch (error) {
      if (!mounted) return;
      final errorId = DateTime.now().millisecondsSinceEpoch.toString();
      _removeOpenClawWaitingCard(aiMessageId);
      setState(() {
        _isAiResponding = false;
        removeLatestLoadingIfExists();
        _messages.insert(
          0,
          ChatMessageModel(
            id: errorId,
            type: 1,
            user: 2,
            content: {'text': '抱歉，发送消息失败：$error', 'id': errorId},
          ),
        );
      });
    }
  }

  // ===================== 可执行任务处理流程 =====================

  Future<bool> _handleExecutableTaskFlow(
    String aiMessageId,
    String userMessageId,
  ) async {
    _isCheckingExecutableTask = true;
    try {
      return await _tryAgentFlow(aiMessageId, userMessageId);
    } finally {
      _isCheckingExecutableTask = false;
    }
  }

  // 新增：Agent 流程
  Future<bool> _tryAgentFlow(String aiMessageId, String userMessageId) async {
    try {
      _currentDispatchTaskId = aiMessageId;
      _currentThinkingStage = 1;

      createThinkingCard(aiMessageId);
      _syncRuntimeSnapshotForMode(_activeMode);
      _registerActiveTaskBinding(aiMessageId);

      final userMessage = latestUserUtterance();
      final history = _historyBeforeLatestUser(buildConversationHistory());
      final attachments = await _latestUserAttachments();

      final success = await AssistsMessageService.createAgentTask(
        taskId: aiMessageId,
        userMessage: userMessage,
        conversationHistory: history,
        attachments: attachments,
        conversationId: _currentConversationId,
      );
      if (!success) {
        _runtimeCoordinator.unregisterTask(aiMessageId);
      }

      return success;
    } catch (e) {
      _runtimeCoordinator.unregisterTask(aiMessageId);
      debugPrint('Agent flow error: $e');
      return false;
    }
  }

  List<Map<String, dynamic>> _historyBeforeLatestUser(
    List<Map<String, dynamic>> history,
  ) {
    if (history.isEmpty) return history;
    final normalized = List<Map<String, dynamic>>.from(history);
    final last = normalized.last;
    if ((last['role'] as String?) == 'user') {
      normalized.removeLast();
    }
    return normalized;
  }

  Future<List<Map<String, dynamic>>> _latestUserAttachments() async {
    for (final message in _messages) {
      if (message.user != 1) continue;
      final raw = message.content?['attachments'];
      if (raw is! List) return const [];
      final normalized = raw
          .whereType<Map>()
          .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      for (final item in normalized) {
        if (!_isImageAttachmentMap(item)) continue;
        final dataUrl = await _resolveImageDataUrl(item);
        if (dataUrl.isNotEmpty) {
          item['dataUrl'] = dataUrl;
        }
      }
      return normalized;
    }
    return const [];
  }

  bool _isImageAttachmentMap(Map<String, dynamic> item) {
    final explicitFlag = item['isImage'];
    if (explicitFlag is bool && explicitFlag) return true;
    final mimeType = (item['mimeType'] as String? ?? '').toLowerCase();
    if (mimeType.startsWith('image/')) return true;
    final path = (item['path'] as String? ?? '').toLowerCase();
    final url = (item['url'] as String? ?? '').toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.bmp') ||
        path.endsWith('.heic') ||
        path.endsWith('.heif') ||
        url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp') ||
        url.endsWith('.gif');
  }

  Future<String> _resolveImageDataUrl(Map<String, dynamic> item) async {
    final existingDataUrl = (item['dataUrl'] as String? ?? '').trim();
    if (existingDataUrl.startsWith('data:')) {
      return existingDataUrl;
    }

    final existingUrl = (item['url'] as String? ?? '').trim();
    if (existingUrl.startsWith('data:')) {
      return existingUrl;
    }
    if (existingUrl.startsWith('http://') ||
        existingUrl.startsWith('https://')) {
      return existingUrl;
    }

    final path = (item['path'] as String? ?? '').trim();
    if (path.isEmpty) return '';
    final file = File(path);
    if (!await file.exists()) return '';
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return '';
      final mimeType = ((item['mimeType'] as String?) ?? '')
          .trim()
          .toLowerCase();
      final resolvedMime = mimeType.startsWith('image/')
          ? mimeType
          : _mimeTypeFromExtension(path) ?? 'image/png';
      return 'data:$resolvedMime;base64,${base64Encode(bytes)}';
    } catch (_) {
      return '';
    }
  }

  // ===================== 取消任务 =====================

  void _onCancelTask() {
    try {
      if (_currentDispatchTaskId != null ||
          _isCheckingExecutableTask ||
          _isExecutingTask) {
        _cancelDispatchTask();
      } else {
        AssistsMessageService.cancelChatTask();
      }

      setState(() {
        _isAiResponding = false;
        _isCheckingExecutableTask = false;
        _isExecutingTask = false;
        _isInputAreaVisible = true;
        _messages.removeWhere(
          (msg) => msg.isLoading || _isOpenClawWaitingCardMessage(msg),
        );
      });

      debugPrint('Task cancelled, all states reset');
    } catch (e) {
      debugPrint('onCancelTask error: $e');
    }
  }

  void _cancelDispatchTask() {
    final taskId = _currentDispatchTaskId;
    interruptActiveToolCard();
    AssistsMessageService.cancelRunningTask();
    if (taskId != null) {
      _runtimeCoordinator.unregisterTask(taskId);
      removeThinkingCard(taskId);
    }
    clearAgentStreamSessionState();
    resetDispatchState();
  }

  void _onCancelTaskFromCard(String taskId) {
    try {
      interruptActiveToolCard();
      if (_isDeepThinking) {
        AssistsMessageService.cancelRunningTask();
      }
      AssistsMessageService.cancelRunningTask();
      _runtimeCoordinator.unregisterTask(taskId);
      _updateThinkingCardToCancelled(taskId);
      clearAgentStreamSessionState();
      resetDispatchState();
      setState(() {
        _isAiResponding = false;
        _isExecutingTask = false;
        _isInputAreaVisible = true;
        _messages.removeWhere(
          (msg) => msg.isLoading || _isOpenClawWaitingCardMessage(msg),
        );
      });
    } catch (e) {
      debugPrint('onCancelTaskFromCard error: $e');
    }
  }

  void _updateThinkingCardToCancelled(String taskId) {
    final thinkingCards = _messages
        .where(
          (msg) =>
              msg.id == '$taskId-thinking' ||
              msg.id.startsWith('$taskId-thinking-'),
        )
        .toList();
    if (thinkingCards.isEmpty) return;

    final thinkingCard = thinkingCards.first;
    final thinkingCardId = thinkingCard.id;
    final index = _messages.indexWhere((msg) => msg.id == thinkingCardId);
    if (index == -1) return;

    final cardData = Map<String, dynamic>.from(thinkingCard.cardData ?? {});
    cardData['stage'] = 5;
    cardData['isLoading'] = false;
    cardData['endTime'] = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _messages[index] = ChatMessageModel(
        id: thinkingCardId,
        type: 2,
        user: 3,
        content: {'cardData': cardData, 'id': thinkingCardId},
      );
    });
  }

  // ===================== Popup =====================

  void _onPopupVisibilityChanged(bool visible) {
    setState(() {
      _isPopupVisible = visible;
    });
  }

  /// 检查 OpenClaw 服务连接状态，通过全局 Toast 通知结果
  Future<void> _checkOpenClawConnection() async {
    await OpenClawConnectionChecker.checkAndToast(_openClawBaseUrl);
  }

  Widget _buildSlashCommandPanel() {
    final visible =
        _showSlashCommandPanel ||
        (_isOpenClawSurface && _openClawPanelExpanded);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: !visible
          ? const SizedBox.shrink()
          : Container(
              key: _openClawPanelKey,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _openClawPanelExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OpenClaw 配置',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _openClawBaseUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            hintText: 'http://192.168.1.10:18789',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _openClawTokenController,
                          decoration: const InputDecoration(
                            labelText: 'Token（可选）',
                            hintText: '为空表示无需 token',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _openClawUserIdController,
                          decoration: const InputDecoration(
                            labelText: 'User ID（可选）',
                            isDense: true,
                          ),
                        ),
                      ],
                    )
                  : !_isOpenClawSurface
                  ? Row(
                      children: const [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '/openclaw 在普通聊天模式下已停用，请滑到右侧 OpenClaw 模式',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    )
                  : InkWell(
                      onTap: () {
                        _showOpenClawCommandPanel(expand: true);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        children: const [
                          Icon(Icons.link, size: 16, color: Color(0xFF2563EB)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'OpenClaw',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          Text(
                            '配置',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
    );
  }

  // ===================== UI 构建 =====================

  Widget _buildModeMessagePage(ChatPageMode mode) {
    final runtime = _runtimeForMode(mode);
    return ChatMessageList(
      messages: runtime?.messages ?? _messagesByMode[mode]!,
      scrollController: _scrollControllerForMode(mode),
      onBeforeTaskExecute: handleBeforeTaskExecute,
      onCancelTask: _onCancelTaskFromCard,
      onRequestAuthorize: mode == ChatPageMode.normal
          ? _requestAuthorizeForExecution
          : null,
    );
  }

  Widget _buildWorkspaceSurfacePage() {
    return OmnibotWorkspaceBrowser(
      key: ValueKey('workspace_surface_$_workspaceSurfaceSeed'),
      workspacePath: OmnibotResourceService.rootPath,
      workspaceShellPath: OmnibotResourceService.shellRootPath,
    );
  }

  Future<void> _requestAuthorizeForExecution(
    List<String> requiredPermissionIds,
  ) async {
    if (_isAwaitingAuthorizeResult) return;
    if (latestUserUtterance().trim().isEmpty) return;

    _isAwaitingAuthorizeResult = true;
    try {
      final result = await GoRouterManager.pushForResult<bool>(
        '/home/authorize',
        extra: AuthorizePageArgs(
          requiredPermissionIds: requiredPermissionIds.isEmpty
              ? kTaskExecutionRequiredPermissionIds
              : requiredPermissionIds,
        ),
      );
      if (result == true && mounted) {
        await _retryLatestInstructionAfterAuth();
      }
    } finally {
      _isAwaitingAuthorizeResult = false;
    }
  }

  Future<void> _retryLatestInstructionAfterAuth() async {
    if (_isRetryingLatestInstructionAfterAuth ||
        _activeConversationMode == ChatPageMode.openclaw) {
      return;
    }
    if (latestUserUtterance().trim().isEmpty) return;

    _isRetryingLatestInstructionAfterAuth = true;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final aiMessageId = '$timestamp-ai';
    final userMessageId = '$timestamp-user';

    try {
      if (mounted) {
        setState(() {
          _removeLatestSystemReplyBeforeAuthRetry();
          _isAiResponding = true;
        });
      }

      final handled = await _handleExecutableTaskFlow(
        aiMessageId,
        userMessageId,
      );
      if (!handled && mounted && _currentDispatchTaskId == aiMessageId) {
        handleAgentError('统一 Agent 启动失败，请检查模型提供商与场景模型配置。');
      }
    } finally {
      _isRetryingLatestInstructionAfterAuth = false;
    }
  }

  void _removeLatestSystemReplyBeforeAuthRetry() {
    var removeCount = 0;
    for (final message in _messages) {
      if (message.user == 1) break;
      removeCount += 1;
    }
    if (removeCount <= 0) return;
    _messages.removeRange(0, removeCount);
  }

  @override
  Widget build(BuildContext context) {
    const edgeInset = 24.0;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    // 消除键盘收起时输入框“先下后上”弹跳：
    // 输入框距屏幕底 = Scaffold留白(bottomInset) + SafeArea(max(0,vp-bi)) + SizedBox
    // 目标总和 = max(bottomInset, viewPadding+edgeInset)，保证与左右边距一致
    // clamp(0,edgeInset) 保证键盘高于静止位时 SizedBox=0，接近时平滑补齐
    final inputBottomPadding = (viewPaddingBottom + edgeInset - bottomInset)
        .clamp(0.0, edgeInset);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(saveConversationWithSummary());
        if (GoRouterManager.canPop()) {
          GoRouterManager.pop();
          return;
        }
        unawaited(AppStateService.exitApp());
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF9FCFF),
        drawer: HomeDrawer(key: _drawerKey),
        onDrawerChanged: (isOpen) {
          if (isOpen) {
            _drawerKey.currentState?.reloadConversations();
          } else {
            checkAndHandleDeletedConversation();
          }
        },
        body: SafeArea(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _interruptCompanionAutoHomeIfNeeded();
              unawaited(_handleOutsideTap(event.position));
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    // 顶部栏
                    ChatAppBar(
                      onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                      onCompanionTap: () {
                        unawaited(_toggleCompanionMode());
                      },
                      activeMode: _activeSurfaceMode,
                      onModeChanged: (value) {
                        unawaited(_switchChatMode(value, syncPage: true));
                      },
                      isCompanionModeEnabled: _isCompanionModeEnabled,
                      isCompanionToggleLoading: _isCompanionToggleLoading,
                    ),
                    if (_isCompanionModeEnabled && _showCompanionCountdown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '$_companionCountdown秒后自动回到桌面',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF617390),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    // 消息列表
                    Expanded(
                      child: PageView(
                        controller: _modePageController,
                        onPageChanged: _handleModePageChanged,
                        children: [
                          _buildWorkspaceSurfacePage(),
                          _buildModeMessagePage(ChatPageMode.normal),
                          _buildModeMessagePage(ChatPageMode.openclaw),
                        ],
                      ),
                    ),
                    // VLM 用户输入提示
                    if (!_isWorkspaceSurface && _vlmInfoQuestion != null)
                      VlmInfoPrompt(
                        question: _vlmInfoQuestion!,
                        controller: _vlmAnswerController,
                        isSubmitting: _isSubmittingVlmReply,
                        onSubmit: onSubmitVlmInfo,
                        onDismiss: dismissVlmInfo,
                      ),
                    if (!_isWorkspaceSurface) _buildSlashCommandPanel(),
                    // 输入框区域
                    if (_isInputAreaVisible && !_isWorkspaceSurface)
                      Container(
                        key: _inputAreaKey,
                        child: ChatInputWrapper(
                          inputAreaKey: _chatInputAreaKey,
                          controller: _messageController,
                          focusNode: _inputFocusNode,
                          isProcessing: _isAiResponding,
                          onSendMessage: _sendMessage,
                          onCancelTask: _onCancelTask,
                          onPopupVisibilityChanged: _onPopupVisibilityChanged,
                          useLargeComposerStyle: true,
                          useAttachmentPickerForPlus: true,
                          onPickAttachment: _pickAttachments,
                          attachments: _pendingAttachments,
                          onRemoveAttachment: _removePendingAttachment,
                          topBanner: _buildAppUpdateBanner(),
                        ),
                      ),
                    SizedBox(height: inputBottomPadding),
                  ],
                ),
                // Popup menu
                if (_isPopupVisible && !_isWorkspaceSurface)
                  Positioned(
                    right: 24,
                    // Scaffold 已经根据键盘重排了 body，这里不再叠加 bottomInset，
                    // 否则键盘弹出时会把菜单额外上推，出现跑到屏幕顶部的问题。
                    bottom: _popupMenuBottomOffset(),
                    child:
                        _chatInputAreaKey.currentState?.buildPopupMenu() ??
                        const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
