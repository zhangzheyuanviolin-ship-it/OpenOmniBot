part of 'chat_page.dart';

mixin _ChatPageBrowserMixin on _ChatPageStateBase {
  static const double _kBrowserOverlayMinWidth = 280;
  static const double _kBrowserOverlayMinHeight = 240;
  static const double _kBrowserOverlayMaxWidthFactor = 0.92;
  static const double _kBrowserOverlayMaxHeightFactor = 0.78;
  static const double _kBrowserOverlayHorizontalMargin = 16;
  static const double _kBrowserOverlayTopMargin = 64;
  static const double _kBrowserOverlayBottomMargin = 16;
  static const double _kPageSwipeThreshold = 18;
  static const double _kRevealInterruptThreshold = 6;

  bool _isNormalChatListAtBottom() {
    final controller = _normalMessageScrollController;
    if (!controller.hasClients) {
      return true;
    }
    final position = controller.position;
    final distanceToBottom = (position.pixels - position.minScrollExtent).abs();
    return distanceToBottom <= 2;
  }

  bool _isInNewConversationPullActivationZone(Offset position) {
    if (_isPointerInside(_inputAreaKey, position)) {
      return false;
    }
    final inputContext = _inputAreaKey.currentContext;
    if (inputContext == null) {
      final screenHeight = MediaQuery.of(context).size.height;
      return position.dy >=
          screenHeight -
              _ChatPageStateBase._newConversationPullActivationZoneHeight;
    }
    final box = inputContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      final screenHeight = MediaQuery.of(context).size.height;
      return position.dy >=
          screenHeight -
              _ChatPageStateBase._newConversationPullActivationZoneHeight;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final zoneTop =
        rect.top - _ChatPageStateBase._newConversationPullActivationZoneHeight;
    return position.dy >= zoneTop;
  }

  bool _canStartNewConversationPullGesture(PointerDownEvent event) {
    if (_activeSurfaceMode != ChatSurfaceMode.normal ||
        _activeMode != ChatPageMode.normal ||
        _isPopupVisible ||
        _showSlashCommandPanel ||
        _showModelMentionPanel ||
        _openClawPanelExpanded ||
        _isAiResponding ||
        _isCheckingExecutableTask ||
        _isExecutingTask) {
      return false;
    }
    return _isNormalChatListAtBottom() &&
        _isInNewConversationPullActivationZone(event.position);
  }

  void _updateNewConversationPullDistance(double distance) {
    final clampedDistance = distance
        .clamp(0.0, _ChatPageStateBase._newConversationPullMaxDistance)
        .toDouble();
    final reachedThreshold =
        clampedDistance >= _ChatPageStateBase._newConversationPullThreshold;
    if (_newConversationPullDistance == clampedDistance &&
        _newConversationPullThresholdReached == reachedThreshold) {
      return;
    }
    if (mounted) {
      setState(() {
        _newConversationPullDistance = clampedDistance;
        _newConversationPullThresholdReached = reachedThreshold;
      });
    } else {
      _newConversationPullDistance = clampedDistance;
      _newConversationPullThresholdReached = reachedThreshold;
    }
    if (reachedThreshold && !_newConversationPullHapticTriggered) {
      _newConversationPullHapticTriggered = true;
      unawaited(_triggerNewConversationPullHaptic());
    }
  }

  void _resetNewConversationPullGesture({bool clearPointer = false}) {
    final hasVisualChanges =
        _isNewConversationPullTracking ||
        _newConversationPullDistance > 0 ||
        _newConversationPullThresholdReached ||
        _newConversationPullHapticTriggered;
    if (hasVisualChanges) {
      if (mounted) {
        setState(() {
          _isNewConversationPullTracking = false;
          _newConversationPullDistance = 0;
          _newConversationPullThresholdReached = false;
          _newConversationPullHapticTriggered = false;
        });
      } else {
        _isNewConversationPullTracking = false;
        _newConversationPullDistance = 0;
        _newConversationPullThresholdReached = false;
        _newConversationPullHapticTriggered = false;
      }
    }
    if (clearPointer) {
      _pageGesturePointerId = null;
      _pageVerticalDragDelta = 0;
    }
  }

  Future<void> _triggerNewConversationPullHaptic() async {
    try {
      final enabled = await CacheUtil.getBool(
        'app_vibrate',
        defaultValue: true,
      );
      if (!enabled) {
        return;
      }
      await HapticFeedback.mediumImpact();
    } catch (error) {
      debugPrint('[ChatPage] failed to trigger pull haptic: $error');
    }
  }

  Future<void> _triggerNewConversationFromPull() async {
    if (_isCreatingConversationFromPull) {
      return;
    }
    _isCreatingConversationFromPull = true;
    try {
      GoRouterManager.pushReplacement(
        '/home/chat',
        extra: ConversationThreadTarget.newConversation(
          mode: _conversationModeForPageMode(_activeMode),
          requestKey: DateTime.now().microsecondsSinceEpoch.toString(),
        ),
      );
    } finally {
      _isCreatingConversationFromPull = false;
    }
  }

  void _applyPageVerticalIntent(double delta) {
    if (_activeSurfaceMode != ChatSurfaceMode.normal ||
        delta.abs() < _kPageSwipeThreshold) {
      return;
    }
    _handleChatIslandDisplayLayerChanged(
      delta > 0 ? ChatIslandDisplayLayer.tools : ChatIslandDisplayLayer.model,
    );
  }

  @override
  void _handlePagePointerDown(PointerDownEvent event) {
    if (_activeSurfaceMode != ChatSurfaceMode.normal) {
      _resetNewConversationPullGesture(clearPointer: true);
      return;
    }
    if (_isBrowserOverlayVisible &&
        _isPointerInside(_browserOverlayKey, event.position)) {
      _resetNewConversationPullGesture(clearPointer: true);
      return;
    }
    if (_canStartNewConversationPullGesture(event)) {
      _pageGesturePointerId = event.pointer;
      _pageVerticalDragDelta = 0;
      if (mounted) {
        setState(() {
          _isNewConversationPullTracking = true;
          _newConversationPullDistance = 0;
          _newConversationPullThresholdReached = false;
          _newConversationPullHapticTriggered = false;
        });
      } else {
        _isNewConversationPullTracking = true;
        _newConversationPullDistance = 0;
        _newConversationPullThresholdReached = false;
        _newConversationPullHapticTriggered = false;
      }
      return;
    }
    _resetNewConversationPullGesture();
    _pageGesturePointerId = event.pointer;
    _pageVerticalDragDelta = 0;
  }

  @override
  void _handlePagePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pageGesturePointerId ||
        _activeSurfaceMode != ChatSurfaceMode.normal) {
      return;
    }
    if (ToolCardDetailGestureGate.containsPointer(event.pointer)) {
      _resetNewConversationPullGesture(clearPointer: true);
      return;
    }
    _pageVerticalDragDelta += event.delta.dy;
    if (_normalSurfaceModelRevealTimer != null &&
        !_normalSurfaceModelRevealInterrupted &&
        _pageVerticalDragDelta.abs() >= _kRevealInterruptThreshold) {
      _interruptNormalSurfaceModelReveal();
    }
    if (_isNewConversationPullTracking) {
      _updateNewConversationPullDistance(-_pageVerticalDragDelta);
    }
  }

  @override
  void _handlePagePointerUp(PointerUpEvent event) {
    if (event.pointer != _pageGesturePointerId) {
      return;
    }
    if (ToolCardDetailGestureGate.containsPointer(event.pointer)) {
      _resetNewConversationPullGesture(clearPointer: true);
      return;
    }
    if (_isNewConversationPullTracking) {
      final shouldCreateNewConversation = _newConversationPullThresholdReached;
      _resetNewConversationPullGesture(clearPointer: true);
      if (shouldCreateNewConversation) {
        unawaited(_triggerNewConversationFromPull());
      }
      return;
    }
    _applyPageVerticalIntent(_pageVerticalDragDelta);
    _resetNewConversationPullGesture(clearPointer: true);
  }

  @override
  void _handlePagePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pageGesturePointerId) {
      return;
    }
    _resetNewConversationPullGesture(clearPointer: true);
  }

  @override
  String _browserSnapshotSignature(ChatBrowserSessionSnapshot? snapshot) {
    if (snapshot == null) {
      return '';
    }
    return [
      snapshot.available ? '1' : '0',
      snapshot.workspaceId,
      snapshot.activeTabId?.toString() ?? '',
      snapshot.currentUrl,
      snapshot.title,
      snapshot.userAgentProfile ?? '',
    ].join('|');
  }

  @override
  void _scheduleBrowserSessionRefreshIfNeeded() {
    if (_activeSurfaceMode != ChatSurfaceMode.normal) {
      return;
    }
    final snapshot = _runtimeForMode(
      ChatPageMode.normal,
    )?.browserSessionSnapshot;
    if (snapshot == null ||
        !snapshot.matchesWorkspace(_expectedBrowserWorkspaceId)) {
      return;
    }
    final signature = _browserSnapshotSignature(snapshot);
    if (signature.isEmpty ||
        signature == _lastObservedBrowserSnapshotSignature) {
      return;
    }
    _lastObservedBrowserSnapshotSignature = signature;
    unawaited(_refreshLiveBrowserSessionSnapshot(syncRuntime: true));
  }

  @override
  Future<void> _refreshLiveBrowserSessionSnapshot({
    bool syncRuntime = false,
  }) async {
    final snapshot = await AgentBrowserSessionService.getLiveSessionSnapshot();
    if (!mounted) {
      return;
    }
    final resolved =
        snapshot?.matchesWorkspace(_expectedBrowserWorkspaceId) == true
        ? snapshot
        : null;
    final previousSignature = _browserSnapshotSignature(
      _liveBrowserSessionSnapshot,
    );
    final nextSignature = _browserSnapshotSignature(resolved);

    if (syncRuntime) {
      final runtime = _runtimeForMode(ChatPageMode.normal);
      if (runtime != null) {
        runtime.browserSessionSnapshot = resolved;
      } else {
        _browserSessionSnapshotByMode[ChatPageMode.normal] = resolved;
      }
    }

    final shouldHideOverlay = resolved == null || !resolved.available;
    if (!mounted) {
      return;
    }
    setState(() {
      _liveBrowserSessionSnapshot = resolved;
      if (previousSignature != nextSignature) {
        _browserOverlayViewSeed += 1;
      }
      if (shouldHideOverlay) {
        _isBrowserOverlayVisible = false;
        _isBrowserOverlayInitialized = false;
      }
    });
  }

  @override
  void _setChatIslandDisplayLayerForMode(
    ChatPageMode mode,
    ChatIslandDisplayLayer layer,
  ) {
    final resolvedLayer = mode == ChatPageMode.normal
        ? layer
        : ChatIslandDisplayLayer.mode;
    _chatIslandDisplayLayerByMode[mode] = resolvedLayer;
    final runtime = _runtimeForMode(mode);
    if (runtime != null) {
      runtime.chatIslandDisplayLayer = resolvedLayer;
    }
  }

  @override
  void _handleChatIslandDisplayLayerChanged(ChatIslandDisplayLayer layer) {
    if (_activeSurfaceMode != ChatSurfaceMode.normal) {
      return;
    }
    _cancelNormalSurfaceModelReveal();
    setState(() {
      _setChatIslandDisplayLayerForMode(ChatPageMode.normal, layer);
      if (layer != ChatIslandDisplayLayer.tools) {
        _isBrowserOverlayVisible = false;
      }
    });
  }

  @override
  Future<void> _handleTerminalToolTap() async {
    if (_activeSurfaceMode != ChatSurfaceMode.normal) {
      return;
    }
    _cancelNormalSurfaceModelReveal();
    setState(() {
      _setChatIslandDisplayLayerForMode(
        ChatPageMode.normal,
        ChatIslandDisplayLayer.tools,
      );
    });
    try {
      await openNativeTerminal();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showToast('打开终端失败: $error', type: ToastType.error);
    }
  }

  @override
  Future<void> _handleBrowserToolTap() async {
    if (_activeSurfaceMode != ChatSurfaceMode.normal) {
      return;
    }
    _cancelNormalSurfaceModelReveal();
    if (!Platform.isAndroid) {
      showToast('当前平台暂不支持浏览器工具视图', type: ToastType.warning);
      return;
    }
    await _refreshLiveBrowserSessionSnapshot(syncRuntime: true);
    final snapshot = _resolvedBrowserSessionSnapshot;
    if (snapshot == null || !snapshot.available) {
      showToast('当前会话还没有可用的浏览器会话', type: ToastType.warning);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _setChatIslandDisplayLayerForMode(
        ChatPageMode.normal,
        ChatIslandDisplayLayer.tools,
      );
      _isBrowserOverlayVisible = true;
      _browserOverlayViewSeed += 1;
    });
  }

  @override
  void _hideBrowserOverlay() {
    if (!_isBrowserOverlayVisible && !_isBrowserOverlayInitialized) {
      return;
    }
    setState(() {
      _isBrowserOverlayVisible = false;
      _isBrowserOverlayInitialized = false;
    });
  }

  Size _overlayMaxSize(BoxConstraints constraints) {
    final maxWidth = (constraints.maxWidth * _kBrowserOverlayMaxWidthFactor)
        .clamp(_kBrowserOverlayMinWidth, constraints.maxWidth)
        .toDouble();
    final maxHeight = (constraints.maxHeight * _kBrowserOverlayMaxHeightFactor)
        .clamp(_kBrowserOverlayMinHeight, constraints.maxHeight)
        .toDouble();
    return Size(maxWidth, maxHeight);
  }

  Size _clampBrowserOverlaySize(Size size, BoxConstraints constraints) {
    final maxSize = _overlayMaxSize(constraints);
    return Size(
      size.width.clamp(_kBrowserOverlayMinWidth, maxSize.width).toDouble(),
      size.height.clamp(_kBrowserOverlayMinHeight, maxSize.height).toDouble(),
    );
  }

  Offset _clampBrowserOverlayOffset(
    Offset offset,
    Size size,
    BoxConstraints constraints,
  ) {
    final maxLeft =
        (constraints.maxWidth - size.width - _kBrowserOverlayHorizontalMargin)
            .clamp(_kBrowserOverlayHorizontalMargin, double.infinity)
            .toDouble();
    final maxTop =
        (constraints.maxHeight - size.height - _kBrowserOverlayBottomMargin)
            .clamp(_kBrowserOverlayTopMargin, double.infinity)
            .toDouble();
    return Offset(
      offset.dx.clamp(_kBrowserOverlayHorizontalMargin, maxLeft).toDouble(),
      offset.dy.clamp(_kBrowserOverlayTopMargin, maxTop).toDouble(),
    );
  }

  @override
  void _ensureBrowserOverlayGeometry(BoxConstraints constraints) {
    final targetSize = _clampBrowserOverlaySize(
      _browserOverlaySize,
      constraints,
    );
    final defaultOffset = Offset(
      (constraints.maxWidth -
              targetSize.width -
              _kBrowserOverlayHorizontalMargin)
          .clamp(_kBrowserOverlayHorizontalMargin, double.infinity)
          .toDouble(),
      _kBrowserOverlayTopMargin,
    );
    _browserOverlaySize = targetSize;
    _browserOverlayOffset = _clampBrowserOverlayOffset(
      _isBrowserOverlayInitialized ? _browserOverlayOffset : defaultOffset,
      targetSize,
      constraints,
    );
    _isBrowserOverlayInitialized = true;
  }

  @override
  void _moveBrowserOverlay(Offset delta, BoxConstraints constraints) {
    setState(() {
      _ensureBrowserOverlayGeometry(constraints);
      _browserOverlayOffset = _clampBrowserOverlayOffset(
        _browserOverlayOffset + delta,
        _browserOverlaySize,
        constraints,
      );
    });
  }

  @override
  void _resizeBrowserOverlayFromLeft(Offset delta, BoxConstraints constraints) {
    setState(() {
      _ensureBrowserOverlayGeometry(constraints);
      final currentRight = _browserOverlayOffset.dx + _browserOverlaySize.width;
      final maxSize = _overlayMaxSize(constraints);
      final nextHeight = _clampBrowserOverlaySize(
        Size(_browserOverlaySize.width, _browserOverlaySize.height + delta.dy),
        constraints,
      ).height;
      var nextLeft = (_browserOverlayOffset.dx + delta.dx).clamp(
        _kBrowserOverlayHorizontalMargin,
        currentRight - _kBrowserOverlayMinWidth,
      );
      var nextWidth = currentRight - nextLeft;
      if (nextWidth > maxSize.width) {
        nextWidth = maxSize.width;
        nextLeft = currentRight - nextWidth;
      }
      _browserOverlaySize = Size(nextWidth.toDouble(), nextHeight);
      _browserOverlayOffset = _clampBrowserOverlayOffset(
        Offset(nextLeft.toDouble(), _browserOverlayOffset.dy),
        _browserOverlaySize,
        constraints,
      );
    });
  }

  @override
  void _resizeBrowserOverlayFromRight(
    Offset delta,
    BoxConstraints constraints,
  ) {
    setState(() {
      _ensureBrowserOverlayGeometry(constraints);
      final resized = _clampBrowserOverlaySize(
        Size(
          _browserOverlaySize.width + delta.dx,
          _browserOverlaySize.height + delta.dy,
        ),
        constraints,
      );
      _browserOverlaySize = resized;
      _browserOverlayOffset = _clampBrowserOverlayOffset(
        _browserOverlayOffset,
        resized,
        constraints,
      );
    });
  }

  @override
  Rect _browserOverlayBounds(BoxConstraints constraints) {
    final size = _clampBrowserOverlaySize(_browserOverlaySize, constraints);
    final offset = _clampBrowserOverlayOffset(
      _isBrowserOverlayInitialized
          ? _browserOverlayOffset
          : Offset(
              (constraints.maxWidth -
                      size.width -
                      _kBrowserOverlayHorizontalMargin)
                  .clamp(_kBrowserOverlayHorizontalMargin, double.infinity)
                  .toDouble(),
              _kBrowserOverlayTopMargin,
            ),
      size,
      constraints,
    );
    return Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
  }

  @override
  Widget _buildBrowserOverlay(BoxConstraints constraints) {
    if (_activeSurfaceMode != ChatSurfaceMode.normal ||
        !_isBrowserOverlayVisible) {
      return const SizedBox.shrink();
    }
    final snapshot = _resolvedBrowserSessionSnapshot;
    if (snapshot == null || !snapshot.available) {
      return const SizedBox.shrink();
    }
    if (!_isBrowserOverlayInitialized) {
      _ensureBrowserOverlayGeometry(constraints);
    }
    final bounds = _browserOverlayBounds(constraints);
    return Positioned(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      child: KeyedSubtree(
        key: ValueKey(
          'agent-browser-overlay-${snapshot.workspaceId}-$_browserOverlayViewSeed',
        ),
        child: ChatBrowserOverlay(
          key: _browserOverlayKey,
          workspaceId: snapshot.workspaceId,
          title: snapshot.title,
          currentUrl: snapshot.currentUrl,
          onClose: _hideBrowserOverlay,
          onDragDelta: (delta) => _moveBrowserOverlay(delta, constraints),
          onResizeLeftDelta: (delta) =>
              _resizeBrowserOverlayFromLeft(delta, constraints),
          onResizeRightDelta: (delta) =>
              _resizeBrowserOverlayFromRight(delta, constraints),
        ),
      ),
    );
  }
}
