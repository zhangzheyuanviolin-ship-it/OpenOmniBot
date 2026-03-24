part of 'chat_page.dart';

mixin _ChatPageModelContextMixin on _ChatPageStateBase {
  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
  ModelProviderProfileSummary? _findProviderProfile(String profileId) {
    for (final profile in _modelProviderProfiles) {
      if (profile.id == profileId) {
        return profile;
      }
    }
    return null;
  }

  @override
  List<ProviderModelOption> get _filteredQuickModelPickerModels {
    final query = _quickModelPickerSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _quickModelPickerModels;
    }
    return _quickModelPickerModels.where((item) {
      final modelId = item.id.toLowerCase();
      final displayName = item.displayName.toLowerCase();
      return modelId.contains(query) || displayName.contains(query);
    }).toList();
  }

  @override
  String get _quickModelPickerSearchHintLabel {
    final providerId = _quickModelPickerProviderProfileId;
    if (providerId == null) {
      return '搜索模型 ID';
    }
    final provider = _findProviderProfile(providerId);
    final label = (provider?.name ?? providerId).trim();
    if (label.isEmpty) {
      return '搜索模型 ID';
    }
    return '搜索 $label 的模型';
  }

  List<ModelProviderProfileSummary> get _quickModelPickerAvailableProfiles {
    return _modelProviderProfiles.where((profile) {
      if (!profile.configured) {
        return false;
      }
      final models =
          _modelOptionsByProfileId[profile.id] ?? const <ProviderModelOption>[];
      return models.isNotEmpty;
    }).toList();
  }

  List<ProviderModelOption> _quickModelPickerModelsForProvider(
    String providerProfileId,
  ) {
    final models =
        _modelOptionsByProfileId[providerProfileId] ??
        const <ProviderModelOption>[];
    return List<ProviderModelOption>.from(models);
  }

  _QuickModelPickerSession? _resolveQuickModelPickerSession() {
    final availableProfiles = _quickModelPickerAvailableProfiles;
    if (availableProfiles.isEmpty) {
      return null;
    }
    final activeSelection = _activeDispatchSceneSelection;
    if (activeSelection != null) {
      final activeModels = _quickModelPickerModelsForProvider(
        activeSelection.providerProfileId,
      );
      final hasConfiguredProvider = availableProfiles.any(
        (profile) => profile.id == activeSelection.providerProfileId,
      );
      if (hasConfiguredProvider && activeModels.isNotEmpty) {
        return _QuickModelPickerSession(
          providerProfileId: activeSelection.providerProfileId,
          models: activeModels,
        );
      }
    }
    for (final profile in availableProfiles) {
      final models = _quickModelPickerModelsForProvider(profile.id);
      if (models.isNotEmpty) {
        return _QuickModelPickerSession(
          providerProfileId: profile.id,
          models: models,
        );
      }
    }
    return null;
  }

  void _selectQuickModelPickerProvider(String providerProfileId) {
    final models = _quickModelPickerModelsForProvider(providerProfileId);
    if (models.isEmpty) {
      return;
    }
    _stopQuickModelPickerAutoScroll();
    if (!mounted) {
      _quickModelPickerProviderProfileId = providerProfileId;
      _quickModelPickerModels = models;
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerHasEnteredList = false;
      return;
    }
    setState(() {
      _quickModelPickerProviderProfileId = providerProfileId;
      _quickModelPickerModels = models;
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerHasEnteredList = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isQuickModelPickerActive ||
          _quickModelPickerProviderProfileId != providerProfileId) {
        return;
      }
      _primeQuickModelPickerScrollPosition();
    });
  }

  void _primeQuickModelPickerScrollPosition() {
    if (!_quickModelPickerScrollController.hasClients ||
        _filteredQuickModelPickerModels.isEmpty) {
      return;
    }
    final activeSelection = _activeDispatchSceneSelection;
    final visibleModels = _filteredQuickModelPickerModels;
    final selectedIndex = activeSelection != null &&
            activeSelection.providerProfileId == _quickModelPickerProviderProfileId
        ? visibleModels.indexWhere(
            (item) => item.id == activeSelection.modelId,
          )
        : -1;
    final controller = _quickModelPickerScrollController;
    final viewport = controller.position.viewportDimension;
    final targetIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final rawOffset =
        targetIndex * _QuickModelPickerOverlay.kItemExtent -
        (viewport - _QuickModelPickerOverlay.kItemExtent) / 2;
    final targetOffset = rawOffset.clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    controller.jumpTo(targetOffset.toDouble());
  }

  double _resolveQuickModelPickerAutoScrollDelta({
    required double localDy,
    required double height,
    required bool horizontalInside,
  }) {
    final controller = _quickModelPickerScrollController;
    if (!horizontalInside ||
        !controller.hasClients ||
        controller.position.maxScrollExtent <= 0) {
      return 0;
    }
    const edgeExtent = _QuickModelPickerOverlay.kEdgeActivationExtent;
    if (localDy < edgeExtent) {
      final intensity =
          ((edgeExtent - localDy.clamp(0.0, edgeExtent)) / edgeExtent)
              .clamp(0.0, 1.0);
      return -(4 + intensity * 14);
    }
    if (localDy > height - edgeExtent) {
      final distance = (height - localDy).clamp(0.0, edgeExtent);
      final intensity = ((edgeExtent - distance) / edgeExtent).clamp(0.0, 1.0);
      return 4 + intensity * 14;
    }
    return 0;
  }

  void _stopQuickModelPickerAutoScroll() {
    _quickModelPickerAutoScrollDelta = 0;
    _quickModelPickerAutoScrollTimer?.cancel();
    _quickModelPickerAutoScrollTimer = null;
  }

  void _startQuickModelPickerAutoScroll(double delta) {
    _quickModelPickerAutoScrollDelta = delta;
    if (_quickModelPickerAutoScrollTimer != null) {
      return;
    }
    _quickModelPickerAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (timer) {
        final controller = _quickModelPickerScrollController;
        final pointerPosition = _quickModelPickerPointerPosition;
        if (!_isQuickModelPickerActive ||
            pointerPosition == null ||
            !controller.hasClients) {
          _stopQuickModelPickerAutoScroll();
          return;
        }
        final nextOffset = (controller.offset + _quickModelPickerAutoScrollDelta)
            .clamp(
              controller.position.minScrollExtent,
              controller.position.maxScrollExtent,
            )
            .toDouble();
        if ((nextOffset - controller.offset).abs() < 0.1) {
          _stopQuickModelPickerAutoScroll();
          _updateQuickModelPickerHover(
            pointerPosition,
            allowAutoScroll: false,
          );
          return;
        }
        controller.jumpTo(nextOffset);
        _updateQuickModelPickerHover(pointerPosition, allowAutoScroll: false);
      },
    );
  }

  _ChatModelOverrideSelection? _updateQuickModelPickerHover(
    Offset globalPosition, {
    bool allowAutoScroll = true,
  }) {
    _quickModelPickerPointerPosition = globalPosition;
    final providerProfileId = _quickModelPickerProviderProfileId;
    final panelContext = _quickModelPickerListKey.currentContext;
    final controller = _quickModelPickerScrollController;
    final visibleModels = _filteredQuickModelPickerModels;
    if (!_isQuickModelPickerActive ||
        providerProfileId == null ||
        visibleModels.isEmpty ||
        panelContext == null ||
        !controller.hasClients) {
      if (allowAutoScroll) {
        _stopQuickModelPickerAutoScroll();
      }
      return null;
    }
    final renderObject = panelContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      if (allowAutoScroll) {
        _stopQuickModelPickerAutoScroll();
      }
      return null;
    }
    final local = renderObject.globalToLocal(globalPosition);
    final size = renderObject.size;
    final horizontalInside = local.dx >= -24 && local.dx <= size.width + 24;
    final insideList =
        local.dx >= 0 &&
        local.dx <= size.width &&
        local.dy >= 0 &&
        local.dy <= size.height;

    if (_isQuickModelPickerLongPressing &&
        !_quickModelPickerHasEnteredList &&
        insideList) {
      if (mounted) {
        setState(() {
          _quickModelPickerHasEnteredList = true;
        });
      } else {
        _quickModelPickerHasEnteredList = true;
      }
    }

    final shouldTrackHover =
        !_isQuickModelPickerLongPressing || _quickModelPickerHasEnteredList;
    final verticalNear =
        shouldTrackHover &&
        local.dy >= -_QuickModelPickerOverlay.kEdgeActivationExtent &&
        local.dy <=
            size.height + _QuickModelPickerOverlay.kEdgeActivationExtent;

    if (allowAutoScroll) {
      final delta = shouldTrackHover
          ? _resolveQuickModelPickerAutoScrollDelta(
              localDy: local.dy,
              height: size.height,
              horizontalInside: horizontalInside,
            )
          : 0.0;
      if (delta == 0 || !shouldTrackHover) {
        _stopQuickModelPickerAutoScroll();
      } else {
        _startQuickModelPickerAutoScroll(delta);
      }
    }

    _ChatModelOverrideSelection? nextHover;
    if (shouldTrackHover && horizontalInside && verticalNear) {
      final clampedDy = local.dy.clamp(
        _QuickModelPickerOverlay.kVerticalPadding,
        size.height - _QuickModelPickerOverlay.kVerticalPadding - 0.001,
      );
      final contentDy =
          clampedDy -
          _QuickModelPickerOverlay.kVerticalPadding +
          controller.offset;
      if (contentDy >= 0) {
        final index =
            (contentDy / _QuickModelPickerOverlay.kItemExtent).floor();
        if (index >= 0 && index < visibleModels.length) {
          nextHover = _ChatModelOverrideSelection(
            providerProfileId: providerProfileId,
            modelId: visibleModels[index].id,
          );
        }
      }
    }

    if (!mounted) {
      _quickModelPickerHoverSelection = nextHover;
      return nextHover;
    }
    if (nextHover == _quickModelPickerHoverSelection) {
      return nextHover;
    }
    setState(() {
      _quickModelPickerHoverSelection = nextHover;
    });
    return nextHover;
  }

  @override
  void _handleModelLongPressStart(
    BuildContext anchorContext,
    Offset globalPosition,
  ) {
    if (_activeMode != ChatPageMode.normal || _isOpenClawSurface) {
      return;
    }
    _openQuickModelPicker(
      longPressing: true,
      globalPosition: globalPosition,
      requestSearchFocus: false,
    );
  }

  @override
  void _openQuickModelPicker({
    required bool longPressing,
    Offset? globalPosition,
    bool requestSearchFocus = false,
  }) {
    if (_activeMode != ChatPageMode.normal || _isOpenClawSurface) {
      return;
    }
    final session = _resolveQuickModelPickerSession();
    if (session == null) {
      return;
    }
    _inputFocusNode.unfocus();
    _closeConversationModelSelector();
    _quickModelPickerSearchFocusNode.unfocus();
    _quickModelPickerSearchController.clear();
    if (!mounted) {
      _isQuickModelPickerActive = true;
      _isQuickModelPickerLongPressing = longPressing;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerProviderProfileId = session.providerProfileId;
      _quickModelPickerModels = session.models;
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = globalPosition;
      return;
    }
    setState(() {
      _showSlashCommandPanel = false;
      _showModelMentionPanel = false;
      _openClawPanelExpanded = false;
      _openClawDeployPanelExpanded = false;
      _isQuickModelPickerActive = true;
      _isQuickModelPickerLongPressing = longPressing;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerProviderProfileId = session.providerProfileId;
      _quickModelPickerModels = session.models;
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = globalPosition;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isQuickModelPickerActive) {
        return;
      }
      _primeQuickModelPickerScrollPosition();
      if (globalPosition != null) {
        _updateQuickModelPickerHover(globalPosition);
      }
      if (requestSearchFocus) {
        _quickModelPickerSearchFocusNode.requestFocus();
      }
    });
  }

  @override
  void _handleModelLongPressMove(Offset globalPosition) {
    if (!_isQuickModelPickerActive) {
      return;
    }
    _updateQuickModelPickerHover(globalPosition);
  }

  @override
  Future<void> _handleModelLongPressEnd(Offset globalPosition) async {
    if (!_isQuickModelPickerActive) {
      return;
    }
    final selection = _updateQuickModelPickerHover(
      globalPosition,
      allowAutoScroll: false,
    );
    _stopQuickModelPickerAutoScroll();
    if (!mounted) {
      _isQuickModelPickerLongPressing = false;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerHoverSelection = null;
    } else {
      setState(() {
        _isQuickModelPickerLongPressing = false;
        _quickModelPickerHasEnteredList = false;
        _quickModelPickerPointerPosition = null;
        if (selection == null) {
          _quickModelPickerHoverSelection = null;
        }
      });
    }
    if (selection == null) {
      return;
    }
    _closeQuickModelPicker();
    await _applyDispatchSceneModelSelection(
      providerProfileId: selection.providerProfileId,
      modelId: selection.modelId,
    );
  }

  @override
  void _handleModelLongPressCancel() {
    _closeQuickModelPicker();
  }

  @override
  Future<void> _openConversationModelSelector(
    BuildContext anchorContext,
  ) async {
    if (_activeMode != ChatPageMode.normal || _isOpenClawSurface) {
      return;
    }
    _closeQuickModelPicker();
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
    if (!mounted) {
      return;
    }
    if (_isConversationModelSelectorActive) {
      _conversationModelSearchFocusNode.requestFocus();
      return;
    }
    _conversationModelSearchController.clear();
    setState(() {
      _isConversationModelSelectorActive = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isConversationModelSelectorActive) {
        return;
      }
      _conversationModelSearchFocusNode.requestFocus();
    });
  }

  @override
  void _closeConversationModelSelector({bool clearSearch = true}) {
    final shouldClearSearch = clearSearch;
    if (!_isConversationModelSelectorActive) {
      if (shouldClearSearch &&
          _conversationModelSearchController.text.isNotEmpty) {
        _conversationModelSearchController.clear();
      }
      _conversationModelSearchFocusNode.unfocus();
      return;
    }
    _conversationModelSearchFocusNode.unfocus();
    if (!mounted) {
      _isConversationModelSelectorActive = false;
      if (shouldClearSearch) {
        _conversationModelSearchController.clear();
      }
      return;
    }
    setState(() {
      _isConversationModelSelectorActive = false;
    });
    if (shouldClearSearch) {
      _conversationModelSearchController.clear();
    }
  }

  @override
  void _closeQuickModelPicker() {
    _stopQuickModelPickerAutoScroll();
    _quickModelPickerSearchFocusNode.unfocus();
    if (!_isQuickModelPickerActive) {
      _isQuickModelPickerLongPressing = false;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerProviderProfileId = null;
      _quickModelPickerModels = const [];
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerSearchController.clear();
      return;
    }
    if (!mounted) {
      _isQuickModelPickerActive = false;
      _isQuickModelPickerLongPressing = false;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerProviderProfileId = null;
      _quickModelPickerModels = const [];
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerSearchController.clear();
      return;
    }
    setState(() {
      _isQuickModelPickerActive = false;
      _isQuickModelPickerLongPressing = false;
      _quickModelPickerHasEnteredList = false;
      _quickModelPickerProviderProfileId = null;
      _quickModelPickerModels = const [];
      _quickModelPickerHoverSelection = null;
      _quickModelPickerPointerPosition = null;
      _quickModelPickerSearchController.clear();
    });
  }

  @override
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
      showToast('切换成功', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('更新 Agent 模型失败：$e', type: ToastType.error);
    }
  }

  Future<void> _handleConversationModelSelectorSelection(
    _ChatModelOverrideSelection selection,
  ) async {
    _closeQuickModelPicker();
    _closeConversationModelSelector();
    await _applyDispatchSceneModelSelection(
      providerProfileId: selection.providerProfileId,
      modelId: selection.modelId,
    );
  }

  @override
  Widget _buildConversationModelSelectorPanel() {
    return _ConversationModelSelectorPanel(
      profiles: _modelProviderProfiles,
      providerModelsByProfileId: _modelOptionsByProfileId,
      currentSelection: _activeDispatchSceneSelection,
      query: _conversationModelSearchController.text,
      onSelect: (selection) {
        unawaited(_handleConversationModelSelectorSelection(selection));
      },
    );
  }

  @override
  Widget? _buildQuickModelPickerOverlay() {
    final providers = _quickModelPickerAvailableProfiles;
    final providerProfileId = _quickModelPickerProviderProfileId;
    final visibleModels = _filteredQuickModelPickerModels;
    if (!_isQuickModelPickerActive ||
        providerProfileId == null ||
        providers.isEmpty ||
        _quickModelPickerModels.isEmpty) {
      return null;
    }
    return _QuickModelPickerOverlay(
      panelKey: _quickModelPickerPanelKey,
      listKey: _quickModelPickerListKey,
      providers: providers,
      providerProfileId: providerProfileId,
      models: visibleModels,
      currentSelection: _activeDispatchSceneSelection,
      hoverSelection: _quickModelPickerHoverSelection,
      scrollController: _quickModelPickerScrollController,
      onProviderChanged: _selectQuickModelPickerProvider,
      onSelect: (selection) {
        unawaited(
          _handleConversationModelSelectorSelection(selection),
        );
      },
    );
  }

  @override
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

class _QuickModelPickerSession {
  final String providerProfileId;
  final List<ProviderModelOption> models;

  const _QuickModelPickerSession({
    required this.providerProfileId,
    required this.models,
  });
}

class _QuickModelPickerOverlay extends StatelessWidget {
  static const double kItemExtent = 44;
  static const double kVerticalPadding = 8;
  static const double kEdgeActivationExtent = 40;
  static const double _kMaxListHeight = 264;

  final Key? panelKey;
  final Key? listKey;
  final List<ModelProviderProfileSummary> providers;
  final String providerProfileId;
  final List<ProviderModelOption> models;
  final _ChatModelOverrideSelection? currentSelection;
  final _ChatModelOverrideSelection? hoverSelection;
  final ScrollController scrollController;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<_ChatModelOverrideSelection> onSelect;

  const _QuickModelPickerOverlay({
    this.panelKey,
    this.listKey,
    required this.providers,
    required this.providerProfileId,
    required this.models,
    required this.currentSelection,
    required this.hoverSelection,
    required this.scrollController,
    required this.onProviderChanged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final contentHeight = models.length * kItemExtent + kVerticalPadding * 2;
    final maxHeight = contentHeight.clamp(96.0, _kMaxListHeight).toDouble();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 272),
      child: Container(
        key: panelKey,
        width: 272,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE7F7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0F172A),
              blurRadius: 20,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: providers.map((profile) {
                              final label = profile.name.trim().isEmpty
                                  ? profile.id
                                  : profile.name.trim();
                              final selected = profile.id == providerProfileId;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: selected
                                      ? null
                                      : () {
                                          onProviderChanged(profile.id);
                                        },
                                  borderRadius: BorderRadius.circular(999),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    curve: Curves.easeOut,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFFEAF3FF)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(999),
                                      border: selected
                                          ? Border.all(
                                              color: const Color(0xFF7FB6FF),
                                            )
                                          : null,
                                    ),
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: selected
                                            ? const Color(0xFF2C7FEB)
                                            : const Color(0xFF64748B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${models.length} 项',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (models.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
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
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ListView.builder(
                        key: listKey,
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          vertical: kVerticalPadding,
                        ),
                        shrinkWrap: true,
                        itemExtent: kItemExtent,
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final isCurrent =
                              currentSelection?.providerProfileId ==
                                  providerProfileId &&
                              currentSelection?.modelId == model.id;
                          final isHovered =
                              hoverSelection?.providerProfileId ==
                                  providerProfileId &&
                              hoverSelection?.modelId == model.id;
                          final backgroundColor = isHovered
                              ? const Color(0xFFDCEBFF)
                              : isCurrent
                              ? const Color(0xFFEAF3FF)
                              : Colors.white;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                onSelect(
                                  _ChatModelOverrideSelection(
                                    providerProfileId: providerProfileId,
                                    modelId: model.id,
                                  ),
                                );
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 90),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isHovered
                                      ? Border.all(
                                          color: const Color(0xFF7FB6FF),
                                        )
                                      : null,
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
                                    if (isHovered)
                                      const Icon(
                                        Icons.keyboard_double_arrow_left_rounded,
                                        size: 16,
                                        color: Color(0xFF2C7FEB),
                                      )
                                    else if (isCurrent)
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Color(0xFF2C7FEB),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

class _ConversationModelSelectorPanel extends StatefulWidget {
  const _ConversationModelSelectorPanel({
    required this.profiles,
    required this.providerModelsByProfileId,
    required this.currentSelection,
    required this.query,
    required this.onSelect,
  });

  final List<ModelProviderProfileSummary> profiles;
  final Map<String, List<ProviderModelOption>> providerModelsByProfileId;
  final _ChatModelOverrideSelection? currentSelection;
  final String query;
  final ValueChanged<_ChatModelOverrideSelection> onSelect;

  @override
  State<_ConversationModelSelectorPanel> createState() =>
      _ConversationModelSelectorPanelState();
}

class _ConversationModelSelectorPanelState
    extends State<_ConversationModelSelectorPanel> {
  late final Set<String> _expandedProfileIds;

  bool get _hasSearchQuery => widget.query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _expandedProfileIds = <String>{};
    _seedExpandedProfiles();
  }

  @override
  void didUpdateWidget(covariant _ConversationModelSelectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousProviderId = oldWidget.currentSelection?.providerProfileId;
    final currentProviderId = widget.currentSelection?.providerProfileId;
    if (currentProviderId != null && currentProviderId != previousProviderId) {
      _expandedProfileIds.add(currentProviderId);
    }
    if (_expandedProfileIds.isEmpty) {
      _seedExpandedProfiles();
    }
  }

  void _seedExpandedProfiles() {
    final selectedProviderId = widget.currentSelection?.providerProfileId;
    if (selectedProviderId != null && selectedProviderId.isNotEmpty) {
      _expandedProfileIds.add(selectedProviderId);
      return;
    }
    for (final profile in widget.profiles) {
      if (profile.configured) {
        _expandedProfileIds.add(profile.id);
        break;
      }
    }
  }

  List<ProviderModelOption> _filteredModels(String profileId) {
    final query = widget.query.trim().toLowerCase();
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
          widget.onSelect(
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
        (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 180)
            .clamp(220.0, 360.0)
            .toDouble();
    final configuredProfiles = widget.profiles
        .where((profile) => profile.configured)
        .toList();
    final visibleProfiles = _visibleProfiles;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: dynamicMaxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE7F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
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
