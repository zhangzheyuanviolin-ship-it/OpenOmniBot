import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/services/mnn_local_models_service.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/theme/omni_theme_palette.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

enum _LocalModelsTab { service, market }

enum _AccentTone { neutral, accent, success, info, warning, danger }

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

  OmniThemePalette get _palette => context.omniPalette;
  bool get _isDarkTheme => context.isDarkTheme;
  Color get _cardColor =>
      _blend(_palette.surfacePrimary, _palette.surfaceSecondary, 0.16);
  Color get _panelColor =>
      _blend(_palette.surfaceSecondary, _palette.surfaceElevated, 0.34);
  Color get _highlightPanelColor =>
      _blend(_palette.surfacePrimary, _palette.accentPrimary, 0.08);
  Color get _borderColor => _palette.borderSubtle;
  Color get _strongBorderColor =>
      _blend(_palette.borderStrong, _palette.accentPrimary, 0.18);
  Color get _primaryTextColor => _palette.textPrimary;
  Color get _secondaryTextColor => _palette.textSecondary;
  Color get _tertiaryTextColor => _palette.textTertiary;
  Color get _tagSurfaceColor =>
      _blend(_palette.surfaceSecondary, _palette.surfacePrimary, 0.34);
  LinearGradient get _pageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      _blend(_palette.pageBackground, _palette.accentPrimary, 0.1),
      _palette.pageBackground,
      _blend(_palette.pageBackground, _palette.surfaceSecondary, 0.55),
    ],
  );
  List<BoxShadow> get _cardShadow => const [];

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
    final normalizedQuery = _installedSearchController.text
        .trim()
        .toLowerCase();
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

  List<MnnLocalModel> get _sortedMarketModels {
    final sorted = List<MnnLocalModel>.from(_marketModels);
    sorted.sort((a, b) {
      final sizeCompare = _modelSizeSortValue(
        a,
      ).compareTo(_modelSizeSortValue(b));
      if (sizeCompare != 0) {
        return sizeCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

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
              modelId: config.activeModelId.isEmpty
                  ? null
                  : config.activeModelId,
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
      return '已就绪';
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

  Color _blend(Color first, Color second, double t) {
    return Color.lerp(first, second, t.clamp(0.0, 1.0))!;
  }

  Color _alpha(Color color, double opacity) {
    final safe = opacity.clamp(0.0, 1.0);
    return color.withAlpha((safe * 255).round());
  }

  _AccentTone _apiServiceTone(MnnLocalConfig config) {
    if (config.apiReady) {
      return _AccentTone.success;
    }
    switch (config.apiState.trim().toLowerCase()) {
      case 'running':
        return _AccentTone.info;
      case 'starting':
        return _AccentTone.warning;
      case 'failed':
        return _AccentTone.danger;
      default:
        return _AccentTone.neutral;
    }
  }

  Color _toneBaseColor(_AccentTone tone) {
    switch (tone) {
      case _AccentTone.accent:
        return _palette.accentPrimary;
      case _AccentTone.success:
        return const Color(0xFF3FA66C);
      case _AccentTone.info:
        return const Color(0xFF4C8DFF);
      case _AccentTone.warning:
        return const Color(0xFFD69A41);
      case _AccentTone.danger:
        return const Color(0xFFD86473);
      case _AccentTone.neutral:
        return _secondaryTextColor;
    }
  }

  Color _toneBackgroundColor(_AccentTone tone) {
    return _blend(
      _panelColor,
      _toneBaseColor(tone),
      _isDarkTheme ? 0.28 : 0.14,
    );
  }

  Color _toneBorderColor(_AccentTone tone) {
    return _blend(
      _borderColor,
      _toneBaseColor(tone),
      _isDarkTheme ? 0.58 : 0.36,
    );
  }

  Color _toneTextColor(_AccentTone tone) {
    return _blend(
      _primaryTextColor,
      _toneBaseColor(tone),
      _isDarkTheme ? 0.52 : 0.72,
    );
  }

  Color _buttonForegroundColor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111315);
  }

  Widget _buildApiServiceStateTag(MnnLocalConfig config) {
    final tone = _apiServiceTone(config);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _toneBackgroundColor(tone),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _toneBorderColor(tone)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            config.apiReady
                ? Icons.check_circle_rounded
                : config.apiRunning
                ? Icons.radar_rounded
                : Icons.power_settings_new_rounded,
            size: 14,
            color: _toneTextColor(tone),
          ),
          const SizedBox(width: 6),
          Text(
            _apiServiceStateLabel(config),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _toneTextColor(tone),
              fontFamily: AppTextStyles.fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  String _displayModelName(String modelId) {
    final normalized = modelId.trim();
    if (normalized.isEmpty) {
      return '';
    }
    for (final model in [..._installedModels, ..._marketModels]) {
      if (model.id == normalized) {
        return model.name.trim().isEmpty ? normalized : model.name;
      }
    }
    return normalized;
  }

  String _shortLabel(
    String value, {
    String fallback = '-',
    int maxLength = 18,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}…';
  }

  String _modelSubtitle(MnnLocalModel model) {
    final parts = <String>[];
    if (model.vendor.trim().isNotEmpty) {
      parts.add(model.vendor.trim());
    }
    if (model.id.trim().isNotEmpty) {
      parts.add(model.id.trim());
    }
    if (parts.isEmpty) {
      return '本地推理模型';
    }
    return parts.join('  ·  ');
  }

  ButtonStyle _filledButtonStyle({required _AccentTone tone}) {
    final background = tone == _AccentTone.accent
        ? _blend(_palette.accentPrimary, _cardColor, _isDarkTheme ? 0.08 : 0.0)
        : _toneBaseColor(tone);
    return FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: _buttonForegroundColor(background),
      disabledBackgroundColor: _alpha(
        _secondaryTextColor,
        _isDarkTheme ? 0.18 : 0.1,
      ),
      disabledForegroundColor: _tertiaryTextColor,
      elevation: 0,
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: AppTextStyles.fontFamily,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  ButtonStyle _softButtonStyle({required _AccentTone tone}) {
    return FilledButton.styleFrom(
      backgroundColor: _toneBackgroundColor(tone),
      foregroundColor: _toneTextColor(tone),
      disabledBackgroundColor: _alpha(
        _secondaryTextColor,
        _isDarkTheme ? 0.18 : 0.1,
      ),
      disabledForegroundColor: _tertiaryTextColor,
      elevation: 0,
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: AppTextStyles.fontFamily,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  ButtonStyle _outlinedButtonStyle({required _AccentTone tone}) {
    return OutlinedButton.styleFrom(
      foregroundColor: _toneTextColor(tone),
      disabledForegroundColor: _tertiaryTextColor,
      side: BorderSide(color: _toneBorderColor(tone)),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: AppTextStyles.fontFamily,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? helper,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      filled: true,
      fillColor: _panelColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: _strongBorderColor, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      helperStyle: TextStyle(
        color: _secondaryTextColor,
        height: 1.45,
        fontFamily: AppTextStyles.fontFamily,
      ),
      labelStyle: TextStyle(
        color: _secondaryTextColor,
        fontWeight: FontWeight.w600,
        fontFamily: AppTextStyles.fontFamily,
      ),
      hintStyle: TextStyle(
        color: _tertiaryTextColor,
        fontWeight: FontWeight.w500,
        fontFamily: AppTextStyles.fontFamily,
      ),
    );
  }

  Widget _buildBackendDropdown({required String backend}) {
    return DropdownButtonFormField<String>(
      key: ValueKey('backend-$backend'),
      initialValue: backend,
      decoration: _fieldDecoration(
        label: '推理后端',
        icon: Icons.settings_input_component_rounded,
      ),
      dropdownColor: _cardColor,
      borderRadius: BorderRadius.circular(20),
      style: TextStyle(
        color: _primaryTextColor,
        fontWeight: FontWeight.w600,
        fontFamily: AppTextStyles.fontFamily,
      ),
      items: const [
        DropdownMenuItem(
          value: _llamaCppBackend,
          child: Text('OmniInfer-llama'),
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
      return _buildEmptyState(title: '无法加载本地模型配置', subtitle: '请稍后重试。');
    }
    return RefreshIndicator(
      color: _palette.accentPrimary,
      backgroundColor: _cardColor,
      onRefresh: () async {
        await Future.wait([
          _refreshConfig(silent: true),
          _refreshInstalled(silent: true),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildHeroCard(
            title: '本地模型服务',
            subtitle: '把设备上的模型整理成一个稳定、可切换、可暴露本地接口的推理控制台。',
            trailing: _buildApiServiceStateTag(config),
            badges: [
              '后端 ${_backendLabel(config.backend)}',
              '已安装 ${_serviceModels.length}',
              config.activeModelId.isEmpty
                  ? '未选择默认模型'
                  : '默认 ${_shortLabel(_displayModelName(config.activeModelId), fallback: '已选择')}',
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: '服务控制',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackendDropdown(backend: config.backend),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'active-model-${config.backend}-${config.activeModelId}',
                  ),
                  initialValue:
                      config.activeModelId.isNotEmpty &&
                          _serviceModels.any(
                            (item) => item.id == config.activeModelId,
                          )
                      ? config.activeModelId
                      : null,
                  decoration: _fieldDecoration(
                    label: '当前模型',
                    helper: '启动服务时会加载这里选择的模型。',
                    icon: Icons.memory_rounded,
                  ),
                  dropdownColor: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppTextStyles.fontFamily,
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
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    setState(() {});
                    _schedulePortSave();
                  },
                  onSubmitted: (_) => _savePortConfig(),
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppTextStyles.fontFamily,
                  ),
                  decoration: _fieldDecoration(
                    label: '服务端口',
                    icon: Icons.settings_ethernet_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '共享端口：同一时间只会有一个 OmniInfer 本地服务实例，切换后端不会改变监听端口。',
                  style: TextStyle(
                    color: _secondaryTextColor,
                    height: 1.55,
                    fontFamily: AppTextStyles.fontFamily,
                  ),
                ),
                const SizedBox(height: 12),
                if (config.loadedModelId.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _toneBackgroundColor(_AccentTone.success),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _toneBorderColor(_AccentTone.success),
                      ),
                    ),
                    child: Text(
                      '当前已加载：${_backendLabel(config.loadedBackend)} / ${_displayModelName(config.loadedModelId)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _toneTextColor(_AccentTone.success),
                        fontFamily: AppTextStyles.fontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _togglingApiService ||
                                (config.activeModelId.isEmpty &&
                                    _serviceModels.isEmpty)
                            ? null
                            : () => _toggleApiService(true),
                        style: _filledButtonStyle(tone: _AccentTone.accent),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          _togglingApiService && !config.apiRunning
                              ? '启动中…'
                              : '启动服务',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _togglingApiService || !config.apiRunning
                            ? null
                            : () => _toggleApiService(false),
                        style: _outlinedButtonStyle(tone: _AccentTone.danger),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: Text(
                          _togglingApiService && config.apiRunning
                              ? '停止中…'
                              : '停止服务',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: '自动预热',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _panelColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '打开 App 时自动预热',
                          style: TextStyle(
                            color: _primaryTextColor,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '打开 App 后自动启动本地服务并加载当前模型。',
                          style: TextStyle(
                            color: _secondaryTextColor,
                            height: 1.5,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch.adaptive(
                    value: config.autoStartOnAppOpen,
                    onChanged: _toggleAutoStart,
                    activeThumbColor: Colors.white,
                    activeTrackColor: _palette.accentPrimary,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: _alpha(_secondaryTextColor, 0.28),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: '已安装模型',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(
                  controller: _installedSearchController,
                  onSubmitted: (_) => setState(() {}),
                  onRefresh: () => _refreshInstalled(),
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
          ),
        ],
      ),
    );
  }

  Widget _buildMarketTab() {
    final config = _config;
    return RefreshIndicator(
      color: _palette.accentPrimary,
      backgroundColor: _cardColor,
      onRefresh: () => _refreshMarket(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildHeroCard(
            title: '模型市场',
            subtitle: '按当前推理后端浏览可下载模型，统一管理下载源。',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _toneBackgroundColor(_AccentTone.accent),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _toneBorderColor(_AccentTone.accent)),
              ),
              child: Text(
                config?.downloadProvider ?? '同步中',
                style: TextStyle(
                  color: _toneTextColor(_AccentTone.accent),
                  fontWeight: FontWeight.w700,
                  fontFamily: AppTextStyles.fontFamily,
                ),
              ),
            ),
            badges: [
              '在架 ${_marketModels.length}',
              '进行中 ${_marketModels.where((item) => item.download?.isDownloading == true).length}',
              '来源 ${(config?.availableSources ?? const <String>[]).length}',
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: '筛选与来源',
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
                  decoration: _fieldDecoration(
                    label: '下载源',
                    icon: Icons.public_rounded,
                  ),
                  dropdownColor: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppTextStyles.fontFamily,
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
          _buildInfoCard(
            title: '市场模型',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(
                  controller: _marketSearchController,
                  onSubmitted: (_) => _refreshMarket(),
                  onRefresh: () => _refreshMarket(refresh: true),
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
                  ..._sortedMarketModels.map(_buildMarketCard),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledCard(MnnLocalModel model) {
    final modelSizeText = _resolvedModelSizeText(model);
    final isLoaded = _config?.loadedModelId == model.id;
    final outlineTone = model.active
        ? _AccentTone.accent
        : (isLoaded ? _AccentTone.success : _AccentTone.neutral);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _blend(_cardColor, _toneBaseColor(outlineTone), 0.08),
            _blend(_cardColor, _panelColor, 0.52),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _toneBorderColor(outlineTone)),
        boxShadow: _cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _primaryTextColor,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _modelSubtitle(model),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryTextColor,
                          fontWeight: FontWeight.w500,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                if (model.active || isLoaded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _toneBackgroundColor(
                        model.active ? _AccentTone.accent : _AccentTone.success,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _toneBorderColor(
                          model.active
                              ? _AccentTone.accent
                              : _AccentTone.success,
                        ),
                      ),
                    ),
                    child: Text(
                      model.active ? '当前默认' : '已加载',
                      style: TextStyle(
                        fontSize: 12,
                        color: _toneTextColor(
                          model.active
                              ? _AccentTone.accent
                              : _AccentTone.success,
                        ),
                        fontWeight: FontWeight.w700,
                        fontFamily: AppTextStyles.fontFamily,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(model.category.toUpperCase()),
                if (model.source.isNotEmpty) _buildTag(model.source),
                if (model.vendor.isNotEmpty) _buildTag(model.vendor),
                for (final tag in model.tags.take(4)) _buildTag(tag),
              ],
            ),
            if (modelSizeText != null || model.path.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (modelSizeText != null)
                      Text(
                        '文件大小  $modelSizeText',
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryTextColor,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                    if (model.path.isNotEmpty) ...[
                      if (modelSizeText != null) const SizedBox(height: 8),
                      Text(
                        model.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _tertiaryTextColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              model.readOnly ? '这是手动放置目录，App 内不提供删除。' : '该模型可由 OmniInfer 直接加载。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: model.readOnly
                    ? _toneTextColor(_AccentTone.warning)
                    : _secondaryTextColor,
                fontFamily: AppTextStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!model.active)
                  FilledButton.icon(
                    onPressed: () => _setActiveModel(model.id),
                    style: _softButtonStyle(tone: _AccentTone.accent),
                    icon: const Icon(
                      Icons.playlist_add_check_circle_rounded,
                      size: 18,
                    ),
                    label: const Text('设为当前'),
                  ),
                if (!model.readOnly)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await MnnLocalModelsService.deleteModel(model.id);
                      _refreshInstalled(silent: true);
                      _refreshMarket(silent: true);
                    },
                    style: _outlinedButtonStyle(tone: _AccentTone.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('删除'),
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
    final isFailed = download?.stateLabel == 'failed';
    final modelSizeText = _resolvedModelSizeText(model);
    final tone = isCompleted
        ? _AccentTone.success
        : isDownloading
        ? _AccentTone.info
        : isPaused
        ? _AccentTone.warning
        : isFailed
        ? _AccentTone.danger
        : _AccentTone.neutral;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _blend(_cardColor, _toneBaseColor(tone), 0.08),
            _blend(_cardColor, _panelColor, 0.56),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _toneBorderColor(tone)),
        boxShadow: _cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _primaryTextColor,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                      if (model.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          model.description,
                          style: TextStyle(
                            color: _secondaryTextColor,
                            height: 1.5,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (download != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _toneBackgroundColor(tone),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _toneBorderColor(tone)),
                    ),
                    child: Text(
                      _downloadStatusLabel(download),
                      style: TextStyle(
                        fontSize: 12,
                        color: _toneTextColor(tone),
                        fontWeight: FontWeight.w700,
                        fontFamily: AppTextStyles.fontFamily,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(model.category.toUpperCase()),
                if (model.source.isNotEmpty) _buildTag(model.source),
                if (model.vendor.isNotEmpty) _buildTag(model.vendor),
                if (model.hasUpdate) _buildTag('有更新'),
                for (final tag in model.tags.take(4)) _buildTag(tag),
              ],
            ),
            if (modelSizeText != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _panelColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _borderColor),
                ),
                child: Text(
                  '文件大小  $modelSizeText',
                  style: TextStyle(
                    fontSize: 12,
                    color: _secondaryTextColor,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppTextStyles.fontFamily,
                  ),
                ),
              ),
            ],
            if (download != null && (isDownloading || isPaused || isFailed))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _panelColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _toneBorderColor(tone)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: download.progress,
                          minHeight: 8,
                          backgroundColor: _alpha(_secondaryTextColor, 0.14),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _toneBaseColor(
                              tone == _AccentTone.neutral
                                  ? _AccentTone.info
                                  : tone,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${(download.progress * 100).toStringAsFixed(1)}%  ${download.speedInfo}'
                            .trim(),
                        style: TextStyle(
                          fontSize: 12,
                          color: _secondaryTextColor,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                      if (download.progressStage.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          download.progressStage.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            color: _secondaryTextColor,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                      ],
                      if (isFailed &&
                          download.errorMessage.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          download.errorMessage.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            color: _toneTextColor(_AccentTone.danger),
                            fontWeight: FontWeight.w700,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!isCompleted && !isDownloading)
                  FilledButton.icon(
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
                    style: _filledButtonStyle(tone: _AccentTone.accent),
                    icon: Icon(
                      isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.download_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isPaused
                          ? '继续下载'
                          : isFailed
                          ? '重新下载'
                          : '下载模型',
                    ),
                  ),
                if (isDownloading)
                  OutlinedButton.icon(
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
                    style: _outlinedButtonStyle(tone: _AccentTone.warning),
                    icon: const Icon(Icons.pause_rounded, size: 18),
                    label: const Text('暂停'),
                  ),
                if (isCompleted)
                  FilledButton.icon(
                    onPressed: () async {
                      await MnnLocalModelsService.deleteModel(model.id);
                      _refreshMarket(silent: true);
                      _refreshInstalled(silent: true);
                    },
                    style: _softButtonStyle(
                      tone: model.hasUpdate
                          ? _AccentTone.warning
                          : _AccentTone.neutral,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(model.hasUpdate ? '删除旧版本' : '删除'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard({
    required String title,
    required String subtitle,
    required Widget trailing,
    required List<String> badges,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _blend(_highlightPanelColor, _palette.accentPrimary, 0.12),
            _blend(_cardColor, _panelColor, 0.42),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _strongBorderColor),
        boxShadow: _cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 28,
                          height: 1.1,
                          color: _primaryTextColor,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: _secondaryTextColor,
                          fontWeight: FontWeight.w500,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                trailing,
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: badges.map(_buildTag).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton({
    required _LocalModelsTab tab,
    required String title,
  }) {
    final selected = _tabController.index == tab.index;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        if (_tabController.index != tab.index) {
          _tabController.animateTo(tab.index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _blend(_highlightPanelColor, _palette.accentPrimary, 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _blend(_strongBorderColor, _palette.accentPrimary, 0.2)
                : Colors.transparent,
          ),
        ),
        child: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: selected ? _primaryTextColor : _secondaryTextColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontFamily: AppTextStyles.fontFamily,
          ),
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _alpha(_cardColor, 0.82),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _blend(_borderColor, _strongBorderColor, 0.28),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSegmentButton(
                      tab: _LocalModelsTab.service,
                      title: '服务',
                    ),
                    const SizedBox(width: 4),
                    _buildSegmentButton(
                      tab: _LocalModelsTab.market,
                      title: '市场',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar({
    required TextEditingController controller,
    required ValueChanged<String> onSubmitted,
    required VoidCallback onRefresh,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _borderColor),
        boxShadow: _cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: _secondaryTextColor),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: onSubmitted,
              style: TextStyle(
                fontSize: 14,
                color: _primaryTextColor,
                fontWeight: FontWeight.w600,
                fontFamily: AppTextStyles.fontFamily,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                controller.clear();
                setState(() {});
                onSubmitted('');
              },
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: _secondaryTextColor,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(width: 1, height: 18, color: _borderColor),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '刷新',
            onPressed: onRefresh,
            style: IconButton.styleFrom(
              minimumSize: const Size(34, 34),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              foregroundColor: _primaryTextColor,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_cardColor, _blend(_cardColor, _panelColor, 0.48)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _primaryTextColor,
              fontFamily: AppTextStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildTag(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _tagSurfaceColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _borderColor),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 12,
          color: _secondaryTextColor,
          fontWeight: FontWeight.w600,
          fontFamily: AppTextStyles.fontFamily,
        ),
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _panelColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                Icons.offline_bolt_outlined,
                size: 28,
                color: _tertiaryTextColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _primaryTextColor,
                fontFamily: AppTextStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.6,
                color: _secondaryTextColor,
                fontFamily: AppTextStyles.fontFamily,
              ),
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
        return 'OmniInfer-llama';
    }
  }

  double _modelSizeSortValue(MnnLocalModel model) {
    if (model.sizeB > 0) {
      return model.sizeB;
    }
    if (model.fileSize > 0) {
      return model.fileSize.toDouble();
    }
    final totalSize = model.download?.totalSize.toDouble() ?? 0;
    if (totalSize > 0) {
      return totalSize;
    }
    return double.infinity;
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
      backgroundColor: _palette.pageBackground,
      appBar: CommonAppBar(
        title: '本地模型',
        height: 38,
        primary: true,
        backgroundColor: _palette.pageBackground,
        titleStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _primaryTextColor,
          fontFamily: AppTextStyles.fontFamily,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: _pageGradient),
        child: Column(
          children: [
            _buildTabSwitcher(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [_buildServiceTab(), _buildMarketTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
