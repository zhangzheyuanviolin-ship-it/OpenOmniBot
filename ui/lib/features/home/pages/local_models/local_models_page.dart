import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/services/mnn_local_models_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

enum _LocalModelsTab { service, market }

const String _llamaCppBackend = 'llama.cpp';
const String _omniinferMnnBackend = 'omniinfer-mnn';

class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key, this.initialTab = 'service'});

  final String initialTab;

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _installedSearchController =
      TextEditingController();
  final TextEditingController _marketSearchController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  StreamSubscription<MnnLocalEvent>? _eventSubscription;
  Timer? _pollTimer;
  Timer? _configSaveDebounce;

  MnnLocalConfig? _config;
  List<MnnLocalModel> _installedModels = const [];
  List<MnnLocalModel> _marketModels = const [];

  bool _loadingInstalled = true;
  bool _loadingMarket = true;
  bool _loadingConfig = true;
  bool _togglingApiService = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _LocalModelsTab.values.length,
      vsync: this,
      initialIndex: _tabIndexFromName(widget.initialTab),
    );
    _tabController.addListener(_handleTabChanged);
    _eventSubscription = MnnLocalModelsService.eventStream.listen(_handleEvent);
    _bootstrap();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _configSaveDebounce?.cancel();
    _eventSubscription?.cancel();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _installedSearchController.dispose();
    _marketSearchController.dispose();
    _portController.dispose();
    super.dispose();
  }

  int _tabIndexFromName(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'market':
        return _LocalModelsTab.market.index;
      case 'benchmark':
      case 'installed':
      case 'service':
      default:
        return _LocalModelsTab.service.index;
    }
  }

  List<MnnLocalModel> get _filteredInstalledModels {
    final normalizedQuery = _installedSearchController.text.trim().toLowerCase();
    return _installedModels.where((item) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final haystacks = <String>[
        item.name,
        item.id,
        item.vendor,
        item.description,
        item.path,
        ...item.tags,
        ...item.extraTags,
      ];
      return haystacks.any(
        (value) => value.toLowerCase().contains(normalizedQuery),
      );
    }).toList();
  }

  List<MnnLocalModel> get _serviceModels =>
      _installedModels.where((item) => item.category == 'llm').toList();

  Future<void> _bootstrap() async {
    try {
      final overview = await MnnLocalModelsService.getOverview(
        installedQuery: _installedSearchController.text.trim(),
        marketQuery: _marketSearchController.text.trim(),
        marketCategory: 'llm',
      );
      if (!mounted) return;
      setState(() {
        _config = overview.config;
        _installedModels = overview.installedModels;
        _marketModels = overview.market.models;
        _loadingConfig = false;
        _loadingInstalled = false;
        _loadingMarket = false;
      });
      _syncConfigControllers(overview.config);
    } catch (_) {
      await Future.wait([
        _refreshConfig(silent: true),
        _refreshInstalled(silent: true),
        _refreshMarket(silent: true),
      ]);
    }
  }

  void _syncConfigControllers(MnnLocalConfig config) {
    final nextPort = config.apiPort.toString();
    if (_portController.text != nextPort) {
      _portController.text = nextPort;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      switch (_LocalModelsTab.values[_tabController.index]) {
        case _LocalModelsTab.service:
          _refreshConfig(silent: true);
          _refreshInstalled(silent: true);
          break;
        case _LocalModelsTab.market:
          _refreshMarket(silent: true);
          break;
      }
    });
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    switch (_LocalModelsTab.values[_tabController.index]) {
      case _LocalModelsTab.service:
        _refreshConfig(silent: true);
        _refreshInstalled(silent: true);
        break;
      case _LocalModelsTab.market:
        _refreshMarket(silent: true);
        break;
    }
  }

  Future<void> _refreshConfig({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingConfig = true);
    }
    try {
      final config = await MnnLocalModelsService.getConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loadingConfig = false;
      });
      _syncConfigControllers(config);
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        showToast('加载本地模型配置失败', type: ToastType.error);
      }
      setState(() => _loadingConfig = false);
    }
  }

  Future<void> _refreshInstalled({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingInstalled = true);
    }
    try {
      final models = await MnnLocalModelsService.listInstalledModels();
      if (!mounted) return;
      setState(() {
        _installedModels = models;
        _loadingInstalled = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        showToast('加载已安装模型失败', type: ToastType.error);
      }
      setState(() => _loadingInstalled = false);
    }
  }

  Future<void> _refreshMarket({
    bool silent = false,
    bool refresh = false,
  }) async {
    if (!silent && mounted) {
      setState(() => _loadingMarket = true);
    }
    try {
      final payload = await MnnLocalModelsService.listMarketModels(
        query: _marketSearchController.text.trim(),
        category: 'llm',
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _marketModels = payload.models;
        _loadingMarket = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        showToast('加载模型市场失败', type: ToastType.error);
      }
      setState(() => _loadingMarket = false);
    }
  }

  void _handleEvent(MnnLocalEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'download_update':
        final modelId = (event.payload['modelId'] ?? '').toString();
        final rawDownload = event.payload['download'];
        final download = rawDownload is Map
            ? MnnLocalDownloadInfo.fromMap(rawDownload)
            : null;
        _updateMarketDownloadState(modelId, download);
        if (download?.isCompleted == true) {
          _refreshInstalled(silent: true);
        }
        break;
      case 'downloads_changed':
        _refreshInstalled(silent: true);
        _refreshMarket(silent: true);
        break;
      case 'config_changed':
        final configPayload = event.payload['config'];
        if (configPayload is Map) {
          final config = MnnLocalConfig.fromMap(configPayload);
          setState(() => _config = config);
          _syncConfigControllers(config);
        } else {
          _refreshConfig(silent: true);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _switchInferenceBackend(String backend) async {
    try {
      await MnnLocalModelsService.setBackend(backend);
      if (!mounted) return;
      setState(() {
        _loadingConfig = true;
        _loadingInstalled = true;
        _loadingMarket = true;
      });
      await _bootstrap();
    } catch (_) {
      if (!mounted) return;
      showToast('切换推理后端失败', type: ToastType.error);
    }
  }

  Future<void> _setActiveModel(String? modelId) async {
    try {
      final config = await MnnLocalModelsService.setActiveModel(modelId);
      if (!mounted) return;
      setState(() => _config = config);
      _refreshInstalled(silent: true);
      showToast('已更新当前模型');
    } catch (_) {
      showToast('设置当前模型失败', type: ToastType.error);
    }
  }

  Future<void> _savePortConfig({bool silent = false}) async {
    final text = _portController.text.trim();
    final port = int.tryParse(text);
    if (port == null || port <= 0) {
      if (!silent) {
        showToast('端口号无效', type: ToastType.error);
      }
      if (_config != null) {
        _syncConfigControllers(_config!);
      }
      return;
    }
    try {
      final config = await MnnLocalModelsService.saveConfig(apiPort: port);
      if (!mounted) return;
      setState(() => _config = config);
      _syncConfigControllers(config);
      if (!silent) {
        showToast('已更新服务端口');
      }
    } catch (_) {
      if (!silent) {
        showToast('保存端口失败', type: ToastType.error);
      }
    }
  }

  void _schedulePortSave() {
    _configSaveDebounce?.cancel();
    _configSaveDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _savePortConfig(silent: true),
    );
  }

  Future<void> _toggleAutoStart(bool value) async {
    try {
      final config = await MnnLocalModelsService.saveConfig(
        autoStartOnAppOpen: value,
      );
      if (!mounted) return;
      setState(() => _config = config);
    } catch (_) {
      showToast('保存自动预热设置失败', type: ToastType.error);
    }
  }

  Future<void> _changeDownloadProvider(String value) async {
    try {
      final config = await MnnLocalModelsService.saveConfig(
        downloadProvider: value,
      );
      if (!mounted) return;
      setState(() => _config = config);
      _refreshMarket(silent: true);
    } catch (_) {
      showToast('切换下载源失败', type: ToastType.error);
    }
  }

  Future<void> _toggleApiService(bool enable) async {
    final config = _config;
    if (config == null || _togglingApiService) {
      return;
    }
    setState(() => _togglingApiService = true);
    try {
      final nextConfig = enable
          ? await MnnLocalModelsService.startApiService(
              modelId: config.activeModelId.isEmpty ? null : config.activeModelId,
            )
          : await MnnLocalModelsService.stopApiService();
      if (!mounted) return;
      setState(() => _config = nextConfig);
      _refreshInstalled(silent: true);
      showToast(enable ? '本地服务已启动' : '本地服务已停止');
    } catch (_) {
      if (mounted) {
        showToast(enable ? '启动服务失败' : '停止服务失败', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _togglingApiService = false);
      }
    }
  }
  void _updateMarketDownloadState(
    String modelId,
    MnnLocalDownloadInfo? download,
  ) {
    if (modelId.isEmpty || !mounted) {
      return;
    }
    final targetIndex = _marketModels.indexWhere((item) => item.id == modelId);
    if (targetIndex < 0) {
      return;
    }
    final current = _marketModels[targetIndex];
    final updated = MnnLocalModel(
      id: current.id,
      name: current.name,
      category: current.category,
      source: current.source,
      description: current.description,
      path: current.path,
      vendor: current.vendor,
      tags: current.tags,
      extraTags: current.extraTags,
      active: current.active,
      isLocal: current.isLocal,
      isPinned: current.isPinned,
      hasUpdate: current.hasUpdate,
      fileSize: current.fileSize,
      sizeB: current.sizeB,
      formattedSize: current.formattedSize,
      lastUsedAt: current.lastUsedAt,
      downloadedAt: current.downloadedAt,
      readOnly: current.readOnly,
      download: download,
    );
    setState(() {
      _marketModels = List<MnnLocalModel>.from(_marketModels)
        ..[targetIndex] = updated;
    });
  }

  MnnLocalDownloadInfo _downloadPlaceholder({
    required String stateLabel,
    double progress = 0,
    String progressStage = '',
  }) {
    return MnnLocalDownloadInfo(
      state: 0,
      stateLabel: stateLabel,
      progress: progress,
      savedSize: 0,
      totalSize: 0,
      speedInfo: '',
      errorMessage: '',
      progressStage: progressStage,
      currentFile: '',
      hasUpdate: false,
    );
  }

  String _downloadStatusLabel(MnnLocalDownloadInfo download) {
    switch (download.stateLabel) {
      case 'preparing':
        return '准备中';
      case 'downloading':
        return download.progressStage.trim().isNotEmpty
            ? download.progressStage.trim()
            : '下载中';
      case 'paused':
        return '已暂停';
      case 'completed':
        return '已完成';
      case 'failed':
        return '下载失败';
      case 'cancelled':
        return '已取消';
      default:
        return '未下载';
    }
  }

  String _apiServiceStateLabel(MnnLocalConfig config) {
    if (config.apiReady) {
      return 'READY';
    }
    switch (config.apiState.trim().toLowerCase()) {
      case 'running':
        return '运行中';
      case 'starting':
        return '启动中';
      case 'failed':
        return '启动失败';
      default:
        return '已停止';
    }
  }

  Color _apiServiceStateBackgroundColor(MnnLocalConfig config) {
    if (config.apiReady) {
      return const Color(0xFFE8F5E9);
    }
    switch (config.apiState.trim().toLowerCase()) {
      case 'running':
        return const Color(0xFFE3F2FD);
      case 'starting':
        return const Color(0xFFFFF4E5);
      case 'failed':
        return const Color(0xFFFDECEC);
      default:
        return const Color(0xFFF2F4F7);
    }
  }

  Color _apiServiceStateTextColor(MnnLocalConfig config) {
    if (config.apiReady) {
      return const Color(0xFF2E7D32);
    }
    switch (config.apiState.trim().toLowerCase()) {
      case 'running':
        return const Color(0xFF1565C0);
      case 'starting':
        return const Color(0xFFB26A00);
      case 'failed':
        return const Color(0xFFB42318);
      default:
        return AppColors.text70;
    }
  }

  Widget _buildApiServiceStateTag(MnnLocalConfig config) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _apiServiceStateBackgroundColor(config),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _apiServiceStateLabel(config),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _apiServiceStateTextColor(config),
        ),
      ),
    );
  }

  Widget _buildBackendDropdown({required String backend}) {
    return DropdownButtonFormField<String>(
      key: ValueKey('backend-$backend'),
      initialValue: backend,
      decoration: const InputDecoration(
        labelText: '推理后端',
        helperText: 'llama.cpp 使用 .gguf，omniinfer-mnn 使用目录内 config.json。',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(
          value: _llamaCppBackend,
          child: Text('llama.cpp (.gguf)'),
        ),
        DropdownMenuItem(
          value: _omniinferMnnBackend,
          child: Text('omniinfer-mnn'),
        ),
      ],
      onChanged: (value) async {
        if (value == null || value == backend) return;
        await _switchInferenceBackend(value);
      },
    );
  }

  Widget _buildServiceTab() {
    if (_loadingConfig && _config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final config = _config;
    if (config == null) {
      return _buildEmptyState(
        title: '无法加载本地模型配置',
        subtitle: '请稍后重试。',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _refreshConfig(silent: true),
          _refreshInstalled(silent: true),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildInfoCard(
            title: '服务',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackendDropdown(backend: config.backend),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildApiServiceStateTag(config),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        config.baseUrl,
                        style: const TextStyle(color: AppColors.text70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '共享端口：同一时间只会有一个 OmniInfer 本地服务实例，切换后端不会改变监听端口。',
                  style: const TextStyle(color: AppColors.text50, height: 1.5),
                ),
                const SizedBox(height: 8),
                Text(
                  '固定行为：仅监听 127.0.0.1，当前不校验 API Key。',
                  style: const TextStyle(color: AppColors.text50, height: 1.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _schedulePortSave(),
                  onSubmitted: (_) => _savePortConfig(),
                  decoration: const InputDecoration(
                    labelText: '服务端口',
                    border: OutlineInputBorder(),
                    helperText: '修改后会影响内置 OmniInfer provider 的本地 base URL。',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: config.autoStartOnAppOpen,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('打开 App 时自动预热'),
                  subtitle: const Text('只会尝试预热当前选中的后端与其当前模型。'),
                  onChanged: _toggleAutoStart,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'active-model-${config.backend}-${config.activeModelId}',
                  ),
                  initialValue: config.activeModelId.isNotEmpty &&
                          _serviceModels.any((item) => item.id == config.activeModelId)
                      ? config.activeModelId
                      : null,
                  decoration: const InputDecoration(
                    labelText: '当前模型',
                    helperText: '启动服务时会加载这里选择的模型。',
                    border: OutlineInputBorder(),
                  ),
                  items: _serviceModels
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: _serviceModels.isEmpty ? null : _setActiveModel,
                ),
                const SizedBox(height: 12),
                if (config.loadedModelId.isNotEmpty) ...[
                  Text(
                    '当前已加载：${_backendLabel(config.loadedBackend)} / ${config.loadedModelId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text70,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _togglingApiService ||
                                (config.activeModelId.isEmpty && _serviceModels.isEmpty)
                            ? null
                            : () => _toggleApiService(true),
                        child: Text(
                          _togglingApiService && !config.apiRunning ? '启动中…' : '启动服务',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _togglingApiService || !config.apiRunning
                            ? null
                            : () => _toggleApiService(false),
                        child: Text(
                          _togglingApiService && config.apiRunning ? '停止中…' : '停止服务',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSearchBar(
            controller: _installedSearchController,
            hint: '搜索已安装模型',
            onSubmitted: (_) => setState(() {}),
            onRefresh: () => _refreshInstalled(),
            compact: true,
          ),
          const SizedBox(height: 12),
          if (_loadingInstalled && _installedModels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredInstalledModels.isEmpty)
            _buildEmptyState(
              title: '还没有可用的本地模型',
              subtitle: '先去模型市场下载一个模型，或者手动放置 MNN 模型目录。',
            )
          else
            ..._filteredInstalledModels.map(_buildInstalledCard),
        ],
      ),
    );
  }
  Widget _buildMarketTab() {
    final config = _config;
    return RefreshIndicator(
      onRefresh: () => _refreshMarket(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildInfoCard(
            title: '模型市场',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackendDropdown(
                  backend: config?.backend ?? _llamaCppBackend,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'download-provider-${config?.downloadProvider ?? 'ModelScope'}',
                  ),
                  initialValue: config?.downloadProvider.isNotEmpty == true
                      ? config!.downloadProvider
                      : null,
                  decoration: const InputDecoration(
                    labelText: '下载源',
                    border: OutlineInputBorder(),
                    helperText: 'MNN 市场会按当前下载源生成带前缀的 modelId。',
                  ),
                  items: (config?.availableSources ?? const <String>[])
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _changeDownloadProvider(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSearchBar(
            controller: _marketSearchController,
            hint: '搜索模型市场',
            onSubmitted: (_) => _refreshMarket(),
            onRefresh: () => _refreshMarket(refresh: true),
            compact: true,
          ),
          const SizedBox(height: 12),
          if (_loadingMarket && _marketModels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_marketModels.isEmpty)
            _buildEmptyState(
              title: '模型市场暂时为空',
              subtitle: '请检查下载源，或者下拉刷新重试。',
            )
          else
            ..._marketModels.map(_buildMarketCard),
        ],
      ),
    );
  }

  Widget _buildInstalledCard(MnnLocalModel model) {
    final modelSizeText = _resolvedModelSizeText(model);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (model.active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '当前使用',
                      style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(model.category.toUpperCase()),
                if (model.source.isNotEmpty) _buildTag(model.source),
                for (final tag in model.tags.take(4)) _buildTag(tag),
              ],
            ),
            if (modelSizeText != null) ...[
              const SizedBox(height: 8),
              Text(
                '文件大小：$modelSizeText',
                style: const TextStyle(fontSize: 12, color: AppColors.text50),
              ),
            ],
            if (model.path.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                model.path,
                style: const TextStyle(fontSize: 12, color: AppColors.text50),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.readOnly
                        ? '这是手动放置目录，App 内不提供删除。'
                        : '该模型可由 OmniInfer 直接加载。',
                    style: TextStyle(
                      fontSize: 12,
                      color: model.readOnly
                          ? const Color(0xFFB26A00)
                          : AppColors.text50,
                    ),
                  ),
                ),
                if (!model.readOnly)
                  IconButton(
                    tooltip: '删除模型',
                    onPressed: () async {
                      await MnnLocalModelsService.deleteModel(model.id);
                      _refreshInstalled(silent: true);
                      _refreshMarket(silent: true);
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFB42318),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketCard(MnnLocalModel model) {
    final download = model.download;
    final isCompleted = download?.isCompleted == true;
    final isDownloading = download?.isDownloading == true;
    final isPaused = download?.isPaused == true;
    final modelSizeText = _resolvedModelSizeText(model);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (download != null)
                  Text(
                    _downloadStatusLabel(download),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text50,
                    ),
                  ),
              ],
            ),
            if (model.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                model.description,
                style: const TextStyle(color: AppColors.text70, height: 1.5),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(model.category.toUpperCase()),
                if (model.source.isNotEmpty) _buildTag(model.source),
                for (final tag in model.tags.take(4)) _buildTag(tag),
              ],
            ),
            if (modelSizeText != null) ...[
              const SizedBox(height: 8),
              Text(
                '文件大小：$modelSizeText',
                style: const TextStyle(fontSize: 12, color: AppColors.text50),
              ),
            ],
            if (download != null && (isDownloading || isPaused))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: download.progress),
                    const SizedBox(height: 8),
                    Text(
                      '${(download.progress * 100).toStringAsFixed(1)}% ${download.speedInfo}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text50,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isCompleted && !isDownloading)
                  FilledButton(
                    onPressed: () async {
                      _updateMarketDownloadState(
                        model.id,
                        _downloadPlaceholder(
                          stateLabel: 'preparing',
                          progress: download?.progress ?? 0,
                          progressStage: download?.progressStage ?? '',
                        ),
                      );
                      try {
                        await MnnLocalModelsService.startDownload(model.id);
                        _refreshMarket(silent: true);
                      } catch (_) {
                        _refreshMarket(silent: true);
                        showToast('启动下载失败', type: ToastType.error);
                      }
                    },
                    child: Text(isPaused ? '继续下载' : '下载'),
                  ),
                if (isDownloading)
                  OutlinedButton(
                    onPressed: () async {
                      _updateMarketDownloadState(
                        model.id,
                        _downloadPlaceholder(
                          stateLabel: 'paused',
                          progress: download?.progress ?? 0,
                          progressStage: download?.progressStage ?? '',
                        ),
                      );
                      try {
                        await MnnLocalModelsService.pauseDownload(model.id);
                        _refreshMarket(silent: true);
                      } catch (_) {
                        _refreshMarket(silent: true);
                        showToast('暂停下载失败', type: ToastType.error);
                      }
                    },
                    child: const Text('暂停'),
                  ),
                if (isCompleted)
                  FilledButton.tonal(
                    onPressed: () async {
                      await MnnLocalModelsService.deleteModel(model.id);
                      _refreshMarket(silent: true);
                      _refreshInstalled(silent: true);
                    },
                    child: Text(model.hasUpdate ? '删除旧版本' : '删除'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onSubmitted,
    required VoidCallback onRefresh,
    bool compact = false,
  }) {
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          controller.clear();
                          onSubmitted('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
  Widget _buildTag(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 12, color: AppColors.text70),
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.offline_bolt_outlined,
              size: 44,
              color: AppColors.text50,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6, color: AppColors.text50),
            ),
          ],
        ),
      ),
    );
  }

  String _backendLabel(String backend) {
    switch (backend) {
      case _omniinferMnnBackend:
        return 'omniinfer-mnn';
      case _llamaCppBackend:
      default:
        return 'llama.cpp';
    }
  }

  String? _resolvedModelSizeText(MnnLocalModel model) {
    final formatted = model.formattedSize.trim();
    if (formatted.isNotEmpty) {
      return formatted;
    }
    final bytes = model.fileSize > 0
        ? model.fileSize.toDouble()
        : model.download?.totalSize.toDouble() ?? 0;
    if (bytes <= 0) {
      return null;
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes;
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    final fractionDigits = size >= 100 || unitIndex == 0 ? 0 : 1;
    return '${size.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      appBar: const CommonAppBar(title: '本地模型', primary: true),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '服务'),
                Tab(text: '模型市场'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildServiceTab(),
                _buildMarketTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
