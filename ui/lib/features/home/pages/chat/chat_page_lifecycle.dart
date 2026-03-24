part of 'chat_page.dart';

mixin _ChatPageLifecycleMixin on _ChatPageStateBase {
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
    unawaited(_refreshLiveBrowserSessionSnapshot(syncRuntime: true));
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

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_argsChanged(oldWidget.args, widget.args)) {
      debugPrint(
        '[ChatPage] args changed: ${oldWidget.args} -> ${widget.args}',
      );
      if (_activeSurfaceMode == ChatSurfaceMode.workspace &&
          _shouldOpenNormalChatForArgs(widget.args)) {
        _forceSwitchToNormalSurface();
      }
      _resetAndReloadConversation();
      _notifySummarySheetReadyIfNeeded();
    }
  }

  @override
  bool _argsChanged(List<String> oldArgs, List<String> newArgs) {
    if (oldArgs.length != newArgs.length) return true;
    for (int i = 0; i < oldArgs.length; i++) {
      if (oldArgs[i] != newArgs[i]) return true;
    }
    return false;
  }

  @override
  bool _shouldOpenNormalChatForArgs(List<String> args) {
    if (args.isEmpty) {
      return false;
    }
    final first = args.first.trim();
    if (first.isEmpty) {
      return false;
    }
    if (first == 'new' || first == '__new__') {
      return true;
    }
    return int.tryParse(first) != null;
  }

  @override
  void _forceSwitchToNormalSurface() {
    _storeDraftForActiveConversationMode();
    if (!mounted) return;
    setState(() {
      _activeSurfaceMode = ChatSurfaceMode.normal;
      _activeConversationMode = ChatPageMode.normal;
      _showSlashCommandPanel = false;
      _showModelMentionPanel = false;
      _activeModelMentionToken = null;
      _openClawPanelExpanded = false;
    });
    _applyDraftForConversationMode(ChatPageMode.normal);
    _jumpToCurrentModePage(animate: false);
  }

  @override
  void _resetAndReloadConversation() {
    _resetLocalConversationState(_activeMode);
    _vlmAnswerController.clear();
    _messageController.clear();
    initializeConversation();
  }

  @override
  void _notifySummarySheetReadyIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AssistsMessageService.notifySummarySheetReady();
    });
  }

  @override
  Future<void> _initializeHalfScreenEngineIfNeeded() async {
    if (_hasInitializedHalfScreen) return;
    _hasInitializedHalfScreen = true;
    await AppStateService.initHalfScreenEngine();
  }

  @override
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

  @override
  Future<void> _toggleCompanionMode() async {
    if (_isCompanionToggleLoading) return;
    if (_isCompanionModeEnabled) {
      await _cancelCompanionMode();
      return;
    }
    await _startCompanionMode();
  }

  @override
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

  @override
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
        _companionCountdown = _ChatPageStateBase.kCompanionCountdownDuration;
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

  @override
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

  @override
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

  @override
  void _resetCompanionCountdown() {
    _companionCountdownTimer?.cancel();
    _companionCountdownTimer = null;
    if (!mounted) {
      _companionCountdown = _ChatPageStateBase.kCompanionCountdownDuration;
      _showCompanionCountdown = false;
      return;
    }
    setState(() {
      _companionCountdown = _ChatPageStateBase.kCompanionCountdownDuration;
      _showCompanionCountdown = false;
    });
  }

  @override
  void _interruptCompanionAutoHomeIfNeeded() {
    if (!_isCompanionModeEnabled || !_showCompanionCountdown) {
      return;
    }
    _resetCompanionCountdown();
    unawaited(AssistsMessageService.cancelCompanionGoHome());
  }

  @override
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
    _openClawDeployConfigController.dispose();
    _companionCountdownTimer?.cancel();
    _openClawDeploySnapshotPoller?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    unawaited(_loadNormalChatModelContext());
    unawaited(_refreshLiveBrowserSessionSnapshot(syncRuntime: true));
    if (_openClawDeployPanelExpanded) {
      unawaited(_refreshOpenClawDeployPanelState());
    }
  }

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void didPushNext() {}

  @override
  void _onFocusChange() {}

  @override
  void _handleAppUpdateStatusChanged() {
    if (!mounted) return;
    setState(() {
      _appUpdateStatus = AppUpdateService.statusNotifier.value;
    });
  }

  @override
  double _popupMenuBottomOffset() {
    final renderObject = _inputAreaKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 72;
    }
    final offset = renderObject.size.height - 8;
    return offset < 72 ? 72 : offset;
  }

  @override
  Future<void> _handleAppUpdateBannerTap() async {
    final status = _appUpdateStatus;
    if (status == null || !status.hasUpdate || !mounted) return;
    await showAppUpdateDialog(context, status);
  }

  @override
  Future<void> _handleAppUpdateBannerDismiss() async {
    final status = _appUpdateStatus;
    if (status == null || !status.hasUpdate) return;
    await AppUpdateService.dismissBanner(status);
    if (!mounted) return;
    setState(() {});
  }

  @override
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

  @override
  int _pageIndexForSurface(ChatSurfaceMode mode) => switch (mode) {
    ChatSurfaceMode.workspace => 0,
    ChatSurfaceMode.normal => 1,
    ChatSurfaceMode.openclaw => 2,
  };

  @override
  ChatSurfaceMode _surfaceForPageIndex(int pageIndex) => switch (pageIndex) {
    0 => ChatSurfaceMode.workspace,
    2 => ChatSurfaceMode.openclaw,
    _ => ChatSurfaceMode.normal,
  };

  @override
  ScrollController _scrollControllerForMode(ChatPageMode mode) {
    return mode == ChatPageMode.openclaw
        ? _openClawMessageScrollController
        : _normalMessageScrollController;
  }

  @override
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

  @override
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
        _setChatIslandDisplayLayerForMode(
          ChatPageMode.normal,
          ChatIslandDisplayLayer.model,
        );
        _isBrowserOverlayVisible = false;
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
        _setChatIslandDisplayLayerForMode(
          ChatPageMode.normal,
          ChatIslandDisplayLayer.model,
        );
        _isBrowserOverlayVisible = false;
      });
      _applyDraftForConversationMode(ChatPageMode.openclaw);
      await StorageService.setBool(kOpenClawEnabledKey, hasConfig);
      if (syncPage) _jumpToCurrentModePage();
      if (!hasConfig) {
        showToast('请先输入 /deploy 或 /openclaw 完成配置');
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

  @override
  void _handleModePageChanged(int pageIndex) {
    final targetMode = _surfaceForPageIndex(pageIndex);
    unawaited(_switchChatMode(targetMode, syncPage: false));
  }

  @override
  void _storeDraftForActiveConversationMode() {
    _draftMessageByMode[_activeConversationMode] = _messageController.text;
  }

  @override
  void _applyDraftForConversationMode(ChatPageMode mode) {
    final draft = _draftMessageByMode[mode] ?? '';
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
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
      unawaited(_refreshLiveBrowserSessionSnapshot(syncRuntime: true));
      if (_openClawDeployPanelExpanded) {
        unawaited(_refreshOpenClawDeployPanelState());
      }
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _resetCompanionCountdown();
      unawaited(AssistsMessageService.cancelCompanionGoHome());
    }
  }
}
