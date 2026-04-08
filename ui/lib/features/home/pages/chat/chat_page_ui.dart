part of 'chat_page.dart';

const int _kDefaultContextTokenThreshold = 128000;
const int _kMinContextTokenThreshold = 10000;
const int _kMaxContextTokenThreshold = 512000;

class _ToolActivityAnchorGeometry {
  const _ToolActivityAnchorGeometry({required this.rect, required this.bottom});

  final Rect rect;
  final double bottom;
}

enum _UserMessageQuickAction { copy, retry }

mixin _ChatPageUiMixin on _ChatPageStateBase {
  _ToolActivityAnchorGeometry? _lastStableToolActivityAnchorGeometry;

  _ToolActivityAnchorGeometry _resolveToolActivityAnchorGeometry({
    required BuildContext layoutContext,
    required BoxConstraints constraints,
    required double inputBottomPadding,
    required double keyboardSpacer,
    required double inputAreaHeight,
  }) {
    final normalizedInputHeight = inputAreaHeight.isFinite
        ? inputAreaHeight
        : 0.0;
    final derivedWidth = math.max(0.0, constraints.maxWidth - 48);
    if (_isSurfacePageScrolling &&
        _lastStableToolActivityAnchorGeometry != null) {
      return _lastStableToolActivityAnchorGeometry!;
    }

    final liveGeometry = _resolveToolActivityAnchorGeometryFromInputArea(
      layoutContext: layoutContext,
      constraints: constraints,
      derivedWidth: derivedWidth,
    );
    if (liveGeometry != null) {
      _lastStableToolActivityAnchorGeometry = liveGeometry;
      return liveGeometry;
    }

    if (_isInputAreaVisible && normalizedInputHeight > 0.5) {
      final bottom =
          (inputBottomPadding + keyboardSpacer + normalizedInputHeight)
              .clamp(0.0, constraints.maxHeight)
              .toDouble();
      final top = (constraints.maxHeight - bottom)
          .clamp(0.0, constraints.maxHeight)
          .toDouble();
      final geometry = _ToolActivityAnchorGeometry(
        rect: Rect.fromLTWH(24, top, derivedWidth, normalizedInputHeight),
        bottom: bottom,
      );
      _lastStableToolActivityAnchorGeometry = geometry;
      return geometry;
    }

    final fallbackBottom = (inputBottomPadding + keyboardSpacer + 84)
        .clamp(0.0, constraints.maxHeight)
        .toDouble();
    final fallbackRect = Rect.fromLTWH(
      24,
      constraints.maxHeight - fallbackBottom,
      derivedWidth,
      0,
    );
    if (!_isInputAreaVisible) {
      return _ToolActivityAnchorGeometry(
        rect: fallbackRect,
        bottom: fallbackBottom,
      );
    }
    final inputContext = _chatInputAreaKey.currentContext;
    final inputBox = inputContext?.findRenderObject();
    final stackBox = layoutContext.findRenderObject();
    if (inputBox is! RenderBox ||
        stackBox is! RenderBox ||
        !inputBox.hasSize ||
        !stackBox.hasSize) {
      return _ToolActivityAnchorGeometry(
        rect: fallbackRect,
        bottom: fallbackBottom,
      );
    }
    final inputOffset = inputBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = inputOffset & inputBox.size;
    final geometry = _ToolActivityAnchorGeometry(
      rect: rect,
      bottom: (constraints.maxHeight - rect.top)
          .clamp(0.0, constraints.maxHeight)
          .toDouble(),
    );
    _lastStableToolActivityAnchorGeometry = geometry;
    return geometry;
  }

  _ToolActivityAnchorGeometry? _resolveToolActivityAnchorGeometryFromInputArea({
    required BuildContext layoutContext,
    required BoxConstraints constraints,
    required double derivedWidth,
  }) {
    if (!_isInputAreaVisible) {
      return null;
    }
    final inputContext = _chatInputAreaKey.currentContext;
    final inputBox = inputContext?.findRenderObject();
    final stackBox = layoutContext.findRenderObject();
    if (inputBox is! RenderBox ||
        stackBox is! RenderBox ||
        !inputBox.hasSize ||
        !stackBox.hasSize) {
      return null;
    }
    final inputOffset = inputBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final top = inputOffset.dy.clamp(0.0, constraints.maxHeight).toDouble();
    return _ToolActivityAnchorGeometry(
      rect: Rect.fromLTWH(24, top, derivedWidth, inputBox.size.height),
      bottom: (constraints.maxHeight - top)
          .clamp(0.0, constraints.maxHeight)
          .toDouble(),
    );
  }

  void _scheduleToolActivityInsetSync(double height) {
    final normalized = height.isFinite ? height : 0.0;
    if ((_toolActivityOccupiedHeight - normalized).abs() < 0.5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (_toolActivityOccupiedHeight - normalized).abs() < 0.5) {
        return;
      }
      setState(() {
        _toolActivityOccupiedHeightByMode[_activeMode] = normalized;
      });
    });
  }

  void _setToolActivityExpanded(bool expanded) {
    if (_isToolActivityExpanded == expanded) {
      return;
    }
    if (!mounted) {
      _toolActivityExpandedByMode[_activeMode] = expanded;
      return;
    }
    setState(() {
      _toolActivityExpandedByMode[_activeMode] = expanded;
    });
  }

  void _handleInputAreaHeightChanged(double height) {
    final normalized = height.isFinite ? height : 0.0;
    if ((_inputAreaHeight - normalized).abs() < 0.5) {
      return;
    }
    if (!mounted) {
      _inputAreaHeightByMode[_activeMode] = normalized;
      return;
    }
    setState(() {
      _inputAreaHeightByMode[_activeMode] = normalized;
    });
  }

  Widget _buildContextCompressingHint() {
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xE61C2430),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFF6FAFF),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '正在压缩上下文',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFF6FAFF),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalSurfaceTransition({
    required double viewportWidth,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _modePageController,
      child: child,
      builder: (context, child) {
        final visibility = _normalSurfaceVisibility;
        if (child == null || visibility <= 0.001) {
          return const SizedBox.shrink();
        }
        final horizontalOffset = -_surfacePageProgress * viewportWidth;
        return IgnorePointer(
          ignoring: visibility < 0.999,
          child: Opacity(
            opacity: Curves.easeOutCubic.transform(visibility),
            child: Transform.translate(
              offset: Offset(horizontalOffset, 0),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget _buildSlashCommandPanel() {
    final visible =
        _showModelMentionPanel ||
        (_isOpenClawSurface &&
            (_showSlashCommandPanel || _openClawPanelExpanded));
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
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        _buildOpenClawCommandRow(
                          icon: Icons.link_rounded,
                          iconColor: const Color(0xFF2C7FEB),
                          title: '/openclaw',
                          subtitle: '手动配置远端或自定义 OpenClaw 网关',
                          onTap: () {
                            _showOpenClawCommandPanel(expand: true);
                          },
                        ),
                      ],
                    ),
            ),
    );
  }

  @override
  Widget _buildModeMessagePage(
    ChatPageMode mode,
    AppBackgroundConfig appearanceConfig,
    AppBackgroundVisualProfile visualProfile,
  ) {
    final runtime = _runtimeForMode(mode);
    return ChatMessageList(
      messages: runtime?.messages ?? _messagesByMode[mode]!,
      scrollController: _scrollControllerForMode(mode),
      bottomOverlayInset: mode == _activeMode ? _toolActivityOccupiedHeight : 0,
      onBeforeTaskExecute: handleBeforeTaskExecute,
      onCancelTask: _onCancelTaskFromCard,
      onRequestAuthorize: mode == ChatPageMode.normal
          ? _requestAuthorizeForExecution
          : null,
      onUserMessageLongPressStart: mode == ChatPageMode.normal
          ? _handleUserMessageLongPressStart
          : null,
      visualProfile: visualProfile,
      appearanceConfig: appearanceConfig,
    );
  }

  @override
  Widget _buildWorkspaceSurfacePage() {
    final workspacePathsFuture = _workspacePathsLoadFuture ??=
        OmnibotResourceService.ensureWorkspacePathsLoaded();
    return FutureBuilder<OmnibotWorkspacePaths>(
      future: workspacePathsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final paths =
            snapshot.data ??
            const OmnibotWorkspacePaths(
              rootPath: '/data/user/0/cn.com.omnimind.bot/workspace',
              shellRootPath: '/workspace',
              internalRootPath:
                  '/data/user/0/cn.com.omnimind.bot/workspace/.omnibot',
            );
        return OmnibotWorkspaceBrowser(
          workspacePath: paths.rootPath,
          workspaceShellPath: paths.shellRootPath,
          translucentSurfaces: AppBackgroundService.current.isActive,
          onCanGoUpChanged: (canGoUp) {
            if (_workspaceBrowserCanGoUp == canGoUp || !mounted) return;
            setState(() {
              _workspaceBrowserCanGoUp = canGoUp;
            });
          },
        );
      },
    );
  }

  ChatIslandDisplayLayer _resolveChatPaneDisplayLayer({
    required bool showSurfaceSwitcher,
  }) {
    if (!showSurfaceSwitcher) {
      return _chatIslandDisplayLayer == ChatIslandDisplayLayer.tools
          ? ChatIslandDisplayLayer.tools
          : ChatIslandDisplayLayer.model;
    }
    return _activeSurfaceMode == ChatSurfaceMode.normal
        ? _chatIslandDisplayLayer
        : ChatIslandDisplayLayer.mode;
  }

  Widget _buildPaneSurface({
    required Widget child,
    required bool translucent,
    required AppBackgroundVisualProfile visualProfile,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundSurfaceColor(
          translucent: translucent,
          opacity: translucent ? 0.72 : 1,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: translucent
              ? visualProfile.islandBorderColor
              : const Color(0xFFD9E6FB),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121A2433),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(24), child: child),
    );
  }

  Widget _buildChatPaneShell({
    required BuildContext layoutContext,
    required BoxConstraints constraints,
    required AppBackgroundConfig backgroundConfig,
    required AppBackgroundVisualProfile visualProfile,
    required bool backgroundActive,
    required double inputBottomPadding,
    required double keyboardSpacer,
    required double commandPanelBottomOffset,
    required Widget conversationBody,
    required bool hideWorkspaceOverlays,
    required bool showMenuButton,
    required bool showSurfaceSwitcher,
    required VoidCallback onMenuTap,
  }) {
    final toolActivityCards = extractAgentToolCards(_messages);
    final toolActivityCanExpand = toolActivityCards.length > 1;
    final toolActivityAnchor = toolActivityCards.isEmpty
        ? null
        : _resolveToolActivityAnchorGeometry(
            layoutContext: layoutContext,
            constraints: constraints,
            inputBottomPadding: inputBottomPadding,
            keyboardSpacer: keyboardSpacer,
            inputAreaHeight: _inputAreaHeight,
          );
    if (toolActivityCards.isEmpty && _toolActivityOccupiedHeight > 0) {
      _scheduleToolActivityInsetSync(0);
    }
    if (!toolActivityCanExpand && _isToolActivityExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setToolActivityExpanded(false);
      });
    }
    final showAppUpdateIndicator =
        !hideWorkspaceOverlays &&
        AppUpdateService.shouldShowBanner(_appUpdateStatus);
    final appUpdateTooltip = _appUpdateStatus == null
        ? '发现新版本'
        : '发现新版本 ${_appUpdateStatus!.latestVersionLabel}';
    final appBarMode = showSurfaceSwitcher
        ? _activeSurfaceMode
        : ChatSurfaceMode.normal;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Column(
          children: [
            ChatAppBar(
              onMenuTap: onMenuTap,
              onCompanionTap: () {
                unawaited(_toggleCompanionMode());
              },
              activeMode: appBarMode,
              onModeChanged: (value) {
                unawaited(_switchChatMode(value, syncPage: true));
              },
              activeModelId: appBarMode == ChatSurfaceMode.normal
                  ? _activeNormalChatModelId
                  : null,
              onModelTap: appBarMode == ChatSurfaceMode.normal
                  ? (anchorContext) {
                      unawaited(_openConversationModelSelector(anchorContext));
                    }
                  : null,
              displayLayer: _resolveChatPaneDisplayLayer(
                showSurfaceSwitcher: showSurfaceSwitcher,
              ),
              onInteracted: _cancelNormalSurfaceModelReveal,
              onDisplayLayerChanged: _handleChatIslandDisplayLayerChanged,
              onTerminalEnvironmentTap: (anchorContext) {
                unawaited(_openTerminalEnvironmentEditor(anchorContext));
              },
              onTerminalTap: _handleTerminalToolTap,
              onBrowserTap: _handleBrowserToolTap,
              hasTerminalEnvironment: _terminalEnvironmentVariables.isNotEmpty,
              isBrowserEnabled: _isBrowserSessionAvailable,
              activeToolType: _lastAgentToolType,
              isCompanionModeEnabled: _isCompanionModeEnabled,
              isCompanionToggleLoading: _isCompanionToggleLoading,
              showAppUpdateIndicator: showAppUpdateIndicator,
              appUpdateTooltip: appUpdateTooltip,
              onAppUpdateTap: showAppUpdateIndicator
                  ? () {
                      unawaited(_handleAppUpdateBannerTap());
                    }
                  : null,
              translucent: backgroundActive,
              visualProfile: visualProfile,
              showMenuButton: showMenuButton,
              showSurfaceSwitcher: showSurfaceSwitcher,
            ),
            if (_isCompanionModeEnabled && _showCompanionCountdown)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '$_companionCountdown秒后自动回到桌面',
                  style: TextStyle(
                    fontSize: 12,
                    color: visualProfile.secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Expanded(child: conversationBody),
            if (_vlmInfoQuestion != null)
              _buildNormalSurfaceTransition(
                viewportWidth: constraints.maxWidth,
                child: VlmInfoPrompt(
                  question: _vlmInfoQuestion!,
                  controller: _vlmAnswerController,
                  isSubmitting: _isSubmittingVlmReply,
                  onSubmit: onSubmitVlmInfo,
                  onDismiss: dismissVlmInfo,
                ),
              ),
            if (_isInputAreaVisible)
              _buildNormalSurfaceTransition(
                viewportWidth: constraints.maxWidth,
                child: Container(
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
                        ? _activeConversationModelOverrideSelection?.modelId
                        : null,
                    contextUsageRatio: _activeMode == ChatPageMode.normal
                        ? _currentConversation?.contextUsageRatio
                        : null,
                    contextUsageTooltipMessage:
                        _activeMode == ChatPageMode.normal
                        ? _buildContextUsageTooltipMessage()
                        : null,
                    onLongPressContextUsageRing:
                        _activeMode == ChatPageMode.normal
                        ? _handleContextUsageRingLongPress
                        : null,
                    onInputHeightChanged: _handleInputAreaHeightChanged,
                    onClearSelectedModelOverride:
                        _activeMode == ChatPageMode.normal &&
                            _activeConversationModelOverrideSelection != null
                        ? () {
                            unawaited(_clearConversationModelOverride());
                          }
                        : null,
                    translucent: backgroundActive,
                  ),
                ),
              ),
            SizedBox(height: inputBottomPadding + keyboardSpacer),
          ],
        ),
        if (!hideWorkspaceOverlays &&
            toolActivityCanExpand &&
            _isToolActivityExpanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _setToolActivityExpanded(false),
            ),
          ),
        if (_isInputAreaVisible && toolActivityCards.isNotEmpty)
          Positioned(
            left: toolActivityAnchor?.rect.left ?? 24,
            width:
                toolActivityAnchor?.rect.width ??
                math.max(0.0, constraints.maxWidth - 48),
            bottom: toolActivityAnchor?.bottom ?? 0,
            child: _buildNormalSurfaceTransition(
              viewportWidth: constraints.maxWidth,
              child: ChatToolActivityStrip(
                messages: _messages,
                anchorRect: toolActivityAnchor?.rect,
                onOccupiedHeightChanged: _scheduleToolActivityInsetSync,
                expanded: _isToolActivityExpanded,
                onExpandedChanged: _setToolActivityExpanded,
              ),
            ),
          ),
        if (_showModelMentionPanel ||
            _showSlashCommandPanel ||
            _openClawPanelExpanded ||
            _isOpenClawSurface)
          Positioned(
            left: 24,
            right: 24,
            bottom: commandPanelBottomOffset,
            child: _buildNormalSurfaceTransition(
              viewportWidth: constraints.maxWidth,
              child: _buildSlashCommandPanel(),
            ),
          ),
        if (_isContextCompressing)
          Positioned.fill(
            child: _buildNormalSurfaceTransition(
              viewportWidth: constraints.maxWidth,
              child: _buildContextCompressingHint(),
            ),
          ),
        if (_isPopupVisible)
          Positioned(
            right: 24,
            bottom: _popupMenuBottomOffset(),
            child: _buildNormalSurfaceTransition(
              viewportWidth: constraints.maxWidth,
              child:
                  _chatInputAreaKey.currentState?.buildPopupMenu() ??
                  const SizedBox.shrink(),
            ),
          ),
        _buildBrowserOverlay(constraints),
      ],
    );
  }

  Widget _buildHdPadWorkspacePane({
    required bool backgroundActive,
    required AppBackgroundVisualProfile visualProfile,
  }) {
    final workspacePathsFuture = _workspacePathsLoadFuture ??=
        OmnibotResourceService.ensureWorkspacePathsLoaded();
    return FutureBuilder<OmnibotWorkspacePaths>(
      future: workspacePathsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final paths =
            snapshot.data ??
            const OmnibotWorkspacePaths(
              rootPath: '/data/user/0/cn.com.omnimind.bot/workspace',
              shellRootPath: '/workspace',
              internalRootPath:
                  '/data/user/0/cn.com.omnimind.bot/workspace/.omnibot',
            );
        return OmnibotWorkspaceBrowser(
          key: _hdPadWorkspaceBrowserKey,
          workspacePath: paths.rootPath,
          workspaceShellPath: paths.shellRootPath,
          enableSystemBackHandler: false,
          translucentSurfaces: backgroundActive,
          showBreadcrumbHeader: true,
          showHeaderTitle: false,
          enableInlineDirectoryExpansion: false,
          inlineFilePreview: true,
          onCanGoUpChanged: (canGoUp) {
            if (_workspaceBrowserCanGoUp == canGoUp || !mounted) return;
            setState(() {
              _workspaceBrowserCanGoUp = canGoUp;
            });
          },
        );
      },
    );
  }

  Widget _buildHdPadLandscapeShell({
    required AppBackgroundConfig backgroundConfig,
    required AppBackgroundVisualProfile visualProfile,
    required bool backgroundActive,
    required double inputBottomPadding,
    required double keyboardSpacer,
    required double commandPanelBottomOffset,
  }) {
    const shellPadding = EdgeInsets.fromLTRB(8, 10, 8, 10);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math
            .max(0, constraints.maxWidth - shellPadding.horizontal)
            .toDouble();
        final expandedLayout = _hdPadPaneLayoutResolver.resolve(
          availableWidth,
          preferredLeftWidth: _hdPadLeftPaneWidth,
          preferredRightWidth: _hdPadRightPaneWidth,
        );
        final layout = _hdPadPaneLayoutResolver.resolve(
          availableWidth,
          preferredLeftWidth: _hdPadLeftPaneWidth,
          preferredRightWidth: _hdPadRightPaneWidth,
          collapseLeftPane: _hdPadLeftPaneCollapsed,
        );
        final paneDuration = _isHdPadPaneDragging
            ? Duration.zero
            : const Duration(milliseconds: 280);
        const paneCurve = Curves.easeInOutCubic;
        return Padding(
          padding: shellPadding,
          child: Row(
            children: [
              AnimatedContainer(
                duration: paneDuration,
                curve: paneCurve,
                width: layout.leftWidth,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: expandedLayout.leftWidth,
                    maxWidth: expandedLayout.leftWidth,
                    child: SizedBox(
                      width: expandedLayout.leftWidth,
                      child: IgnorePointer(
                        ignoring: _hdPadLeftPaneCollapsed,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeInOutCubic,
                          offset: _hdPadLeftPaneCollapsed
                              ? const Offset(-0.08, 0)
                              : Offset.zero,
                          child: _buildPaneSurface(
                            translucent: backgroundActive,
                            visualProfile: visualProfile,
                            child: HomeDrawer(
                              key: _drawerKey,
                              embedded: true,
                              closeOnNavigate: false,
                              newConversationMode: _conversationModeForPageMode(
                                _activeMode,
                              ),
                              onThreadTargetSelected:
                                  _handleEmbeddedDrawerThreadTargetSelected,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: paneDuration,
                curve: paneCurve,
                width: _hdPadLeftPaneCollapsed
                    ? 0
                    : HdPadPaneLayoutResolver.dividerHitWidth,
                child: _hdPadLeftPaneCollapsed
                    ? const SizedBox.shrink()
                    : _PaneResizeHandle(
                        onDragStart: () {
                          setState(() => _isHdPadPaneDragging = true);
                        },
                        onDragUpdate: (delta) {
                          setState(() {
                            _hdPadLeftPaneWidth = layout.leftWidth + delta;
                          });
                        },
                        onDragEnd: () {
                          setState(() => _isHdPadPaneDragging = false);
                          _persistHdPadPanePreferences();
                        },
                      ),
              ),
              AnimatedContainer(
                duration: paneDuration,
                curve: paneCurve,
                width: layout.centerWidth,
                child: _buildPaneSurface(
                  translucent: backgroundActive,
                  visualProfile: visualProfile,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _handlePagePointerDown,
                    onPointerMove: _handlePagePointerMove,
                    onPointerUp: _handlePagePointerUp,
                    onPointerCancel: _handlePagePointerCancel,
                    child: LayoutBuilder(
                      builder: (context, paneConstraints) {
                        return _buildChatPaneShell(
                          layoutContext: context,
                          constraints: paneConstraints,
                          backgroundConfig: backgroundConfig,
                          visualProfile: visualProfile,
                          backgroundActive: backgroundActive,
                          inputBottomPadding: inputBottomPadding,
                          keyboardSpacer: keyboardSpacer,
                          commandPanelBottomOffset: commandPanelBottomOffset,
                          conversationBody: _buildModeMessagePage(
                            ChatPageMode.normal,
                            backgroundConfig,
                            visualProfile,
                          ),
                          hideWorkspaceOverlays: false,
                          showMenuButton: true,
                          showSurfaceSwitcher: false,
                          onMenuTap: _toggleHdPadLeftPaneCollapsed,
                        );
                      },
                    ),
                  ),
                ),
              ),
              _PaneResizeHandle(
                onDragStart: () {
                  setState(() => _isHdPadPaneDragging = true);
                },
                onDragUpdate: (delta) {
                  setState(() {
                    _hdPadRightPaneWidth = layout.rightWidth - delta;
                  });
                },
                onDragEnd: () {
                  setState(() => _isHdPadPaneDragging = false);
                  _persistHdPadPanePreferences();
                },
              ),
              AnimatedContainer(
                duration: paneDuration,
                curve: paneCurve,
                width: layout.rightWidth,
                child: _buildPaneSurface(
                  translucent: backgroundActive,
                  visualProfile: visualProfile,
                  child: _buildHdPadWorkspacePane(
                    backgroundActive: backgroundActive,
                    visualProfile: visualProfile,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const edgeInset = 24.0;
    final mediaQuery = MediaQuery.of(context);
    final isHdPadLandscape = _isHdPadLandscapeForMediaQuery(mediaQuery);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final viewPaddingBottom = mediaQuery.viewPadding.bottom;
    final shouldLiftComposerForKeyboard = _inputFocusNode.hasFocus;
    final composerKeyboardLift = shouldLiftComposerForKeyboard
        ? bottomInset
        : 0.0;
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

    return ValueListenableBuilder<AppBackgroundConfig>(
      valueListenable: AppBackgroundService.notifier,
      builder: (context, backgroundConfig, _) {
        final backgroundActive = backgroundConfig.isActive;
        return ValueListenableBuilder<AppBackgroundVisualProfile>(
          valueListenable: AppBackgroundService.visualProfileNotifier,
          builder: (context, visualProfile, _) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (isHdPadLandscape && _workspaceBrowserCanGoUp) {
                  _hdPadWorkspaceBrowserKey.currentState?.openParentDirectory();
                  return;
                }
                if (_isWorkspaceSurface && _workspaceBrowserCanGoUp) {
                  return;
                }
                unawaited(saveConversationWithSummary());
                if (GoRouterManager.canPop()) {
                  GoRouterManager.pop();
                  return;
                }
                unawaited(AppStateService.exitApp());
              },
              child: Scaffold(
                key: _scaffoldKey,
                backgroundColor: Colors.transparent,
                resizeToAvoidBottomInset: false,
                drawer: isHdPadLandscape
                    ? null
                    : HomeDrawer(
                        key: _drawerKey,
                        newConversationMode: _conversationModeForPageMode(
                          _activeMode,
                        ),
                      ),
                onDrawerChanged: (isOpen) {
                  if (isHdPadLandscape) {
                    return;
                  }
                  if (isOpen) {
                    _drawerKey.currentState?.reloadConversations();
                  } else {
                    checkAndHandleDeletedConversation();
                  }
                },
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: AppBackgroundLayer(
                        config: backgroundConfig,
                        fallbackColor: const Color(0xFFF9FCFF),
                        layerKey: const ValueKey('chat-page-background'),
                      ),
                    ),
                    SafeArea(
                      child: ClipRect(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) {
                            _interruptCompanionAutoHomeIfNeeded();
                            unawaited(_handleOutsideTap(event.position));
                            if (!isHdPadLandscape) {
                              _handlePagePointerDown(event);
                            }
                          },
                          onPointerMove: isHdPadLandscape
                              ? null
                              : _handlePagePointerMove,
                          onPointerUp: isHdPadLandscape
                              ? null
                              : _handlePagePointerUp,
                          onPointerCancel: isHdPadLandscape
                              ? null
                              : _handlePagePointerCancel,
                          child: isHdPadLandscape
                              ? _buildHdPadLandscapeShell(
                                  backgroundConfig: backgroundConfig,
                                  visualProfile: visualProfile,
                                  backgroundActive: backgroundActive,
                                  inputBottomPadding: inputBottomPadding,
                                  keyboardSpacer: keyboardSpacer,
                                  commandPanelBottomOffset:
                                      commandPanelBottomOffset,
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    return _buildChatPaneShell(
                                      layoutContext: context,
                                      constraints: constraints,
                                      backgroundConfig: backgroundConfig,
                                      visualProfile: visualProfile,
                                      backgroundActive: backgroundActive,
                                      inputBottomPadding: inputBottomPadding,
                                      keyboardSpacer: keyboardSpacer,
                                      commandPanelBottomOffset:
                                          commandPanelBottomOffset,
                                      conversationBody: ClipRect(
                                        child:
                                            NotificationListener<
                                              ScrollNotification
                                            >(
                                              onNotification:
                                                  _handleModePageScrollNotification,
                                              child: PageView(
                                                controller: _modePageController,
                                                onPageChanged:
                                                    _handleModePageChanged,
                                                children: [
                                                  _buildModeMessagePage(
                                                    ChatPageMode.normal,
                                                    backgroundConfig,
                                                    visualProfile,
                                                  ),
                                                  _buildWorkspaceSurfacePage(),
                                                ],
                                              ),
                                            ),
                                      ),
                                      hideWorkspaceOverlays:
                                          _isWorkspaceSurface,
                                      showMenuButton: true,
                                      showSurfaceSwitcher: true,
                                      onMenuTap: () => _scaffoldKey.currentState
                                          ?.openDrawer(),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String? _buildContextUsageTooltipMessage() {
    final conversation = _currentConversation;
    if (conversation == null) {
      return null;
    }
    if (conversation.promptTokenThreshold <= 0) {
      return '当前对话还没有可用的上下文阈值';
    }
    if (conversation.latestPromptTokensUpdatedAt <= 0 &&
        conversation.latestPromptTokens <= 0) {
      return '当前对话还没有上下文 token 统计\n长按可调整阈值';
    }

    final usedTokens = conversation.latestPromptTokens;
    final thresholdTokens = conversation.promptTokenThreshold;
    return '${_formatTokenCount(usedTokens)} / '
        '${_formatTokenCount(thresholdTokens)} tokens'
        '\n长按可调整阈值';
  }

  Future<void> _handleContextUsageRingLongPress() async {
    final conversation = _currentConversation;
    if (conversation == null || conversation.id <= 0) {
      _showSnackBar('当前对话还没有可调整的上下文阈值');
      return;
    }

    final nextThreshold = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextThresholdSheet(
        initialThreshold: conversation.promptTokenThreshold,
        currentUsageTokens: conversation.latestPromptTokens,
      ),
    );
    if (!mounted || nextThreshold == null) return;
    if (nextThreshold == conversation.promptTokenThreshold) return;

    final success =
        await ConversationService.updateConversationPromptTokenThreshold(
          conversationId: conversation.id,
          promptTokenThreshold: nextThreshold,
        );
    if (!mounted) return;
    if (!success) {
      _showSnackBar('更新压缩阈值失败');
      return;
    }

    final updatedConversation = conversation.copyWith(
      promptTokenThreshold: nextThreshold,
    );
    setState(() {
      _currentConversationByMode[ChatPageMode.normal] = updatedConversation;
      if (_activeMode == ChatPageMode.normal) {
        _currentConversation = updatedConversation;
      }
    });
    _syncRuntimeSnapshotForMode(
      ChatPageMode.normal,
      conversation: updatedConversation,
    );
    _showSnackBar('压缩阈值已更新为 ${_formatThresholdLabel(nextThreshold)}');
  }

  Future<void> _handleUserMessageLongPressStart(
    ChatMessageModel message,
    LongPressStartDetails details,
  ) async {
    final text = (message.text ?? '').trim();
    final hasAttachments = _extractRetryAttachments(message).isNotEmpty;
    if (text.isEmpty && !hasAttachments) {
      showToast('这条用户消息没有可操作的文本', type: ToastType.warning);
      return;
    }

    final action = await _showUserMessageQuickMenu(
      details.globalPosition,
      showRetryAction: _canRetryUserMessage(message),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _UserMessageQuickAction.copy:
        if (text.isEmpty) {
          showToast('这条用户消息没有可复制的文本', type: ToastType.warning);
          return;
        }
        await _copyUserMessageText(text);
        return;
      case _UserMessageQuickAction.retry:
        await _retryUserMessage(message);
        return;
    }
  }

  Future<_UserMessageQuickAction?> _showUserMessageQuickMenu(
    Offset globalPosition, {
    required bool showRetryAction,
  }) {
    final estimatedMenuHeight = showRetryAction ? 116.0 : 60.0;
    final position = PopupMenuAnchorPosition.fromGlobalOffset(
      context: context,
      globalOffset: globalPosition,
      estimatedMenuHeight: estimatedMenuHeight,
      verticalGap: 10,
      reservedBottom: MediaQuery.of(context).viewInsets.bottom,
    );
    return showMenu<_UserMessageQuickAction>(
      context: context,
      position: position,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      menuPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 188, maxWidth: 188),
      items: [
        _UserMessageQuickMenuEntry(
          width: 188,
          estimatedHeight: estimatedMenuHeight,
          showRetryAction: showRetryAction,
        ),
      ],
    );
  }

  bool _canRetryUserMessage(ChatMessageModel message) {
    if (message.user != 1) return false;
    for (final item in _messages) {
      if (item.user != 1) continue;
      return item.id == message.id;
    }
    return false;
  }

  int _retryMessageRoundLength(ChatMessageModel message) {
    if (!_canRetryUserMessage(message)) return 0;
    final targetIndex = _messages.indexWhere((item) => item.id == message.id);
    if (targetIndex == -1) return 0;
    return targetIndex + 1;
  }

  Future<void> _clearRetriedMessageRound(ChatMessageModel message) async {
    if (_isAiResponding) {
      _onCancelTask();
      if (!mounted) return;
    }

    final removeCount = _retryMessageRoundLength(message);
    if (removeCount <= 0) return;

    setState(() {
      _messages.removeRange(0, removeCount);
    });

    final conversationId = _currentConversationId;
    if (conversationId == null) return;

    await ConversationHistoryService.saveConversationMessages(
      conversationId,
      List<ChatMessageModel>.from(_messages),
      mode: activeConversationModeValue,
    );
  }

  Future<void> _copyUserMessageText(String text) async {
    final success = await AssistsMessageService.copyToClipboard(text);
    if (!mounted) return;
    showToast(
      success ? '已复制消息内容' : '复制失败',
      type: success ? ToastType.success : ToastType.error,
    );
  }

  Future<void> _retryUserMessage(ChatMessageModel message) async {
    final text = (message.text ?? '').trim();
    final attachments = _extractRetryAttachments(message);
    if (text.isEmpty && attachments.isEmpty) {
      showToast('这条用户消息没有可重试的内容', type: ToastType.warning);
      return;
    }
    if (!_canRetryUserMessage(message)) {
      showToast('只有最新一条用户消息支持重试', type: ToastType.warning);
      return;
    }

    if (text.isNotEmpty) {
      await AssistsMessageService.copyToClipboard(text);
      if (!mounted) return;
    }

    await _clearRetriedMessageRound(message);
    if (!mounted) return;

    await _retryUserMessageText(text, attachments: attachments);
    if (!mounted) return;
  }

  List<Map<String, dynamic>> _extractRetryAttachments(
    ChatMessageModel message,
  ) {
    final raw = message.content?['attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  String _formatThresholdLabel(int threshold) {
    if (threshold >= 1000) {
      final kilo = threshold / 1000;
      final normalized = kilo % 1 == 0
          ? kilo.toStringAsFixed(0)
          : kilo.toStringAsFixed(1);
      return '${normalized}k';
    }
    return threshold.toString();
  }

  String _formatTokenCount(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}

class _UserMessageQuickMenuEntry
    extends PopupMenuEntry<_UserMessageQuickAction> {
  const _UserMessageQuickMenuEntry({
    required this.width,
    required this.estimatedHeight,
    required this.showRetryAction,
  });

  final double width;
  final double estimatedHeight;
  final bool showRetryAction;

  @override
  double get height => estimatedHeight;

  @override
  bool represents(_UserMessageQuickAction? value) => false;

  @override
  State<_UserMessageQuickMenuEntry> createState() =>
      _UserMessageQuickMenuEntryState();
}

class _UserMessageQuickMenuEntryState
    extends State<_UserMessageQuickMenuEntry> {
  void _select(_UserMessageQuickAction action) {
    Navigator.of(context).pop(action);
  }

  Widget _buildAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x14000000), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAction(
                icon: Icons.content_copy_rounded,
                label: '复制',
                onTap: () => _select(_UserMessageQuickAction.copy),
              ),
              if (widget.showRetryAction) ...[
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x14000000),
                ),
                _buildAction(
                  icon: Icons.refresh_rounded,
                  label: '重试这条消息',
                  onTap: () => _select(_UserMessageQuickAction.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneResizeHandle extends StatelessWidget {
  const _PaneResizeHandle({
    required this.onDragUpdate,
    this.onDragStart,
    this.onDragEnd,
  });

  final ValueChanged<double> onDragUpdate;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => onDragStart?.call(),
      onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd?.call(),
      onHorizontalDragCancel: () => onDragEnd?.call(),
      child: const SizedBox(
        width: HdPadPaneLayoutResolver.dividerHitWidth,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFD7E5FB),
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            child: SizedBox(width: 3, height: 52),
          ),
        ),
      ),
    );
  }
}

class _ContextThresholdSheet extends StatefulWidget {
  const _ContextThresholdSheet({
    required this.initialThreshold,
    required this.currentUsageTokens,
  });

  final int initialThreshold;
  final int currentUsageTokens;

  @override
  State<_ContextThresholdSheet> createState() => _ContextThresholdSheetState();
}

class _ContextThresholdSheetState extends State<_ContextThresholdSheet> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;
  late double _draftThreshold;

  static const List<int> _presets = <int>[32000, 64000, 128000, 256000, 512000];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialThreshold.toString(),
    );
    _draftThreshold = widget.initialThreshold.toDouble();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close([int? value]) {
    _focusNode.unfocus();
    Navigator.of(context).pop(value);
  }

  void _updateDraftThreshold(double value, {bool updateText = true}) {
    final normalized = value.round().clamp(
      _kMinContextTokenThreshold,
      _kMaxContextTokenThreshold,
    );
    setState(() {
      _draftThreshold = normalized.toDouble();
      if (updateText) {
        final text = normalized.toString();
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      _errorText = null;
    });
  }

  int? _parseInput() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _errorText = '请输入阈值';
      });
      return null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      setState(() {
        _errorText = '阈值必须是整数';
      });
      return null;
    }
    if (parsed < _kMinContextTokenThreshold ||
        parsed > _kMaxContextTokenThreshold) {
      setState(() {
        _errorText =
            '阈值范围为 $_kMinContextTokenThreshold 到 $_kMaxContextTokenThreshold';
      });
      return null;
    }
    setState(() {
      _errorText = null;
      _draftThreshold = parsed.toDouble();
    });
    return parsed;
  }

  String _formatThresholdLabel(int threshold) {
    if (threshold >= 1000) {
      final kilo = threshold / 1000;
      return kilo % 1 == 0
          ? '${kilo.toStringAsFixed(0)}k'
          : '${kilo.toStringAsFixed(1)}k';
    }
    return threshold.toString();
  }

  String _formatTokenCount(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  String _formatUsagePercent(double ratio) {
    if (!ratio.isFinite) {
      return '0%';
    }
    final percent = ratio * 100;
    final rounded = percent >= 100 || percent % 1 == 0
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(1);
    return '$rounded%';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final draftThreshold = _draftThreshold.round();
    final usageRatio = widget.currentUsageTokens <= 0
        ? 0.0
        : widget.currentUsageTokens / draftThreshold;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A16304A),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6E0F5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '调整上下文阈值',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF172033),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEDF4FF), Color(0xFFF6F9FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD9E6FB)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ThresholdMetric(
                        label: '当前上下文',
                        value: _formatTokenCount(widget.currentUsageTokens),
                        accent: const Color(0xFF5A8DDE),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 38,
                      color: const Color(0xFFD9E6FB),
                    ),
                    Expanded(
                      child: _ThresholdMetric(
                        label: '目标阈值',
                        value: _formatTokenCount(draftThreshold),
                        accent: const Color(0xFF1930D9),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 38,
                      color: const Color(0xFFD9E6FB),
                    ),
                    Expanded(
                      child: _ThresholdMetric(
                        label: '占用比例',
                        value: _formatUsagePercent(usageRatio),
                        accent: usageRatio >= 1
                            ? const Color(0xFFD65A3A)
                            : const Color(0xFF2F8F6B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF2B63F6),
                  inactiveTrackColor: const Color(0xFFD8E3FB),
                  thumbColor: Colors.white,
                  overlayColor: const Color(0x1A2B63F6),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 11,
                  ),
                  trackHeight: 5,
                ),
                child: Slider(
                  min: _kMinContextTokenThreshold.toDouble(),
                  max: _kMaxContextTokenThreshold.toDouble(),
                  divisions:
                      (_kMaxContextTokenThreshold -
                          _kMinContextTokenThreshold) ~/
                      1000,
                  value: _draftThreshold.clamp(
                    _kMinContextTokenThreshold.toDouble(),
                    _kMaxContextTokenThreshold.toDouble(),
                  ),
                  onChanged: (value) => _updateDraftThreshold(value),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets.map((preset) {
                  final selected = draftThreshold == preset;
                  return GestureDetector(
                    onTap: () => _updateDraftThreshold(preset.toDouble()),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF1F56F0)
                            : const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF1F56F0)
                              : const Color(0xFFD9E6FB),
                        ),
                      ),
                      child: Text(
                        _formatThresholdLabel(preset),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF54627A),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '精确阈值',
                  hintText: _kDefaultContextTokenThreshold.toString(),
                  helperText:
                      '默认 $_kDefaultContextTokenThreshold，范围 $_kMinContextTokenThreshold - $_kMaxContextTokenThreshold',
                  errorText: _errorText,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFD9E6FB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFD9E6FB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Color(0xFF2B63F6),
                      width: 1.4,
                    ),
                  ),
                ),
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() {
                      _errorText = null;
                    });
                  }
                  final parsed = int.tryParse(_controller.text.trim());
                  if (parsed != null &&
                      parsed >= _kMinContextTokenThreshold &&
                      parsed <= _kMaxContextTokenThreshold) {
                    setState(() {
                      _draftThreshold = parsed.toDouble();
                    });
                  }
                },
                onSubmitted: (_) {
                  final parsed = _parseInput();
                  if (parsed != null) {
                    _close(parsed);
                  }
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _close(_kDefaultContextTokenThreshold),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Color(0xFFD9E6FB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final parsed = _parseInput();
                        if (parsed != null) {
                          _close(parsed);
                        }
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: const Color(0xFF1F56F0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('保存阈值'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThresholdMetric extends StatelessWidget {
  const _ThresholdMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7891),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
