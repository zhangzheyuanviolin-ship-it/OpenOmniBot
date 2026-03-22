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
import 'package:ui/services/conversation_model_override_service.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/services/permission_registry.dart';
import 'package:ui/services/permission_service.dart';
import 'package:ui/services/scene_model_config_service.dart';
import 'package:ui/utils/popup_menu_anchor_position.dart';
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
  _ActiveModelMentionToken? _activeModelMentionToken;
  List<ModelProviderProfileSummary> _modelProviderProfiles = const [];
  Map<String, List<ProviderModelOption>> _modelOptionsByProfileId = const {};
  List<SceneCatalogItem> _sceneCatalog = const [];
  ConversationModelOverride? _conversationModelOverride;
  _ChatModelOverrideSelection? _pendingConversationModelOverride;
  bool _showConversationModelMentionChip = false;
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
  ModalRoute<dynamic>? _subscribedRoute;

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

  Future<void> _loadNormalChatModelContext() async {
    try {
      final results = await Future.wait<dynamic>([
        ModelProviderConfigService.loadModelGroups(),
        SceneModelConfigService.getSceneCatalog(),
      ]);
      if (!mounted) return;

      final groups = results[0] as List<ProviderModelGroup>;
      final catalog = results[1] as List<SceneCatalogItem>;
      final profiles = groups.map((group) => group.profile).toList();
      final modelOptionsByProfileId = <String, List<ProviderModelOption>>{
        for (final group in groups)
          group.profile.id: List<ProviderModelOption>.from(group.models),
      };

      setState(() {
        _sceneCatalog = catalog;
        _modelProviderProfiles = profiles;
        _modelOptionsByProfileId = _mergeChatModelOptions(
          profiles: profiles,
          source: modelOptionsByProfileId,
          sceneCatalog: catalog,
          overrideSelection: _activeConversationModelOverrideSelection,
        );
      });
      await _syncInvalidNormalConversationOverrideIfNeeded();
    } catch (e) {
      debugPrint('加载聊天模型上下文失败: $e');
    }
  }

  Future<void> _syncInvalidNormalConversationOverrideIfNeeded() async {
    if (_modelProviderProfiles.isEmpty) {
      return;
    }
    final configuredProfileIds = _modelProviderProfiles
        .where((item) => item.configured)
        .map((item) => item.id)
        .toSet();
    final persisted = _conversationModelOverride;
    final pending = _pendingConversationModelOverride;
    final shouldClearPersisted =
        persisted != null &&
        !configuredProfileIds.contains(persisted.providerProfileId);
    final shouldClearPending =
        pending != null &&
        !configuredProfileIds.contains(pending.providerProfileId);

    if (!shouldClearPersisted && !shouldClearPending) {
      return;
    }

    final normalConversationId =
        _currentConversationIdByMode[ChatPageMode.normal];
    if (shouldClearPersisted && normalConversationId != null) {
      await ConversationModelOverrideService.clearOverride(
        normalConversationId,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (shouldClearPersisted) {
        _conversationModelOverride = null;
      }
      if (shouldClearPending) {
        _pendingConversationModelOverride = null;
      }
      if (_conversationModelOverride == null &&
          _pendingConversationModelOverride == null) {
        _showConversationModelMentionChip = false;
      }
      _modelOptionsByProfileId = _mergeChatModelOptions(
        profiles: _modelProviderProfiles,
        source: _modelOptionsByProfileId,
        sceneCatalog: _sceneCatalog,
        overrideSelection: _activeConversationModelOverrideSelection,
      );
    });
  }

  Future<void> _loadConversationModelOverrideForNormalConversation(
    int? conversationId,
  ) async {
    if (conversationId == null) {
      if (!mounted) return;
      setState(() {
        _conversationModelOverride = null;
        if (_pendingConversationModelOverride == null) {
          _showConversationModelMentionChip = false;
        }
      });
      return;
    }
    final override = await ConversationModelOverrideService.getOverride(
      conversationId,
    );
    if (!mounted) return;
    final nextSelection = override == null
        ? _pendingConversationModelOverride
        : _ChatModelOverrideSelection(
            providerProfileId: override.providerProfileId,
            modelId: override.modelId,
          );
    setState(() {
      _conversationModelOverride = override;
      _pendingConversationModelOverride = null;
      _showConversationModelMentionChip = override != null;
      _modelOptionsByProfileId = _mergeChatModelOptions(
        profiles: _modelProviderProfiles,
        source: _modelOptionsByProfileId,
        sceneCatalog: _sceneCatalog,
        overrideSelection: nextSelection,
      );
    });
    await _syncInvalidNormalConversationOverrideIfNeeded();
  }

  Future<void> _persistPendingConversationModelOverrideIfNeeded(
    int conversationId,
  ) async {
    final pending = _pendingConversationModelOverride;
    if (pending == null) {
      if (_conversationModelOverride?.conversationId == conversationId) {
        return;
      }
      await _loadConversationModelOverrideForNormalConversation(conversationId);
      return;
    }

    final value = ConversationModelOverride(
      conversationId: conversationId,
      providerProfileId: pending.providerProfileId,
      modelId: pending.modelId,
    );
    await ConversationModelOverrideService.saveOverride(value);
    if (!mounted) return;
    setState(() {
      _conversationModelOverride = value;
      _pendingConversationModelOverride = null;
      _modelOptionsByProfileId = _mergeChatModelOptions(
        profiles: _modelProviderProfiles,
        source: _modelOptionsByProfileId,
        sceneCatalog: _sceneCatalog,
        overrideSelection: _ChatModelOverrideSelection(
          providerProfileId: value.providerProfileId,
          modelId: value.modelId,
        ),
      );
    });
  }

  void _removeActiveModelMentionTokenFromInput() {
    final token = _activeModelMentionToken;
    if (token == null) {
      return;
    }
    final value = _messageController.value;
    final text = value.text;
    final start = token.start.clamp(0, text.length);
    final end = token.end.clamp(start, text.length);
    final before = text.substring(0, start);
    final after = text.substring(end);
    var nextText = '$before$after';
    if (before.endsWith(' ') && after.startsWith(' ')) {
      nextText = '$before${after.substring(1)}';
    }
    if (nextText.startsWith(' ')) {
      nextText = nextText.substring(1);
    }
    final nextOffset = start > nextText.length ? nextText.length : start;
    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  Future<void> _applyConversationModelOverride({
    required String providerProfileId,
    required String modelId,
    bool displayAsMentionChip = false,
  }) async {
    _removeActiveModelMentionTokenFromInput();
    final selection = _ChatModelOverrideSelection(
      providerProfileId: providerProfileId,
      modelId: modelId,
    );
    final normalConversationId =
        _currentConversationIdByMode[ChatPageMode.normal];

    if (normalConversationId == null) {
      if (!mounted) return;
      setState(() {
        _pendingConversationModelOverride = selection;
        _conversationModelOverride = null;
        _showConversationModelMentionChip = displayAsMentionChip;
        _showModelMentionPanel = false;
        _activeModelMentionToken = null;
        _modelOptionsByProfileId = _mergeChatModelOptions(
          profiles: _modelProviderProfiles,
          source: _modelOptionsByProfileId,
          sceneCatalog: _sceneCatalog,
          overrideSelection: selection,
        );
      });
    } else {
      final value = ConversationModelOverride(
        conversationId: normalConversationId,
        providerProfileId: providerProfileId,
        modelId: modelId,
      );
      await ConversationModelOverrideService.saveOverride(value);
      if (!mounted) return;
      setState(() {
        _conversationModelOverride = value;
        _pendingConversationModelOverride = null;
        _showConversationModelMentionChip = displayAsMentionChip;
        _showModelMentionPanel = false;
        _activeModelMentionToken = null;
        _modelOptionsByProfileId = _mergeChatModelOptions(
          profiles: _modelProviderProfiles,
          source: _modelOptionsByProfileId,
          sceneCatalog: _sceneCatalog,
          overrideSelection: selection,
        );
      });
    }

    final switchedLabel = displayAsMentionChip ? '@$modelId' : modelId;
    showToast('已切换到 $switchedLabel', type: ToastType.success);
  }

  Future<void> _clearConversationModelOverride() async {
    final hasOverride = _activeConversationModelOverrideSelection != null;
    if (!hasOverride) {
      return;
    }
    final normalConversationId =
        _currentConversationIdByMode[ChatPageMode.normal];
    if (normalConversationId != null) {
      await ConversationModelOverrideService.clearOverride(
        normalConversationId,
      );
    }
    if (!mounted) return;
    setState(() {
      _conversationModelOverride = null;
      _pendingConversationModelOverride = null;
      _showConversationModelMentionChip = false;
      _modelOptionsByProfileId = _mergeChatModelOptions(
        profiles: _modelProviderProfiles,
        source: _modelOptionsByProfileId,
        sceneCatalog: _sceneCatalog,
        overrideSelection: null,
      );
    });
    showToast('已恢复场景默认模型', type: ToastType.success);
  }

  Map<String, dynamic>? _buildAgentModelOverridePayload() {
    if (_activeConversationMode != ChatPageMode.normal) {
      return null;
    }
    if (!_showConversationModelMentionChip) {
      return null;
    }
    final override = _activeConversationModelOverrideSelection;
    if (override == null) {
      return null;
    }
    return {
      'providerProfileId': override.providerProfileId,
      'modelId': override.modelId,
    };
  }

  _ActiveModelMentionToken? _parseActiveModelMentionToken(
    TextEditingValue value,
  ) {
    if (_activeConversationMode != ChatPageMode.normal || _isOpenClawSurface) {
      return null;
    }
    final selectionEnd = value.selection.baseOffset;
    final text = value.text;
    if (selectionEnd < 0 || selectionEnd > text.length) {
      return null;
    }

    var tokenStart = selectionEnd;
    while (tokenStart > 0) {
      final char = text.substring(tokenStart - 1, tokenStart);
      if (RegExp(r'\s').hasMatch(char)) {
        break;
      }
      tokenStart -= 1;
    }

    if (tokenStart >= text.length ||
        text.substring(tokenStart, tokenStart + 1) != '@') {
      return null;
    }
    if (tokenStart > 0) {
      final previousChar = text.substring(tokenStart - 1, tokenStart);
      if (!RegExp(r'\s').hasMatch(previousChar)) {
        return null;
      }
    }

    final query = text.substring(tokenStart + 1, selectionEnd);
    if (query.contains(RegExp(r'\s'))) {
      return null;
    }
    return _ActiveModelMentionToken(
      query: query,
      start: tokenStart,
      end: selectionEnd,
    );
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
          conversation ??
          runtime?.conversation ??
          _currentConversationByMode[mode],
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
          runtime?.deepThinkingContent ??
          (_deepThinkingContentByMode[mode] ?? ''),
      isDeepThinking:
          runtime?.isDeepThinking ?? (_isDeepThinkingByMode[mode] ?? false),
      currentDispatchTaskId:
          runtime?.currentDispatchTaskId ?? _currentDispatchTaskIdByMode[mode],
      currentThinkingStage:
          runtime?.currentThinkingStage ??
          (_currentThinkingStageByMode[mode] ?? 1),
      isInputAreaVisible:
          runtime?.isInputAreaVisible ??
          (_isInputAreaVisibleByMode[mode] ?? true),
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
      'thinkingContent': thinkingContent ?? '',
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
    unawaited(_loadNormalChatModelContext());
    initializeConversation();
    _notifySummarySheetReadyIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        GoRouterManager.routeObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      GoRouterManager.routeObserver.subscribe(this, route);
    }
  }

  void _unusedSetupAiServiceCallbacks() {}

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
    if (_subscribedRoute != null) {
      GoRouterManager.routeObserver.unsubscribe(this);
      _subscribedRoute = null;
    }
    _runtimeCoordinator.removeListener(_handleRuntimeCoordinatorChanged);
    AppUpdateService.statusNotifier.removeListener(
      _handleAppUpdateStatusChanged,
    );
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

  @override
  void didPopNext() {
    // Return from settings pages should immediately refresh the model chip
    // displayed in chat app bar.
    unawaited(_loadNormalChatModelContext());
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}

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

  Future<void> _handleAppUpdateBannerDismiss() async {
    final status = _appUpdateStatus;
    if (status == null || !status.hasUpdate) return;
    await AppUpdateService.dismissBanner(status);
    if (!mounted) return;
    setState(() {});
  }

  Widget? _buildAppUpdateBanner() {
    final status = _appUpdateStatus;
    if (status == null || !AppUpdateService.shouldShowBanner(status)) {
      return null;
    }
    return AppUpdateBanner(
      text: '发现新版本 ${status.latestVersionLabel}，点击更新',
      onTap: () {
        _handleAppUpdateBannerTap();
      },
      onClose: () {
        _handleAppUpdateBannerDismiss();
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
        _showModelMentionPanel = false;
        _activeModelMentionToken = null;
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
    unawaited(_loadNormalChatModelContext());
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
    final value = _messageController.value;
    final shouldShowSlash = value.text.trimLeft().startsWith('/');
    final nextMentionToken = shouldShowSlash
        ? null
        : _parseActiveModelMentionToken(value);
    final shouldShowModelMention = nextMentionToken != null;
    final shouldCollapseOpenClawPanel = !shouldShowSlash || !_isOpenClawSurface;

    if (!mounted) return;

    final shouldUpdate =
        shouldShowSlash != _showSlashCommandPanel ||
        shouldShowModelMention != _showModelMentionPanel ||
        nextMentionToken != _activeModelMentionToken ||
        (shouldCollapseOpenClawPanel && _openClawPanelExpanded);
    if (!shouldUpdate) {
      return;
    }

    setState(() {
      _showSlashCommandPanel = shouldShowSlash;
      _showModelMentionPanel = shouldShowModelMention;
      _activeModelMentionToken = nextMentionToken;
      if (shouldCollapseOpenClawPanel) {
        _openClawPanelExpanded = false;
      }
    });
  }

  void _showOpenClawCommandPanel({bool expand = false}) {
    if (!_isOpenClawSurface) {
      _showSnackBar('请先顶部滑动到 OpenClaw 模式');
      return;
    }
    if (!mounted) return;
    setState(() {
      _showSlashCommandPanel = true;
      _showModelMentionPanel = false;
      _activeModelMentionToken = null;
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
      _showModelMentionPanel = false;
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
    if (!_showSlashCommandPanel &&
        !_showModelMentionPanel &&
        !_openClawPanelExpanded) {
      return;
    }
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
      unawaited(_loadNormalChatModelContext());
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
      _deepThinkingContent = '';
      _isDeepThinking = false;
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
        modelOverride: _buildAgentModelOverridePayload(),
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

  Future<void> _openConversationModelSelector(
    BuildContext anchorContext,
  ) async {
    if (_activeMode != ChatPageMode.normal) {
      return;
    }
    if (_showSlashCommandPanel ||
        _showModelMentionPanel ||
        _openClawPanelExpanded) {
      setState(() {
        _showSlashCommandPanel = false;
        _showModelMentionPanel = false;
        _openClawPanelExpanded = false;
      });
    }
    final hasSelectableModels = _modelProviderProfiles.any((profile) {
      if (!profile.configured) {
        return false;
      }
      final models =
          _modelOptionsByProfileId[profile.id] ?? const <ProviderModelOption>[];
      return models.isNotEmpty;
    });
    if (!hasSelectableModels) {
      return;
    }
    _inputFocusNode.unfocus();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlay == null || anchorBox == null || !anchorBox.hasSize) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final anchorRect = Rect.fromPoints(topLeft, bottomRight);
    final popupWidth = anchorBox.size.width.clamp(160.0, 320.0).toDouble();
    const popupMaxHeight = 360.0;
    final position = PopupMenuAnchorPosition.fromAnchorRect(
      anchorRect: anchorRect,
      overlaySize: overlay.size,
      estimatedMenuHeight: popupMaxHeight,
      reservedBottom: MediaQuery.of(context).viewInsets.bottom,
    );
    final selected = await showMenu<_ChatModelOverrideSelection>(
      context: context,
      color: Colors.white,
      elevation: 8,
      constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: position,
      items: [
        _ConversationModelSelectorPopupEntry(
          width: popupWidth,
          estimatedHeight: popupMaxHeight,
          profiles: _modelProviderProfiles,
          providerModelsByProfileId: _modelOptionsByProfileId,
          currentSelection: _activeDispatchSceneSelection,
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    await _applyDispatchSceneModelSelection(
      providerProfileId: selected.providerProfileId,
      modelId: selected.modelId,
    );
  }

  Future<void> _applyDispatchSceneModelSelection({
    required String providerProfileId,
    required String modelId,
  }) async {
    const sceneId = 'scene.dispatch.model';
    final currentSelection = _activeDispatchSceneSelection;
    if (currentSelection != null &&
        currentSelection.providerProfileId == providerProfileId &&
        currentSelection.modelId == modelId) {
      return;
    }
    try {
      await SceneModelConfigService.saveSceneModelBinding(
        sceneId: sceneId,
        providerProfileId: providerProfileId,
        modelId: modelId,
      );
      await _loadNormalChatModelContext();
      if (!mounted) return;
      showToast('Agent 模型已切换到 $modelId', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('更新 Agent 模型失败：$e', type: ToastType.error);
    }
  }

  Widget _buildModelMentionPanel() {
    return _ChatModelMentionPanel(
      profiles: _modelProviderProfiles,
      providerModelsByProfileId: _modelOptionsByProfileId,
      query: _activeModelMentionToken?.query ?? '',
      currentSelection: _activeConversationModelOverrideSelection,
      onSelect: (selection) {
        unawaited(
          _applyConversationModelOverride(
            providerProfileId: selection.providerProfileId,
            modelId: selection.modelId,
            displayAsMentionChip: true,
          ),
        );
      },
    );
  }

  Widget _buildSlashCommandPanel() {
    final visible =
        _showSlashCommandPanel ||
        _showModelMentionPanel ||
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
              padding: _showModelMentionPanel
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
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
                  : _showModelMentionPanel
                  ? _buildModelMentionPanel()
                  : !_isOpenClawSurface
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '请滑到右侧 OpenClaw 模式',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : InkWell(
                      onTap: () {
                        _showOpenClawCommandPanel(expand: true);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.link_rounded,
                              size: 16,
                              color: Color(0xFF2C7FEB),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '/openclaw',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                          ],
                        ),
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
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final viewPaddingBottom = mediaQuery.viewPadding.bottom;
    final shouldLiftComposerForKeyboard = _inputFocusNode.hasFocus;
    final composerKeyboardLift = shouldLiftComposerForKeyboard
        ? bottomInset
        : 0.0;
    // 只在聊天输入框聚焦时抬升输入区；其它面板（例如顶部模型搜索）唤起键盘不影响底部输入栏。
    final inputBottomPadding =
        (viewPaddingBottom + edgeInset - composerKeyboardLift)
            .clamp(0.0, edgeInset)
            .toDouble();
    final keyboardSpacer = shouldLiftComposerForKeyboard
        ? composerKeyboardLift
        : 0.0;
    final commandPanelBottomOffset =
        (_popupMenuBottomOffset() + inputBottomPadding + keyboardSpacer + 6)
            .toDouble();

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
        resizeToAvoidBottomInset: false,
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
                      activeModelId:
                          _activeSurfaceMode == ChatSurfaceMode.normal
                          ? _activeNormalChatModelId
                          : null,
                      onModelTap: _activeSurfaceMode == ChatSurfaceMode.normal
                          ? (anchorContext) {
                              unawaited(
                                _openConversationModelSelector(anchorContext),
                              );
                            }
                          : null,
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
                          selectedModelOverrideId:
                              _activeMode == ChatPageMode.normal &&
                                  _showConversationModelMentionChip
                              ? _activeConversationModelOverrideSelection
                                    ?.modelId
                              : null,
                          onClearSelectedModelOverride:
                              _activeMode == ChatPageMode.normal &&
                                  _activeConversationModelOverrideSelection !=
                                      null
                              ? () {
                                  unawaited(_clearConversationModelOverride());
                                }
                              : null,
                          topBanner: _buildAppUpdateBanner(),
                        ),
                      ),
                    SizedBox(height: inputBottomPadding + keyboardSpacer),
                  ],
                ),
                if (!_isWorkspaceSurface)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: commandPanelBottomOffset,
                    child: _buildSlashCommandPanel(),
                  ),
                // Popup menu
                if (_isPopupVisible && !_isWorkspaceSurface)
                  Positioned(
                    right: 24,
                    // 顶部模型搜索等场景会弹键盘，但这里保持固定锚点偏移，
                    // 避免底部菜单随全局 viewInsets 产生额外跳动。
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

class _ActiveModelMentionToken {
  final String query;
  final int start;
  final int end;

  const _ActiveModelMentionToken({
    required this.query,
    required this.start,
    required this.end,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ActiveModelMentionToken &&
        other.query == query &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(query, start, end);
}

class _ChatModelOverrideSelection {
  final String providerProfileId;
  final String modelId;

  const _ChatModelOverrideSelection({
    required this.providerProfileId,
    required this.modelId,
  });
}

class _ChatModelMentionPanel extends StatefulWidget {
  final List<ModelProviderProfileSummary> profiles;
  final Map<String, List<ProviderModelOption>> providerModelsByProfileId;
  final String query;
  final _ChatModelOverrideSelection? currentSelection;
  final ValueChanged<_ChatModelOverrideSelection> onSelect;

  const _ChatModelMentionPanel({
    required this.profiles,
    required this.providerModelsByProfileId,
    required this.query,
    required this.currentSelection,
    required this.onSelect,
  });

  @override
  State<_ChatModelMentionPanel> createState() => _ChatModelMentionPanelState();
}

class _ChatModelMentionPanelState extends State<_ChatModelMentionPanel> {
  List<ProviderModelOption> _filteredModels(String profileId) {
    final normalizedQuery = widget.query.trim().toLowerCase();
    final models =
        widget.providerModelsByProfileId[profileId] ??
        const <ProviderModelOption>[];
    if (normalizedQuery.isEmpty) {
      return models;
    }
    return models.where((item) {
      final modelId = item.id.toLowerCase();
      final displayName = item.displayName.toLowerCase();
      return modelId.contains(normalizedQuery) ||
          displayName.contains(normalizedQuery);
    }).toList();
  }

  Widget _buildProviderHeader(
    ModelProviderProfileSummary profile,
    int modelCount,
  ) {
    final isCurrentProvider =
        widget.currentSelection?.providerProfileId == profile.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$modelCount',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9AA4B6),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isCurrentProvider) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_circle_rounded,
                size: 13,
                color: Color(0xFF2C7FEB),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelRow({
    required ModelProviderProfileSummary profile,
    required ProviderModelOption item,
  }) {
    final selected =
        widget.currentSelection?.providerProfileId == profile.id &&
        widget.currentSelection?.modelId == item.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: InkWell(
        onTap: () {
          widget.onSelect(
            _ChatModelOverrideSelection(
              providerProfileId: profile.id,
              modelId: item.id,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF3FF) : const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: Color(0xFF2C7FEB),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleProfiles = widget.profiles.where((profile) {
      if (!profile.configured) {
        return false;
      }
      return _filteredModels(profile.id).isNotEmpty;
    }).toList();

    if (visibleProfiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final dynamicMaxHeight =
        (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 180)
            .clamp(150.0, 240.0)
            .toDouble();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: dynamicMaxHeight),
      child: Scrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 6),
          itemCount: visibleProfiles.length,
          itemBuilder: (context, index) {
            final profile = visibleProfiles[index];
            final models = _filteredModels(profile.id);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProviderHeader(profile, models.length),
                if (models.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Text(
                      '没有匹配的模型',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: models
                        .map(
                          (item) =>
                              _buildModelRow(profile: profile, item: item),
                        )
                        .toList(),
                  ),
                if (index != visibleProfiles.length - 1)
                  const SizedBox(height: 4),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConversationModelSelectorPopupEntry
    extends PopupMenuEntry<_ChatModelOverrideSelection> {
  const _ConversationModelSelectorPopupEntry({
    required this.width,
    required this.estimatedHeight,
    required this.profiles,
    required this.providerModelsByProfileId,
    required this.currentSelection,
  });

  final double width;
  final double estimatedHeight;
  final List<ModelProviderProfileSummary> profiles;
  final Map<String, List<ProviderModelOption>> providerModelsByProfileId;
  final _ChatModelOverrideSelection? currentSelection;

  @override
  double get height => estimatedHeight;

  @override
  bool represents(_ChatModelOverrideSelection? value) => false;

  @override
  State<_ConversationModelSelectorPopupEntry> createState() =>
      _ConversationModelSelectorPopupEntryState();
}

class _ConversationModelSelectorPopupEntryState
    extends State<_ConversationModelSelectorPopupEntry> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _expandedProfileIds;

  bool get _hasSearchQuery => _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _expandedProfileIds = <String>{
      if (widget.currentSelection != null)
        widget.currentSelection!.providerProfileId,
    };
    if (_expandedProfileIds.isEmpty && widget.profiles.isNotEmpty) {
      _expandedProfileIds.add(widget.profiles.first.id);
    }
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProviderModelOption> _filteredModels(String profileId) {
    final query = _searchController.text.trim().toLowerCase();
    final models = widget.providerModelsByProfileId[profileId] ?? const [];
    if (query.isEmpty) {
      return models;
    }
    return models.where((item) {
      final modelId = item.id.toLowerCase();
      final displayName = item.displayName.toLowerCase();
      return modelId.contains(query) || displayName.contains(query);
    }).toList();
  }

  List<ModelProviderProfileSummary> get _visibleProfiles {
    final configuredProfiles = widget.profiles
        .where((profile) => profile.configured)
        .toList();
    if (!_hasSearchQuery) {
      return configuredProfiles;
    }
    return configuredProfiles.where((profile) {
      return _filteredModels(profile.id).isNotEmpty;
    }).toList();
  }

  bool _isExpanded(String profileId) {
    if (_hasSearchQuery) {
      return true;
    }
    return _expandedProfileIds.contains(profileId);
  }

  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: Color(0xFF9AA4B6)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: false,
              scrollPadding: EdgeInsets.zero,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜索模型 ID',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9AA4B6),
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ModelProviderProfileSummary profile) {
    final expanded = _isExpanded(profile.id);
    final models = _filteredModels(profile.id);
    final isSelectedProvider =
        widget.currentSelection?.providerProfileId == profile.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: InkWell(
        onTap: () {
          if (_hasSearchQuery) {
            return;
          }
          setState(() {
            if (expanded) {
              _expandedProfileIds.remove(profile.id);
            } else {
              _expandedProfileIds.add(profile.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${models.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9AA4B6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isSelectedProvider) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: Color(0xFF2C7FEB),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                _hasSearchQuery
                    ? Icons.unfold_more_rounded
                    : expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 16,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelRow({
    required ModelProviderProfileSummary profile,
    required ProviderModelOption model,
  }) {
    final selected =
        widget.currentSelection?.providerProfileId == profile.id &&
        widget.currentSelection?.modelId == model.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop(
            _ChatModelOverrideSelection(
              providerProfileId: profile.id,
              modelId: model.id,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF3FF) : const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  model.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: Color(0xFF2C7FEB),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dynamicMaxHeight =
        (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 96)
            .clamp(220.0, widget.estimatedHeight)
            .toDouble();
    final configuredProfiles = widget.profiles
        .where((profile) => profile.configured)
        .toList();
    final visibleProfiles = _visibleProfiles;
    return SizedBox(
      width: widget.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dynamicMaxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearchRow(),
            if (configuredProfiles.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '请先在模型提供商页配置 Provider',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else if (visibleProfiles.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '没有匹配的模型',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Flexible(
                child: Scrollbar(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: visibleProfiles.length,
                    itemBuilder: (context, index) {
                      final profile = visibleProfiles[index];
                      final expanded = _isExpanded(profile.id);
                      final models = _filteredModels(profile.id);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildProfileHeader(profile),
                          if (expanded)
                            if (models.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                                child: Text(
                                  '该 Provider 暂无可选模型',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              )
                            else
                              Column(
                                children: models
                                    .map(
                                      (item) => _buildModelRow(
                                        profile: profile,
                                        model: item,
                                      ),
                                    )
                                    .toList(),
                              ),
                          if (index != visibleProfiles.length - 1)
                            const SizedBox(height: 6),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
