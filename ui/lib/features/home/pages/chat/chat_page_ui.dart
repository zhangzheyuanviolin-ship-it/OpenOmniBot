part of 'chat_page.dart';

mixin _ChatPageUiMixin on _ChatPageStateBase {
  @override
  Widget _buildSlashCommandPanel() {
    final visible =
        _showSlashCommandPanel ||
        _showModelMentionPanel ||
        (_isOpenClawSurface &&
            (_openClawPanelExpanded || _openClawDeployPanelExpanded));
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
              child: _openClawDeployPanelExpanded
                  ? _buildOpenClawDeployPanel()
                  : _openClawPanelExpanded
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
                  : Column(
                      children: [
                        _buildOpenClawCommandRow(
                          icon: Icons.cloud_download_rounded,
                          iconColor: const Color(0xFF0F9D7A),
                          title: '/deploy',
                          subtitle: '一键部署到内嵌 Ubuntu 并自动接入当前模式',
                          onTap: () {
                            unawaited(_showOpenClawDeployPanel());
                          },
                        ),
                        const SizedBox(height: 8),
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
                            onDisplayLayerChanged:
                                _handleChatIslandDisplayLayerChanged,
                            onTerminalTap: _handleTerminalToolTap,
                            onBrowserTap: _handleBrowserToolTap,
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
}
