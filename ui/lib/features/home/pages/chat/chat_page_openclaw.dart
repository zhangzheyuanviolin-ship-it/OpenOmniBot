part of 'chat_page.dart';

mixin _ChatPageOpenClawMixin on _ChatPageStateBase {
  @override
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
      });
      await _ensureOpenClawUserId();
    } catch (e) {
      debugPrint('加载OpenClaw配置失败: $e');
    }
  }

  @override
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

  @override
  void _handleSlashCommandInput() {
    final value = _messageController.value;
    final shouldShowSlash = value.text.trimLeft().startsWith('/');
    final nextMentionToken = shouldShowSlash
        ? null
        : _parseActiveModelMentionToken(value);
    final shouldShowModelMention = nextMentionToken != null;
    final shouldCollapsePanels = !_isOpenClawSurface;
    final nextOpenClawPanelExpanded = shouldCollapsePanels
        ? false
        : _openClawPanelExpanded;
    final nextOpenClawDeployPanelExpanded = shouldCollapsePanels
        ? false
        : _openClawDeployPanelExpanded;
    final nextSlashPanelVisible =
        shouldShowSlash ||
        shouldShowModelMention ||
        nextOpenClawPanelExpanded ||
        nextOpenClawDeployPanelExpanded;

    if (!mounted) return;

    final shouldUpdate =
        nextSlashPanelVisible != _showSlashCommandPanel ||
        shouldShowModelMention != _showModelMentionPanel ||
        nextMentionToken != _activeModelMentionToken ||
        nextOpenClawPanelExpanded != _openClawPanelExpanded ||
        nextOpenClawDeployPanelExpanded != _openClawDeployPanelExpanded;
    if (!shouldUpdate) {
      return;
    }

    setState(() {
      _showSlashCommandPanel = nextSlashPanelVisible;
      _showModelMentionPanel = shouldShowModelMention;
      _activeModelMentionToken = nextMentionToken;
      _openClawPanelExpanded = nextOpenClawPanelExpanded;
      _openClawDeployPanelExpanded = nextOpenClawDeployPanelExpanded;
    });
  }

  @override
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
      _openClawDeployPanelExpanded = false;
      if (expand) {
        _openClawBaseUrlController.text = _openClawBaseUrl;
        _openClawTokenController.text = _openClawToken;
        _openClawUserIdController.text = _openClawUserId;
      }
    });
  }

  @override
  void _hideSlashCommandPanel() {
    if (!mounted) return;
    setState(() {
      _showSlashCommandPanel = false;
      _showModelMentionPanel = false;
      _openClawPanelExpanded = false;
      _openClawDeployPanelExpanded = false;
    });
  }

  @override
  bool _isPointerInside(GlobalKey key, Offset position) {
    final context = key.currentContext;
    if (context == null) return false;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return false;
    final offset = renderBox.localToGlobal(Offset.zero);
    final rect = offset & renderBox.size;
    return rect.contains(position);
  }

  @override
  Future<void> _handleOutsideTap(Offset position) async {
    if (!_showSlashCommandPanel &&
        !_showModelMentionPanel &&
        !_openClawPanelExpanded &&
        !_openClawDeployPanelExpanded) {
      return;
    }
    if (_isPointerInside(_openClawPanelKey, position) ||
        _isPointerInside(_inputAreaKey, position)) {
      return;
    }
    if (_openClawDeployPanelExpanded &&
        (_openClawDeploySnapshot?.running ?? false)) {
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

  @override
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

  @override
  String _buildDefaultOpenClawDeployConfigJson({
    required String providerBaseUrl,
    required String modelId,
  }) {
    const providerId = 'omnibot_custom';
    final config = <String, dynamic>{
      'agents': {
        'defaults': {
          'workspace': '/root/.openclaw/workspace',
          'model': {'primary': '$providerId/$modelId'},
        },
      },
      'models': {
        'mode': 'merge',
        'providers': {
          providerId: {
            'api': 'openai-completions',
            'baseUrl': providerBaseUrl,
            'apiKey': _ChatPageStateBase._openClawProviderApiKeyEnv,
            'models': [
              {
                'id': modelId,
                'name': modelId,
                'reasoning': false,
                'input': ['text'],
                'contextWindow': 128000,
                'maxTokens': 32768,
                'cost': {
                  'input': 0,
                  'output': 0,
                  'cacheRead': 0,
                  'cacheWrite': 0,
                },
              },
            ],
          },
        },
      },
      'gateway': {
        'mode': 'local',
        'bind': 'loopback',
        'port': 18789,
        'auth': {
          'mode': 'token',
          'token': _ChatPageStateBase._openClawGatewayTokenEnvRef,
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  @override
  String _buildOpenClawProviderBaseUrl(String providerBaseUrl) {
    var normalized = providerBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.endsWith('/v1')) {
      return normalized;
    }
    if (normalized.endsWith('/v1/chat/completions')) {
      return normalized.substring(
        0,
        normalized.length - '/chat/completions'.length,
      );
    }
    if (normalized.endsWith('/chat/completions')) {
      normalized = normalized.substring(
        0,
        normalized.length - '/chat/completions'.length,
      );
      normalized = normalized.replaceAll(RegExp(r'/+$'), '');
      if (normalized.endsWith('/v1')) {
        return normalized;
      }
    }
    return '$normalized/v1';
  }

  @override
  String? _validateOpenClawDeployConfig(String configJson) {
    final dynamic decodedJson;
    try {
      decodedJson = jsonDecode(configJson);
    } catch (_) {
      return '配置 JSON 格式有误，请检查后重试';
    }
    if (decodedJson is! Map) {
      return 'OpenClaw 配置顶层必须是 JSON 对象';
    }

    final root = Map<String, dynamic>.from(decodedJson);
    final rawGateway = root['gateway'];
    if (rawGateway is! Map) {
      return 'OpenClaw 配置必须包含 gateway 字段';
    }
    final gateway = rawGateway.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawAuth = gateway['auth'];
    if (rawAuth is! Map) {
      return 'OpenClaw 配置必须包含 gateway.auth 字段';
    }
    final auth = rawAuth.map((key, value) => MapEntry(key.toString(), value));
    final authMode = (auth['mode'] ?? '').toString().trim();
    if (authMode != 'token') {
      return 'gateway.auth.mode 必须保持为 token';
    }
    return null;
  }

  @override
  String _buildOpenClawDeployConfigDraftKey(
    _OpenClawDeployResolvedConfig resolvedConfig,
  ) {
    final request = resolvedConfig.request;
    return [request.providerBaseUrl.trim(), request.modelId.trim()].join('|');
  }

  @override
  void _syncOpenClawDeployConfigDraft(
    _OpenClawDeployResolvedConfig resolvedConfig, {
    bool force = false,
  }) {
    final draftKey = _buildOpenClawDeployConfigDraftKey(resolvedConfig);
    final shouldReset =
        force ||
        _openClawDeployConfigDraftKey != draftKey ||
        !_openClawDeployConfigTouched;
    if (!shouldReset) {
      return;
    }
    _openClawDeployConfigDraftKey = draftKey;
    _openClawDeployConfigTouched = false;
    _openClawDeployConfigController.text = resolvedConfig.request.configJson;
  }

  @override
  _OpenClawDeployPanelState _buildOpenClawDeployPanelState() {
    if (_isLoadingOpenClawDeployStatus) {
      return const _OpenClawDeployPanelState.loading(
        message: '正在检查内嵌 Ubuntu 与当前 Agent 模型...',
      );
    }

    final runtimeStatus = _openClawDeployRuntimeStatus;
    if (runtimeStatus == null) {
      return const _OpenClawDeployPanelState.loading(
        message: '正在读取 OpenClaw 部署状态...',
      );
    }

    if (!runtimeStatus.allReady) {
      final message = runtimeStatus.message.isNotEmpty
          ? runtimeStatus.message
          : '内嵌 Ubuntu 尚未完成初始化。';
      return _OpenClawDeployPanelState.action(
        kind: _OpenClawDeployPanelKind.runtimeNotReady,
        title: '内嵌 Ubuntu 未就绪',
        message: message,
        actionLabel: '去初始化',
        actionRoute: '/home/termux_setting',
      );
    }

    final selection = _activeDispatchSceneSelection;
    if (selection == null || selection.modelId.trim().isEmpty) {
      return const _OpenClawDeployPanelState.action(
        kind: _OpenClawDeployPanelKind.sceneModelMissing,
        title: 'Agent 模型未配置',
        message: '请先为 scene.dispatch.model 绑定一个可用模型，再执行一键部署。',
        actionLabel: '去模型设置',
        actionRoute: '/home/scene_model_setting',
      );
    }

    final profile = _findProviderProfile(selection.providerProfileId);
    if (profile == null ||
        !profile.configured ||
        profile.baseUrl.trim().isEmpty ||
        profile.apiKey.trim().isEmpty) {
      return const _OpenClawDeployPanelState.action(
        kind: _OpenClawDeployPanelKind.providerConfigMissing,
        title: 'Provider 未配置完整',
        message: '当前 Agent 模型缺少 provider baseUrl 或 API key，请先补齐。',
        actionLabel: '去 Provider 设置',
        actionRoute: '/home/vlm_model_setting',
      );
    }

    final deployProviderBaseUrl = _buildOpenClawProviderBaseUrl(
      profile.baseUrl.trim(),
    );
    return _OpenClawDeployPanelState.ready(
      resolvedConfig: _OpenClawDeployResolvedConfig(
        request: OpenClawDeployRequest(
          providerBaseUrl: deployProviderBaseUrl,
          providerApiKey: profile.apiKey.trim(),
          modelId: selection.modelId.trim(),
          configJson: _buildDefaultOpenClawDeployConfigJson(
            providerBaseUrl: deployProviderBaseUrl,
            modelId: selection.modelId.trim(),
          ),
        ),
        providerName: profile.name.trim().isEmpty ? profile.id : profile.name,
        modelId: selection.modelId.trim(),
      ),
    );
  }

  @override
  Future<void> _showOpenClawDeployPanel() async {
    if (!_isOpenClawSurface) {
      _showSnackBar('请先顶部滑动到 OpenClaw 模式');
      return;
    }
    if (!mounted) return;
    setState(() {
      _showSlashCommandPanel = true;
      _showModelMentionPanel = false;
      _activeModelMentionToken = null;
      _openClawPanelExpanded = false;
      _openClawDeployPanelExpanded = true;
    });
    await _refreshOpenClawDeployPanelState();
  }

  @override
  Future<void> _refreshOpenClawDeployPanelState() async {
    if (!_isOpenClawSurface) {
      _stopOpenClawDeploySnapshotPolling();
      if (!mounted) return;
      setState(() {
        _openClawDeployRuntimeStatus = null;
        _openClawDeploySnapshot = null;
        _openClawGatewayStatus = null;
        _isLoadingOpenClawDeployStatus = false;
      });
      return;
    }
    await _loadNormalChatModelContext();
    if (mounted) {
      setState(() {
        _isLoadingOpenClawDeployStatus = true;
      });
    }
    EmbeddedTerminalRuntimeStatus? runtimeStatus;
    OpenClawDeploySnapshot? snapshot;
    OpenClawGatewayStatus? gatewayStatus;
    try {
      runtimeStatus = await getEmbeddedTerminalRuntimeStatus();
    } catch (_) {
      runtimeStatus = null;
    }
    try {
      snapshot = await getOpenClawDeploySnapshot();
    } catch (_) {
      snapshot = _openClawDeploySnapshot;
    }
    try {
      gatewayStatus = await getOpenClawGatewayStatus();
    } catch (_) {
      gatewayStatus = _openClawGatewayStatus;
    }
    if (!mounted) return;
    setState(() {
      _openClawDeployRuntimeStatus = runtimeStatus;
      _openClawDeploySnapshot = snapshot;
      _openClawGatewayStatus = gatewayStatus;
      _isLoadingOpenClawDeployStatus = false;
    });
    final panelState = _buildOpenClawDeployPanelState();
    final resolvedConfig = panelState.resolvedConfig;
    if (resolvedConfig != null) {
      _syncOpenClawDeployConfigDraft(resolvedConfig);
    }
    if (snapshot != null) {
      await _handleOpenClawDeploySnapshot(snapshot);
    }
    if (snapshot?.running == true) {
      _startOpenClawDeploySnapshotPolling();
    } else {
      _stopOpenClawDeploySnapshotPolling();
    }
  }

  @override
  void _startOpenClawDeploySnapshotPolling() {
    _openClawDeploySnapshotPoller?.cancel();
    _openClawDeploySnapshotPoller = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) {
        unawaited(_pollOpenClawDeploySnapshot());
      },
    );
  }

  @override
  void _stopOpenClawDeploySnapshotPolling() {
    _openClawDeploySnapshotPoller?.cancel();
    _openClawDeploySnapshotPoller = null;
  }

  @override
  Future<void> _pollOpenClawDeploySnapshot() async {
    try {
      final snapshot = await getOpenClawDeploySnapshot();
      if (!mounted) return;
      setState(() {
        _openClawDeploySnapshot = snapshot;
      });
      await _handleOpenClawDeploySnapshot(snapshot);
      if (!snapshot.running) {
        _stopOpenClawDeploySnapshotPolling();
      }
    } catch (_) {
      _stopOpenClawDeploySnapshotPolling();
    }
  }

  @override
  Future<void> _handleOpenClawDeploySnapshot(
    OpenClawDeploySnapshot snapshot,
  ) async {
    if (!snapshot.completed || _hasHandledOpenClawDeployCompletion) {
      return;
    }
    _hasHandledOpenClawDeployCompletion = true;
    if (snapshot.success == true) {
      var baseUrl = (snapshot.gatewayBaseUrl ?? '').trim();
      var token = (snapshot.gatewayToken ?? '').trim();
      if ((baseUrl.isEmpty || token.isEmpty) &&
          (_openClawGatewayStatus?.dashboardUrl?.isNotEmpty ?? false)) {
        final dashboardUrl = _openClawGatewayStatus!.dashboardUrl!;
        final uri = Uri.tryParse(dashboardUrl);
        final fragment = uri?.fragment ?? '';
        final fragmentToken = RegExp(
          r'(?:^|&)token=([^&]+)',
        ).firstMatch(fragment)?.group(1)?.trim();
        token = token.isNotEmpty ? token : (fragmentToken ?? '');
        baseUrl = baseUrl.isNotEmpty
            ? baseUrl
            : (_openClawGatewayStatus!.dashboardUrl!.split('/#').first.trim());
      }
      if (baseUrl.isEmpty || token.isEmpty) {
        if (mounted) {
          _showSnackBar('OpenClaw 部署已完成，但缺少回连参数');
        }
        return;
      }
      await _applyOpenClawConfig(
        baseUrl: baseUrl,
        token: token,
        userId: _openClawUserId,
        enable: true,
      );
      _messageController.clear();
      _inputFocusNode.unfocus();
      _stopOpenClawDeploySnapshotPolling();
      if (!mounted) return;
      setState(() {
        _showSlashCommandPanel = false;
        _showModelMentionPanel = false;
        _openClawPanelExpanded = false;
        _openClawDeployPanelExpanded = false;
      });
      await _checkOpenClawConnection();
      return;
    }
    if (mounted && (snapshot.errorMessage ?? '').isNotEmpty) {
      _showSnackBar(snapshot.errorMessage!);
    }
  }

  @override
  Future<void> _startOpenClawDeployFromPanel() async {
    final panelState = _buildOpenClawDeployPanelState();
    final resolvedConfig = panelState.resolvedConfig;
    if (resolvedConfig == null) {
      return;
    }
    final configJson = _openClawDeployConfigController.text.trim();
    if (configJson.isEmpty) {
      _showSnackBar('请先确认要写入的 OpenClaw 配置');
      return;
    }
    final validationError = _validateOpenClawDeployConfig(configJson);
    if (validationError != null) {
      _showSnackBar(validationError);
      return;
    }
    _hasHandledOpenClawDeployCompletion = false;
    try {
      final result = await startOpenClawDeploy(
        OpenClawDeployRequest(
          providerBaseUrl: resolvedConfig.request.providerBaseUrl,
          providerApiKey: resolvedConfig.request.providerApiKey,
          modelId: resolvedConfig.request.modelId,
          configJson: configJson,
        ),
      );
      if (!mounted) return;
      if (!result.accepted && !result.alreadyRunning) {
        _showSnackBar(
          result.message.isNotEmpty ? result.message : '无法启动 OpenClaw 部署',
        );
        return;
      }
      await _refreshOpenClawDeployPanelState();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('启动 OpenClaw 部署失败: $e');
    }
  }

  @override
  Future<bool> _tryHandleSlashCommand(String messageText) async {
    final trimmed = messageText.trim();
    if (!trimmed.startsWith('/')) return false;

    if (trimmed == '/deploy') {
      if (!_isOpenClawSurface) {
        _showSnackBar('普通聊天模式下已停用 /deploy，请滑到右侧 OpenClaw 模式');
        return true;
      }
      _messageController.clear();
      _inputFocusNode.unfocus();
      await _showOpenClawDeployPanel();
      return true;
    }

    if (trimmed.startsWith('/deploy')) {
      _showSnackBar('格式: /deploy');
      return true;
    }

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
  Future<void> _checkOpenClawConnection() async {
    await OpenClawConnectionChecker.checkAndToast(_openClawBaseUrl);
  }

  @override
  Widget _buildOpenClawCommandRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget _buildOpenClawDeployPanel() {
    final panelState = _buildOpenClawDeployPanelState();
    final snapshot = _openClawDeploySnapshot;
    final hasSnapshot =
        snapshot != null &&
        (snapshot.running || (snapshot.completed && snapshot.success == false));
    final effectiveLogLines = snapshot?.logLines ?? const <String>[];

    Widget buildLogBox(List<String> lines) {
      if (lines.isEmpty) {
        return const SizedBox.shrink();
      }
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            lines.join('\n'),
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 11,
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
      );
    }

    Widget buildHeader(String title, String subtitle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      );
    }

    if (hasSnapshot) {
      final progress = snapshot.progress.clamp(0.0, 1.0).toDouble();
      final isRunning = snapshot.running;
      final isSuccess = snapshot.success == true;
      final isFailed = snapshot.completed && snapshot.success == false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildHeader(
            'OpenClaw 一键部署',
            isRunning
                ? '正在将 OpenClaw 部署到内嵌 Ubuntu，并接入当前 OpenClaw 模式。'
                : isSuccess
                ? '部署完成，正在回连本机 OpenClaw 网关。'
                : '部署未完成，请查看日志后重试。',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.stage.isNotEmpty ? snapshot.stage : '正在处理...',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isRunning)
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2C7FEB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: isRunning ? progress : 1,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(
              isFailed ? const Color(0xFFDC2626) : const Color(0xFF2C7FEB),
            ),
          ),
          if ((snapshot.errorMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              snapshot.errorMessage!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (effectiveLogLines.isNotEmpty) ...[
            const SizedBox(height: 10),
            buildLogBox(effectiveLogLines),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (isFailed)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _openClawDeploySnapshot = null;
                      _hasHandledOpenClawDeployCompletion = false;
                    });
                  },
                  child: const Text('修改配置'),
                ),
              if (isFailed)
                TextButton(
                  onPressed: () {
                    GoRouterManager.push('/home/termux_setting');
                  },
                  child: const Text('查看引导'),
                ),
              const Spacer(),
              if (isRunning)
                const Text(
                  '部署中...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (isFailed)
                FilledButton(
                  onPressed: () {
                    unawaited(_startOpenClawDeployFromPanel());
                  },
                  child: const Text('重试部署'),
                ),
            ],
          ),
        ],
      );
    }

    switch (panelState.kind) {
      case _OpenClawDeployPanelKind.loadingRuntime:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildHeader('OpenClaw 一键部署', panelState.message),
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  '正在准备部署信息...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        );
      case _OpenClawDeployPanelKind.runtimeNotReady:
      case _OpenClawDeployPanelKind.providerConfigMissing:
      case _OpenClawDeployPanelKind.sceneModelMissing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildHeader(panelState.title, panelState.message),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () {
                  if (panelState.actionRoute != null) {
                    GoRouterManager.push(panelState.actionRoute!);
                  }
                },
                child: Text(panelState.actionLabel ?? '查看引导'),
              ),
            ),
          ],
        );
      case _OpenClawDeployPanelKind.ready:
        final resolvedConfig = panelState.resolvedConfig!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildHeader(
              'OpenClaw 一键部署',
              '将复用当前 Agent 模型配置，无需重复填写 Provider 或 API key。',
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provider：${resolvedConfig.providerName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1F2937),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Model：${resolvedConfig.modelId}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '部署成功后会自动连接到本机 http://127.0.0.1:18789',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '将要写入 ~/.openclaw/openclaw.json，你可以先检查并修改。',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _openClawGatewayStatus?.legacyConfigNeedsRedeploy == true
                  ? '检测到旧版部署痕迹，本次部署会写入真实 gateway token，并把 Provider API key 保存到原生安全存储。'
                  : 'Provider API key 会保存到原生安全存储，部署时会把真实 gateway token 归一化写入配置。',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            if ((_openClawGatewayStatus?.lastError ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _openClawGatewayStatus!.lastError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFB34A40),
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _openClawDeployConfigController,
                minLines: 12,
                maxLines: 16,
                onChanged: (_) {
                  _openClawDeployConfigTouched = true;
                },
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.all(12),
                  hintText: '{\n  "gateway": {}\n}',
                  hintStyle: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _syncOpenClawDeployConfigDraft(
                        resolvedConfig,
                        force: true,
                      );
                    });
                  },
                  child: const Text('恢复默认'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    unawaited(_startOpenClawDeployFromPanel());
                  },
                  child: const Text('开始部署'),
                ),
              ],
            ),
          ],
        );
    }
  }
}

enum _OpenClawDeployPanelKind {
  loadingRuntime,
  runtimeNotReady,
  providerConfigMissing,
  sceneModelMissing,
  ready,
}

class _OpenClawDeployResolvedConfig {
  final OpenClawDeployRequest request;
  final String providerName;
  final String modelId;

  const _OpenClawDeployResolvedConfig({
    required this.request,
    required this.providerName,
    required this.modelId,
  });
}

class _OpenClawDeployPanelState {
  final _OpenClawDeployPanelKind kind;
  final String title;
  final String message;
  final String? actionLabel;
  final String? actionRoute;
  final _OpenClawDeployResolvedConfig? resolvedConfig;

  const _OpenClawDeployPanelState.loading({required this.message})
    : kind = _OpenClawDeployPanelKind.loadingRuntime,
      title = 'OpenClaw 一键部署',
      actionLabel = null,
      actionRoute = null,
      resolvedConfig = null;

  const _OpenClawDeployPanelState.action({
    required this.kind,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionRoute,
  }) : resolvedConfig = null;

  const _OpenClawDeployPanelState.ready({required this.resolvedConfig})
    : kind = _OpenClawDeployPanelKind.ready,
      title = 'OpenClaw 一键部署',
      message = '',
      actionLabel = null,
      actionRoute = null;

  _OpenClawDeployPanelState copyWith({
    String? title,
    String? message,
    String? actionLabel,
    String? actionRoute,
    _OpenClawDeployResolvedConfig? resolvedConfig,
  }) {
    return _OpenClawDeployPanelState._(
      kind: kind,
      title: title ?? this.title,
      message: message ?? this.message,
      actionLabel: actionLabel ?? this.actionLabel,
      actionRoute: actionRoute ?? this.actionRoute,
      resolvedConfig: resolvedConfig ?? this.resolvedConfig,
    );
  }

  const _OpenClawDeployPanelState._({
    required this.kind,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionRoute,
    required this.resolvedConfig,
  });
}
