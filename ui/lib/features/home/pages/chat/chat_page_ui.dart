part of 'chat_page.dart';

const int _kDefaultContextTokenThreshold = 128000;
const int _kMinContextTokenThreshold = 10000;
const int _kMaxContextTokenThreshold = 512000;

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
      onBeforeTaskExecute: handleBeforeTaskExecute,
      onCancelTask: _onCancelTaskFromCard,
      onRequestAuthorize: mode == ChatPageMode.normal
          ? _requestAuthorizeForExecution
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
                  final newConversationPullIndicatorTopOffset =
                      _resolveNewConversationPullIndicatorTop(
                        layoutContext: context,
                        constraints: constraints,
                        inputBottomPadding: inputBottomPadding,
                        keyboardSpacer: keyboardSpacer,
                      );
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
                                onTapContextUsageRing:
                                    _activeMode == ChatPageMode.normal
                                    ? _handleContextUsageRingTap
                                    : null,
                                onLongPressContextUsageRing:
                                    _activeMode == ChatPageMode.normal
                                    ? _handleContextUsageRingLongPress
                                    : null,
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
                      if (!_isWorkspaceSurface &&
                          _showNewConversationPullIndicator)
                        _buildNewConversationPullIndicator(
                          newConversationPullIndicatorTopOffset,
                        ),
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

  void _handleContextUsageRingTap() {
    final conversation = _currentConversation;
    if (conversation == null) {
      return;
    }
    if (conversation.promptTokenThreshold <= 0) {
      _showSnackBar('当前对话还没有可用的上下文阈值');
      return;
    }
    if (conversation.latestPromptTokensUpdatedAt <= 0 &&
        conversation.latestPromptTokens <= 0) {
      _showSnackBar('当前对话还没有上下文 token 统计');
      return;
    }

    final usedTokens = conversation.latestPromptTokens;
    final thresholdTokens = conversation.promptTokenThreshold;
    final usageRatio = usedTokens / thresholdTokens;
    _showSnackBar(
      '上下文已用 ${_formatTokenCount(usedTokens)} / '
      '${_formatTokenCount(thresholdTokens)} tokens '
      '(${_formatUsagePercent(usageRatio)})',
    );
  }

  Future<void> _handleContextUsageRingLongPress() async {
    final conversation = _currentConversation;
    if (conversation == null || conversation.id <= 0) {
      _showSnackBar('当前对话还没有可调整的上下文阈值');
      return;
    }

    final nextThreshold = await showDialog<int>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _ContextThresholdDialog(
        initialThreshold: conversation.promptTokenThreshold,
      ),
    );
    if (!mounted || nextThreshold == null) return;
    if (nextThreshold == conversation.promptTokenThreshold) return;

    final success = await ConversationService.updateConversationPromptTokenThreshold(
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

class _ContextThresholdDialog extends StatefulWidget {
  const _ContextThresholdDialog({required this.initialThreshold});

  final int initialThreshold;

  @override
  State<_ContextThresholdDialog> createState() => _ContextThresholdDialogState();
}

class _ContextThresholdDialogState extends State<_ContextThresholdDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialThreshold.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
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
    });
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _close();
      },
      child: AlertDialog(
        title: const Text('自定义压缩阈值'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '长按圆环可调整当前对话的上下文压缩阈值。',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF54627A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Prompt token 阈值',
                hintText: _kDefaultContextTokenThreshold.toString(),
                helperText:
                    '默认 $_kDefaultContextTokenThreshold，范围 $_kMinContextTokenThreshold - $_kMaxContextTokenThreshold',
                errorText: _errorText,
              ),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() {
                    _errorText = null;
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _close(_kDefaultContextTokenThreshold),
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => _close(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final parsed = _parseInput();
              if (parsed != null) {
                _close(parsed);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
