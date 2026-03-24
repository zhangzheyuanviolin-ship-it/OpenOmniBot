part of 'chat_page.dart';

mixin _ChatPageBrowserMixin on _ChatPageStateBase {
  static const double _kBrowserOverlayMinWidth = 280;
  static const double _kBrowserOverlayMinHeight = 240;
  static const double _kBrowserOverlayMaxWidthFactor = 0.92;
  static const double _kBrowserOverlayMaxHeightFactor = 0.78;
  static const double _kBrowserOverlayHorizontalMargin = 16;
  static const double _kBrowserOverlayTopMargin = 64;
  static const double _kBrowserOverlayBottomMargin = 16;

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
  void _resizeBrowserOverlay(Offset delta, BoxConstraints constraints) {
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
      child: ChatBrowserOverlay(
        key: ValueKey(
          'agent-browser-overlay-${snapshot.workspaceId}-$_browserOverlayViewSeed',
        ),
        workspaceId: snapshot.workspaceId,
        title: snapshot.title,
        currentUrl: snapshot.currentUrl,
        onClose: _hideBrowserOverlay,
        onDragDelta: (delta) => _moveBrowserOverlay(delta, constraints),
        onResizeDelta: (delta) => _resizeBrowserOverlay(delta, constraints),
      ),
    );
  }
}
