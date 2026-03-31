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
  bool get _showNewConversationPullIndicator =>
      _isNewConversationPullTracking || _newConversationPullDistance > 0;

  double _resolveNewConversationPullIndicatorTop({
    required BuildContext layoutContext,
    required BoxConstraints constraints,
    required double inputBottomPadding,
    required double keyboardSpacer,
  }) {
    final fallbackTop =
        constraints.maxHeight -
        inputBottomPadding -
        keyboardSpacer -
        (_isInputAreaVisible ? 106 : 52);
    final fallback = fallbackTop
        .clamp(8.0, constraints.maxHeight - 24)
        .toDouble();
    if (!_isInputAreaVisible) {
      return fallback;
    }
    final inputContext = _inputAreaKey.currentContext;
    final inputBox = inputContext?.findRenderObject();
    final stackBox = layoutContext.findRenderObject();
    if (inputBox is! RenderBox ||
        stackBox is! RenderBox ||
        !inputBox.hasSize ||
        !stackBox.hasSize) {
      return fallback;
    }
    final inputTop = inputBox.localToGlobal(Offset.zero, ancestor: stackBox).dy;
    return (inputTop - 30).clamp(8.0, constraints.maxHeight - 24).toDouble();
  }

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
    if (_isInputAreaVisible && normalizedInputHeight > 0.5) {
      final bottom =
          (inputBottomPadding + keyboardSpacer + normalizedInputHeight)
              .clamp(0.0, constraints.maxHeight)
              .toDouble();
      final top = (constraints.maxHeight - bottom)
          .clamp(0.0, constraints.maxHeight)
          .toDouble();
      return _ToolActivityAnchorGeometry(
        rect: Rect.fromLTWH(24, top, derivedWidth, normalizedInputHeight),
        bottom: bottom,
      );
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
    return _ToolActivityAnchorGeometry(
      rect: rect,
      bottom: (constraints.maxHeight - rect.top)
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

  Widget _buildNewConversationPullIndicator(double topOffset) {
    final progress =
        (_newConversationPullDistance /
                _ChatPageStateBase._newConversationPullThreshold)
            .clamp(0.0, 1.4)
            .toDouble();
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final isReady = _newConversationPullThresholdReached;
    final opacity = (0.10 + eased * 0.90).clamp(0.0, 1.0).toDouble();
    final offsetY = (1 - eased) * 16;
    final textColor = isReady
        ? const Color(0xFF197446)
        : Color.lerp(const Color(0xFF8FA1BC), const Color(0xFF34527A), eased)!;
    final hintText = isReady ? '松手即可新建对话' : '继续上滑新建对话';

    return Positioned(
      left: 24,
      right: 24,
      top: topOffset,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Center(
              child: Text(
                hintText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: 0.65),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
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
  Widget _buildModeMessagePage(ChatPageMode mode) {
    final runtime = _runtimeForMode(mode);
    return ChatMessageList(
      messages: runtime?.messages ?? _messagesByMode[mode]!,
      scrollController: _scrollControllerForMode(mode),
      bottomOverlayInset: mode == _activeMode && !_isWorkspaceSurface
          ? _toolActivityOccupiedHeight
          : 0,
      onBeforeTaskExecute: handleBeforeTaskExecute,
      onCancelTask: _onCancelTaskFromCard,
      onRequestAuthorize: mode == ChatPageMode.normal
          ? _requestAuthorizeForExecution
          : null,
      onUserMessageLongPressStart: mode == ChatPageMode.normal
          ? _handleUserMessageLongPressStart
          : null,
    );
  }

  @override
  Widget _buildWorkspaceSurfacePage() {
    return OmnibotWorkspaceBrowser(
      key: ValueKey('workspace_surface_$_workspaceSurfaceSeed'),
      workspacePath: OmnibotResourceService.rootPath,
      workspaceShellPath: OmnibotResourceService.shellRootPath,
      onCanGoUpChanged: (canGoUp) {
        if (_workspaceBrowserCanGoUp == canGoUp || !mounted) return;
        setState(() {
          _workspaceBrowserCanGoUp = canGoUp;
        });
      },
    );
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
        backgroundColor: const Color(0xFFF9FCFF),
        resizeToAvoidBottomInset: false,
        drawer: HomeDrawer(
          key: _drawerKey,
          newConversationMode: _conversationModeForPageMode(_activeMode),
        ),
        onDrawerChanged: (isOpen) {
          if (isOpen) {
            _drawerKey.currentState?.reloadConversations();
          } else {
            checkAndHandleDeletedConversation();
          }
        },
        body: SafeArea(
          child: ClipRect(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                _handlePagePointerDown(event);
                _interruptCompanionAutoHomeIfNeeded();
                unawaited(_handleOutsideTap(event.position));
              },
              onPointerMove: _handlePagePointerMove,
              onPointerUp: _handlePagePointerUp,
              onPointerCancel: _handlePagePointerCancel,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final toolActivityCards = !_isWorkspaceSurface
                      ? extractAgentToolCards(_messages)
                      : const <Map<String, dynamic>>[];
                  final newConversationPullIndicatorTopOffset =
                      _resolveNewConversationPullIndicatorTop(
                        layoutContext: context,
                        constraints: constraints,
                        inputBottomPadding: inputBottomPadding,
                        keyboardSpacer: keyboardSpacer,
                      );
                  final toolActivityAnchor = toolActivityCards.isEmpty
                      ? null
                      : _resolveToolActivityAnchorGeometry(
                          layoutContext: context,
                          constraints: constraints,
                          inputBottomPadding: inputBottomPadding,
                          keyboardSpacer: keyboardSpacer,
                          inputAreaHeight: _inputAreaHeight,
                        );
                  if (toolActivityCards.isEmpty &&
                      _toolActivityOccupiedHeight > 0) {
                    _scheduleToolActivityInsetSync(0);
                  }
                  final showAppUpdateIndicator =
                      !_isWorkspaceSurface &&
                      AppUpdateService.shouldShowBanner(_appUpdateStatus);
                  final appUpdateTooltip = _appUpdateStatus == null
                      ? '发现新版本'
                      : '发现新版本 ${_appUpdateStatus!.latestVersionLabel}';
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Column(
                        children: [
                          ChatAppBar(
                            onMenuTap: () =>
                                _scaffoldKey.currentState?.openDrawer(),
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
                            onModelTap:
                                _activeSurfaceMode == ChatSurfaceMode.normal
                                ? (anchorContext) {
                                    unawaited(
                                      _openConversationModelSelector(
                                        anchorContext,
                                      ),
                                    );
                                  }
                                : null,
                            displayLayer:
                                _activeSurfaceMode == ChatSurfaceMode.normal
                                ? _chatIslandDisplayLayer
                                : ChatIslandDisplayLayer.mode,
                            onInteracted: _cancelNormalSurfaceModelReveal,
                            onDisplayLayerChanged:
                                _handleChatIslandDisplayLayerChanged,
                            onTerminalEnvironmentTap: (anchorContext) {
                              unawaited(
                                _openTerminalEnvironmentEditor(anchorContext),
                              );
                            },
                            onTerminalTap: _handleTerminalToolTap,
                            onBrowserTap: _handleBrowserToolTap,
                            hasTerminalEnvironment:
                                _terminalEnvironmentVariables.isNotEmpty,
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
                          ),
                          if (_isCompanionModeEnabled &&
                              _showCompanionCountdown)
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
                          Expanded(
                            child: ClipRect(
                              child: NotificationListener<ScrollNotification>(
                                onNotification:
                                    _handleModePageScrollNotification,
                                child: PageView(
                                  controller: _modePageController,
                                  onPageChanged: _handleModePageChanged,
                                  children: [
                                    _buildWorkspaceSurfacePage(),
                                    _buildModeMessagePage(ChatPageMode.normal),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!_isWorkspaceSurface && _vlmInfoQuestion != null)
                            VlmInfoPrompt(
                              question: _vlmInfoQuestion!,
                              controller: _vlmAnswerController,
                              isSubmitting: _isSubmittingVlmReply,
                              onSubmit: onSubmitVlmInfo,
                              onDismiss: dismissVlmInfo,
                            ),
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
                                onPopupVisibilityChanged:
                                    _onPopupVisibilityChanged,
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
                                contextUsageRatio:
                                    _activeMode == ChatPageMode.normal
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
                                onInputHeightChanged:
                                    _handleInputAreaHeightChanged,
                                onClearSelectedModelOverride:
                                    _activeMode == ChatPageMode.normal &&
                                        _activeConversationModelOverrideSelection !=
                                            null
                                    ? () {
                                        unawaited(
                                          _clearConversationModelOverride(),
                                        );
                                      }
                                    : null,
                              ),
                            ),
                          SizedBox(height: inputBottomPadding + keyboardSpacer),
                        ],
                      ),
                      if (!_isWorkspaceSurface &&
                          _isInputAreaVisible &&
                          toolActivityCards.isNotEmpty)
                        Positioned(
                          left: toolActivityAnchor?.rect.left ?? 24,
                          width:
                              toolActivityAnchor?.rect.width ??
                              math.max(0.0, constraints.maxWidth - 48),
                          bottom: toolActivityAnchor?.bottom ?? 0,
                          child: ChatToolActivityStrip(
                            messages: _messages,
                            anchorRect: toolActivityAnchor?.rect,
                            onOccupiedHeightChanged:
                                _scheduleToolActivityInsetSync,
                          ),
                        ),
                      if (!_isWorkspaceSurface)
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: commandPanelBottomOffset,
                          child: _buildSlashCommandPanel(),
                        ),
                      if (!_isWorkspaceSurface &&
                          _showNewConversationPullIndicator)
                        _buildNewConversationPullIndicator(
                          newConversationPullIndicatorTopOffset,
                        ),
                      if (!_isWorkspaceSurface && _isContextCompressing)
                        Positioned.fill(child: _buildContextCompressingHint()),
                      if (_isPopupVisible && !_isWorkspaceSurface)
                        Positioned(
                          right: 24,
                          bottom: _popupMenuBottomOffset(),
                          child:
                              _chatInputAreaKey.currentState
                                  ?.buildPopupMenu() ??
                              const SizedBox.shrink(),
                        ),
                      _buildBrowserOverlay(constraints),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
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
    final usageRatio = usedTokens / thresholdTokens;
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
    if (text.isEmpty) {
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
    if (text.isEmpty) {
      showToast('这条用户消息没有可重试的文本', type: ToastType.warning);
      return;
    }
    if (!_canRetryUserMessage(message)) {
      showToast('只有最新一条用户消息支持重试', type: ToastType.warning);
      return;
    }

    final copied = await AssistsMessageService.copyToClipboard(text);
    if (!mounted) return;

    await _clearRetriedMessageRound(message);
    if (!mounted) return;

    await _retryUserMessageText(text);
    if (!mounted) return;
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
