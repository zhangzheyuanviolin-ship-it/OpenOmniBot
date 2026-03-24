// ignore_for_file: unused_element, unused_element_parameter

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
import '../command_overlay/constants/messages.dart';
import '../common/openclaw_connection_checker.dart';
import '../omnibot_workspace/widgets/omnibot_workspace_browser.dart';
import 'services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/constants/openclaw/openclaw_keys.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/widgets/permission_bottom_sheet.dart';
import 'package:ui/services/app_state_service.dart';
import 'package:ui/services/app_update_service.dart';
import 'package:ui/services/conversation_model_override_service.dart';
import 'package:ui/services/conversation_service.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/services/permission_registry.dart';
import 'package:ui/services/permission_service.dart';
import 'package:ui/services/scene_model_config_service.dart';
import 'package:ui/services/special_permission.dart';
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

part 'chat_page_lifecycle.dart';
part 'chat_page_model_context.dart';
part 'chat_page_openclaw.dart';
part 'chat_page_conversation_flow.dart';
part 'chat_page_ui.dart';

enum ChatPageMode { normal, openclaw }

class ChatPage extends StatefulWidget {
  final List<String> args;

  const ChatPage({super.key, this.args = const []});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

abstract class _ChatPageStateBase extends State<ChatPage>
    with
        WidgetsBindingObserver,
        ChatMessageHandler,
        DispatchStreamHandler,
        AgentStreamHandler,
        TaskExecutionHandler,
        ConversationManager
    implements RouteAware {
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
  bool _showModelMentionPanel = false;
  bool _openClawPanelExpanded = false;
  bool _openClawDeployPanelExpanded = false;
  bool _isLoadingOpenClawDeployStatus = false;
  EmbeddedTerminalRuntimeStatus? _openClawDeployRuntimeStatus;
  OpenClawDeploySnapshot? _openClawDeploySnapshot;
  OpenClawGatewayStatus? _openClawGatewayStatus;
  Timer? _openClawDeploySnapshotPoller;
  bool _hasHandledOpenClawDeployCompletion = false;
  bool _openClawDeployConfigTouched = false;
  String? _openClawDeployConfigDraftKey;
  _ActiveModelMentionToken? _activeModelMentionToken;
  List<ModelProviderProfileSummary> _modelProviderProfiles = const [];
  Map<String, List<ProviderModelOption>> _modelOptionsByProfileId = const {};
  List<SceneCatalogItem> _sceneCatalog = const [];
  ConversationModelOverride? _conversationModelOverride;
  _ChatModelOverrideSelection? _pendingConversationModelOverride;
  bool _showConversationModelMentionChip = false;
  bool _isConversationModelSelectorActive = false;
  bool _isQuickModelPickerActive = false;
  bool _isQuickModelPickerLongPressing = false;
  bool _quickModelPickerHasEnteredList = false;
  String? _quickModelPickerProviderProfileId;
  List<ProviderModelOption> _quickModelPickerModels = const [];
  _ChatModelOverrideSelection? _quickModelPickerHoverSelection;
  final TextEditingController _openClawBaseUrlController =
      TextEditingController();
  final TextEditingController _openClawTokenController =
      TextEditingController();
  final TextEditingController _openClawUserIdController =
      TextEditingController();
  final TextEditingController _openClawDeployConfigController =
      TextEditingController();
  final TextEditingController _conversationModelSearchController =
      TextEditingController();
  final FocusNode _conversationModelSearchFocusNode = FocusNode();
  final TextEditingController _quickModelPickerSearchController =
      TextEditingController();
  final FocusNode _quickModelPickerSearchFocusNode = FocusNode();
  final ScrollController _quickModelPickerScrollController = ScrollController();
  final GlobalKey _chatPageStackKey = GlobalKey();
  final GlobalKey _chatAppBarKey = GlobalKey();
  final GlobalKey _openClawPanelKey = GlobalKey();
  final GlobalKey _inputAreaKey = GlobalKey();
  final GlobalKey _conversationModelSelectorKey = GlobalKey();
  final GlobalKey _quickModelPickerSurfaceKey = GlobalKey();
  final GlobalKey _quickModelPickerPanelKey = GlobalKey();
  final GlobalKey _quickModelPickerListKey = GlobalKey();
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
  static const String _openClawProviderApiKeyEnv =
      'OMNIBOT_OPENCLAW_PROVIDER_API_KEY';
  static const String _openClawGatewayTokenEnvRef =
      r'${OPENCLAW_GATEWAY_TOKEN}';
  static const String _openClawSessionKeyPrefix = 'openclaw';
  static const String _conversationRouteModePrefix = 'mode:';
  static const Duration _openClawGatewayReadyTimeout = Duration(seconds: 70);
  static const Duration _openClawGatewayReadyPollInterval = Duration(
    milliseconds: 1200,
  );
  static const Duration _openClawGatewayInitToastCooldown = Duration(
    seconds: 3,
  );
  DateTime? _lastOpenClawGatewayInitToastAt;
  int _workspaceSurfaceSeed = 0;
  bool _hasInitializedHalfScreen = false;
  bool _isCompanionModeEnabled = false;
  bool _isCompanionToggleLoading = false;
  int _companionCountdown = kCompanionCountdownDuration;
  bool _showCompanionCountdown = false;
  Timer? _companionCountdownTimer;
  Timer? _quickModelPickerAutoScrollTimer;
  AppUpdateStatus? _appUpdateStatus;
  ModalRoute<dynamic>? _subscribedRoute;
  Offset? _quickModelPickerPointerPosition;
  double _quickModelPickerAutoScrollDelta = 0;

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

  ChatConversationRuntimeState? get _activeRuntime =>
      _runtimeForMode(_activeMode);
  bool get _isOpenClawSurface => _activeSurfaceMode == ChatSurfaceMode.openclaw;
  bool get _isWorkspaceSurface =>
      _activeSurfaceMode == ChatSurfaceMode.workspace;

  ChatPageMode _modeFromSurface(ChatSurfaceMode surface) {
    return surface == ChatSurfaceMode.openclaw
        ? ChatPageMode.openclaw
        : ChatPageMode.normal;
  }

  ChatSurfaceMode _surfaceFromMode(ChatPageMode mode) {
    return mode == ChatPageMode.openclaw
        ? ChatSurfaceMode.openclaw
        : ChatSurfaceMode.normal;
  }

  ChatPageMode? _parseConversationModeToken(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      kConversationModeOpenClaw => ChatPageMode.openclaw,
      kConversationModeNormal => ChatPageMode.normal,
      _ => null,
    };
  }

  ChatPageMode? _explicitConversationModeFromArgs(List<String> args) {
    for (final rawArg in args.skip(1)) {
      final arg = rawArg.trim();
      if (!arg.startsWith(_conversationRouteModePrefix)) {
        continue;
      }
      final modeValue = arg.substring(_conversationRouteModePrefix.length);
      return _parseConversationModeToken(modeValue);
    }
    return null;
  }

  int? _conversationIdFromArgs(List<String> args) {
    if (args.isEmpty) return null;
    return int.tryParse(args.first.trim());
  }

  int _runtimeSignalScore(ChatConversationRuntimeState? runtime) {
    if (runtime == null) return 0;
    var score = 0;
    if (runtime.messages.isNotEmpty) score += 2;
    if (runtime.conversation != null) score += 1;
    if (runtime.hasInFlightTask) score += 1;
    return score;
  }

  ChatPageMode? _runtimeConversationModeFromArgs(List<String> args) {
    final conversationId = _conversationIdFromArgs(args);
    if (conversationId == null) return null;
    final normalScore = _runtimeSignalScore(
      _runtimeCoordinator.runtimeFor(
        conversationId: conversationId,
        mode: kChatRuntimeModeNormal,
      ),
    );
    final openClawScore = _runtimeSignalScore(
      _runtimeCoordinator.runtimeFor(
        conversationId: conversationId,
        mode: kChatRuntimeModeOpenClaw,
      ),
    );
    if (normalScore == 0 && openClawScore == 0) {
      return null;
    }
    if (normalScore == openClawScore) {
      return null;
    }
    return openClawScore > normalScore
        ? ChatPageMode.openclaw
        : ChatPageMode.normal;
  }

  ChatPageMode? _conversationModeFromArgs(List<String> args) {
    return _explicitConversationModeFromArgs(args) ??
        _runtimeConversationModeFromArgs(args);
  }

  ChatSurfaceMode? _surfaceForArgs(List<String> args) {
    final requestedMode = _conversationModeFromArgs(args);
    if (requestedMode != null) {
      return _surfaceFromMode(requestedMode);
    }
    if (_shouldOpenNormalChatForArgs(args)) {
      return ChatSurfaceMode.normal;
    }
    return null;
  }

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
      _activeRuntime?.currentAiMessages ??
      _currentAiMessagesByMode[_activeMode]!;
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
      _activeRuntime?.isDeepThinking ??
      (_isDeepThinkingByMode[_activeMode] ?? false);
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
      _activeRuntime?.isExecutingTask ??
      (_isExecutingTaskByMode[_activeMode] ?? false);
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
  _ChatModelOverrideSelection? get _activeConversationModelOverrideSelection {
    final pending = _pendingConversationModelOverride;
    if (pending != null) {
      return pending;
    }
    final persisted = _conversationModelOverride;
    if (persisted == null) {
      return null;
    }
    return _ChatModelOverrideSelection(
      providerProfileId: persisted.providerProfileId,
      modelId: persisted.modelId,
    );
  }

  SceneCatalogItem? get _dispatchSceneCatalogItem {
    for (final item in _sceneCatalog) {
      if (item.sceneId == 'scene.dispatch.model') {
        return item;
      }
    }
    return null;
  }

  String? get _activeNormalChatModelId {
    final dispatchScene = _dispatchSceneCatalogItem;
    final effectiveModel = dispatchScene?.effectiveModel.trim() ?? '';
    if (effectiveModel.isNotEmpty) {
      return effectiveModel;
    }
    final defaultModel = dispatchScene?.defaultModel.trim() ?? '';
    if (defaultModel.isNotEmpty) {
      return defaultModel;
    }
    return null;
  }

  _ChatModelOverrideSelection? get _activeDispatchSceneSelection {
    final dispatchScene = _dispatchSceneCatalogItem;
    if (dispatchScene == null) {
      return null;
    }
    final providerProfileId = dispatchScene.effectiveProviderProfileId.trim();
    final modelId = dispatchScene.effectiveModel.trim();
    if (providerProfileId.isEmpty || modelId.isEmpty) {
      return null;
    }
    return _ChatModelOverrideSelection(
      providerProfileId: providerProfileId,
      modelId: modelId,
    );
  }

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
  String get currentConversationMode => switch (_activeMode) {
    ChatPageMode.openclaw => kConversationModeOpenClaw,
    ChatPageMode.normal => kConversationModeNormal,
  };
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
    final requestedMode = _conversationModeFromArgs(widget.args);
    final shouldBackfillMode =
        conversation != null &&
        !conversation.hasExplicitMode &&
        requestedMode == mode;
    final conversationWithMode =
        shouldBackfillMode
        ? conversation!.copyWith(
            mode: mode == ChatPageMode.openclaw
                ? kConversationModeOpenClaw
                : kConversationModeNormal,
          )
        : conversation;
    if (conversationWithMode != null) {
      _currentConversationByMode[mode] = conversationWithMode;
      if (conversation != conversationWithMode) {
        unawaited(ConversationService.updateConversation(conversationWithMode));
      }
    }
    final runtime = _runtimeCoordinator.runtimeFor(
      conversationId: conversationId,
      mode: _modeKey(mode),
    );
    if (runtime == null) {
      _runtimeCoordinator.ensureRuntime(
        conversationId: conversationId,
        mode: _modeKey(mode),
        initialMessages: messages,
        conversation: conversationWithMode,
      );
    } else if (conversationWithMode != null) {
      runtime.conversation = conversationWithMode;
    }
    if (mode == ChatPageMode.normal) {
      unawaited(
        _loadConversationModelOverrideForNormalConversation(conversationId),
      );
      unawaited(_loadNormalChatModelContext());
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
    if (_activeMode == ChatPageMode.normal) {
      unawaited(
        _persistPendingConversationModelOverrideIfNeeded(conversationId),
      );
    }
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

  String _buildOpenClawSessionKey(int conversationId) {
    final normalizedUserId = _openClawUserId.trim();
    if (normalizedUserId.isNotEmpty) {
      return '$_openClawSessionKeyPrefix:$normalizedUserId:conversation:$conversationId';
    }
    return '$_openClawSessionKeyPrefix:conversation:$conversationId';
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
    if (mode == ChatPageMode.normal) {
      _conversationModelOverride = null;
      _pendingConversationModelOverride = null;
      _showConversationModelMentionChip = false;
      _showModelMentionPanel = false;
      _activeModelMentionToken = null;
      _isConversationModelSelectorActive = false;
      _isQuickModelPickerActive = false;
      _isQuickModelPickerLongPressing = false;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerProviderProfileId = null;
      _quickModelPickerModels = const [];
      _quickModelPickerHoverSelection = null;
      _quickModelPickerAutoScrollTimer?.cancel();
      _quickModelPickerAutoScrollTimer = null;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerAutoScrollDelta = 0;
      _conversationModelSearchController.clear();
      _quickModelPickerSearchController.clear();
    }
  }

  Map<String, List<ProviderModelOption>> _mergeChatModelOptions({
    required List<ModelProviderProfileSummary> profiles,
    required Map<String, List<ProviderModelOption>> source,
    required List<SceneCatalogItem> sceneCatalog,
    _ChatModelOverrideSelection? overrideSelection,
  }) {
    final result = <String, List<ProviderModelOption>>{
      for (final entry in source.entries)
        entry.key: List<ProviderModelOption>.from(entry.value),
    };
    final knownProfileIds = profiles.map((item) => item.id).toSet();

    void ensureOption(String profileId, String modelId, String ownedBy) {
      final normalizedProfileId = profileId.trim();
      final normalizedModelId = modelId.trim();
      if (normalizedProfileId.isEmpty || normalizedModelId.isEmpty) {
        return;
      }
      if (!knownProfileIds.contains(normalizedProfileId)) {
        return;
      }
      final bucket = result.putIfAbsent(
        normalizedProfileId,
        () => <ProviderModelOption>[],
      );
      final exists = bucket.any((item) => item.id == normalizedModelId);
      if (!exists) {
        bucket.insert(
          0,
          ProviderModelOption(
            id: normalizedModelId,
            displayName: normalizedModelId,
            ownedBy: ownedBy,
          ),
        );
      }
    }

    if (overrideSelection != null) {
      ensureOption(
        overrideSelection.providerProfileId,
        overrideSelection.modelId,
        'override',
      );
    }

    final dispatchScene = sceneCatalog.where(
      (item) => item.sceneId == 'scene.dispatch.model',
    );
    if (dispatchScene.isNotEmpty) {
      final scene = dispatchScene.first;
      ensureOption(
        scene.effectiveProviderProfileId,
        scene.effectiveModel,
        'scene',
      );
      ensureOption(scene.boundProviderProfileId, scene.overrideModel, 'scene');
    }

    return result;
  }

  double _quickModelPickerTopOffset() {
    final stackContext = _chatPageStackKey.currentContext;
    final appBarContext = _chatAppBarKey.currentContext;
    if (stackContext == null || appBarContext == null) {
      return 72;
    }
    final stackRenderBox = stackContext.findRenderObject() as RenderBox?;
    final appBarRenderBox = appBarContext.findRenderObject() as RenderBox?;
    if (stackRenderBox == null ||
        appBarRenderBox == null ||
        !stackRenderBox.hasSize ||
        !appBarRenderBox.hasSize) {
      return 72;
    }
    final stackOrigin = stackRenderBox.localToGlobal(Offset.zero);
    final appBarOrigin = appBarRenderBox.localToGlobal(Offset.zero);
    return appBarOrigin.dy - stackOrigin.dy + appBarRenderBox.size.height + 6;
  }

  // ===================== Part 方法声明 =====================

  bool _argsChanged(List<String> oldArgs, List<String> newArgs);

  bool _shouldOpenNormalChatForArgs(List<String> args);

  void _forceSwitchToNormalSurface();

  void _resetAndReloadConversation();

  void _handleQuickModelPickerSearchChanged();

  void _notifySummarySheetReadyIfNeeded();

  Future<void> _initializeHalfScreenEngineIfNeeded();

  Future<void> _checkCompanionTaskState();

  Future<void> _toggleCompanionMode();

  Future<void> _startCompanionMode();

  Future<void> _executeCompanionStart();

  Future<void> _cancelCompanionMode();

  void _startCompanionCountdown();

  void _resetCompanionCountdown();

  void _interruptCompanionAutoHomeIfNeeded();

  Future<void> _pressHomeAfterCompanionCountdown();

  void _onFocusChange();

  void _handleAppUpdateStatusChanged();

  double _popupMenuBottomOffset();

  Future<void> _handleAppUpdateBannerTap();

  Future<void> _handleAppUpdateBannerDismiss();

  Widget? _buildAppUpdateBanner();

  Future<void> _loadOpenClawConfig();

  Future<void> _ensureOpenClawUserId();

  int _pageIndexForSurface(ChatSurfaceMode mode);

  ChatSurfaceMode _surfaceForPageIndex(int pageIndex);

  ScrollController _scrollControllerForMode(ChatPageMode mode);

  void _jumpToCurrentModePage({bool animate = true});

  Future<void> _switchChatMode(
    ChatSurfaceMode targetMode, {
    bool syncPage = true,
  });

  void _handleModePageChanged(int pageIndex);

  void _storeDraftForActiveConversationMode();

  void _applyDraftForConversationMode(ChatPageMode mode);

  Future<void> _loadNormalChatModelContext();

  Future<void> _syncInvalidNormalConversationOverrideIfNeeded();

  Future<void> _loadConversationModelOverrideForNormalConversation(
    int? conversationId,
  );

  Future<void> _persistPendingConversationModelOverrideIfNeeded(
    int conversationId,
  );

  void _removeActiveModelMentionTokenFromInput();

  Future<void> _applyConversationModelOverride({
    required String providerProfileId,
    required String modelId,
    bool displayAsMentionChip = false,
  });

  Future<void> _clearConversationModelOverride();

  Map<String, dynamic>? _buildAgentModelOverridePayload();

  _ActiveModelMentionToken? _parseActiveModelMentionToken(
    TextEditingValue value,
  );

  ModelProviderProfileSummary? _findProviderProfile(String profileId);

  Future<void> _openConversationModelSelector(BuildContext anchorContext);

  void _closeConversationModelSelector({bool clearSearch = true});

  void _openQuickModelPicker({
    required bool longPressing,
    Offset? globalPosition,
    bool requestSearchFocus = false,
  });

  void _handleModelLongPressStart(
    BuildContext anchorContext,
    Offset globalPosition,
  );

  void _handleModelLongPressMove(Offset globalPosition);

  Future<void> _handleModelLongPressEnd(Offset globalPosition);

  void _handleModelLongPressCancel();

  void _closeQuickModelPicker();

  List<ProviderModelOption> get _filteredQuickModelPickerModels;

  String get _quickModelPickerSearchHintLabel;

  Future<void> _applyDispatchSceneModelSelection({
    required String providerProfileId,
    required String modelId,
  });

  Widget _buildConversationModelSelectorPanel();

  Widget? _buildQuickModelPickerOverlay();

  Widget _buildModelMentionPanel();

  void _handleSlashCommandInput();

  void _showOpenClawCommandPanel({bool expand = false});

  void _hideSlashCommandPanel();

  bool _isPointerInside(GlobalKey key, Offset position);

  Future<void> _handleOutsideTap(Offset position);

  Future<void> _applyOpenClawConfig({
    required String baseUrl,
    required String token,
    String? userId,
    bool enable = true,
  });

  String _buildDefaultOpenClawDeployConfigJson({
    required String providerBaseUrl,
    required String modelId,
  });

  String _buildOpenClawProviderBaseUrl(String providerBaseUrl);

  String? _validateOpenClawDeployConfig(String configJson);

  String _buildOpenClawDeployConfigDraftKey(
    _OpenClawDeployResolvedConfig resolvedConfig,
  );

  void _syncOpenClawDeployConfigDraft(
    _OpenClawDeployResolvedConfig resolvedConfig, {
    bool force = false,
  });

  _OpenClawDeployPanelState _buildOpenClawDeployPanelState();

  Future<void> _showOpenClawDeployPanel();

  Future<void> _refreshOpenClawDeployPanelState();

  void _startOpenClawDeploySnapshotPolling();

  void _stopOpenClawDeploySnapshotPolling();

  Future<void> _pollOpenClawDeploySnapshot();

  Future<void> _handleOpenClawDeploySnapshot(OpenClawDeploySnapshot snapshot);

  Future<void> _startOpenClawDeployFromPanel();

  Future<bool> _tryHandleSlashCommand(String messageText);

  Future<void> _checkOpenClawConnection();

  Widget _buildOpenClawCommandRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  });

  Widget _buildOpenClawDeployPanel();

  void _syncRuntimeSnapshotForMode(
    ChatPageMode mode, {
    ConversationModel? conversation,
    List<ChatMessageModel>? messages,
  });

  Future<void> _ensureActiveConversationReadyForStreaming();

  void _registerActiveTaskBinding(String taskId);

  void _createThinkingCard(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
  });

  void _updateThinkingCard(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
    bool lockCompleted = true,
  });

  Future<void> _pickAttachments();

  void _removePendingAttachment(String id);

  String _fileNameFromPath(String path);

  bool _isImageFilePath(String path, {String? mimeType});

  String? _mimeTypeFromExtension(String path, {String extension = ''});

  void _showSnackBar(String message);

  Future<void> _sendMessage({String? text});

  Future<void> _sendChatMessage(String aiMessageId);

  Future<bool> _handleExecutableTaskFlow(
    String aiMessageId,
    String userMessageId,
  );

  Future<bool> _tryAgentFlow(String aiMessageId, String userMessageId);

  List<Map<String, dynamic>> _historyBeforeLatestUser(
    List<Map<String, dynamic>> history,
  );

  Future<List<Map<String, dynamic>>> _latestUserAttachments();

  bool _isImageAttachmentMap(Map<String, dynamic> item);

  Future<String> _resolveImageDataUrl(Map<String, dynamic> item);

  void _onCancelTask();

  void _cancelDispatchTask();

  void _onCancelTaskFromCard(String taskId);

  void _updateThinkingCardToCancelled(String taskId);

  void _onPopupVisibilityChanged(bool visible);

  Future<void> _requestAuthorizeForExecution(
    List<String> requiredPermissionIds,
  );

  Future<void> _retryLatestInstructionAfterAuth();

  void _removeLatestSystemReplyBeforeAuthRetry();

  Widget _buildSlashCommandPanel();

  Widget _buildModeMessagePage(ChatPageMode mode);

  Widget _buildWorkspaceSurfacePage();
}

class _ChatPageState extends _ChatPageStateBase
    with
        _ChatPageLifecycleMixin,
        _ChatPageModelContextMixin,
        _ChatPageOpenClawMixin,
        _ChatPageConversationFlowMixin,
        _ChatPageUiMixin {}
