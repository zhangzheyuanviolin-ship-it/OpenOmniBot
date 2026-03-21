import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

const String _kArrowBigDownSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M15 11a1 1 0 0 0 1 1h2.939a1 1 0 0 1 .75 1.811l-6.835 6.836a1.207 1.207 0 0 1-1.707 0L4.31 13.81a1 1 0 0 1 .75-1.811H8a1 1 0 0 0 1-1V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1z"/>
</svg>
''';

const String _kPlusSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M5 12h14"/>
  <path d="M12 5v14"/>
</svg>
''';

const String _kPackageSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z"/>
  <path d="M12 22V12"/>
  <polyline points="3.29 7 12 12 20.71 7"/>
  <path d="m7.5 4.27 9 5.15"/>
</svg>
''';

enum _ProviderModelSource { manual, remote }

class _ProviderModelItem {
  const _ProviderModelItem({required this.id, required this.source});

  final String id;
  final _ProviderModelSource source;

  String get sourceLabel {
    return source == _ProviderModelSource.manual ? '手动' : '自动';
  }
}

class VlmModelSettingPage extends StatefulWidget {
  const VlmModelSettingPage({super.key});

  @override
  State<VlmModelSettingPage> createState() => _VlmModelSettingPageState();
}

class _VlmModelSettingPageState extends State<VlmModelSettingPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  static const Duration _autoSaveDebounce = Duration(milliseconds: 600);
  static const double _modelDeleteExtentRatio = 0.24;
  static const double _modelDeleteIconSize = 18;
  static const BorderRadius _modelDeleteActionRadius = BorderRadius.only(
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
  );

  bool _isLoading = true;
  bool _isFetchingModels = false;
  bool _obscureApiKey = true;
  bool _isSyncingControllers = false;
  bool _isSavingConfig = false;
  bool _saveQueued = false;

  Timer? _autoSaveTimer;

  ModelProviderConfig _config = ModelProviderConfig.empty();
  List<ProviderModelOption> _remoteModels = const [];
  List<String> _manualModelIds = const [];
  Set<String> _deletingModelIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadData();
    _baseUrlController.addListener(_onConfigChanged);
    _apiKeyController.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_shouldAutoSaveDraft) {
      unawaited(_persistConfigDraft());
    }
    unawaited(_persistManualModelIds());
    _baseUrlController.removeListener(_onConfigChanged);
    _apiKeyController.removeListener(_onConfigChanged);
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  List<_ProviderModelItem> get _modelItems {
    final items = <_ProviderModelItem>[];
    final seen = <String>{};

    for (final modelId in _manualModelIds) {
      final normalized = modelId.trim();
      if (!ModelProviderConfigService.isValidModelName(normalized)) {
        continue;
      }
      if (seen.add(normalized)) {
        items.add(
          _ProviderModelItem(
            id: normalized,
            source: _ProviderModelSource.manual,
          ),
        );
      }
    }

    for (final model in _remoteModels) {
      final normalized = model.id.trim();
      if (!ModelProviderConfigService.isValidModelName(normalized)) {
        continue;
      }
      if (seen.add(normalized)) {
        items.add(
          _ProviderModelItem(
            id: normalized,
            source: _ProviderModelSource.remote,
          ),
        );
      }
    }

    return items;
  }

  void _onConfigChanged() {
    if (_isSyncingControllers || _isLoading) {
      return;
    }
    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    if (!_shouldAutoSaveDraft) {
      return;
    }
    _autoSaveTimer = Timer(_autoSaveDebounce, () {
      _autoSaveTimer = null;
      unawaited(_persistConfigDraft());
    });
  }

  bool get _shouldAutoSaveDraft {
    final normalizedBaseUrl = ModelProviderConfigService.normalizeApiBase(
      _baseUrlController.text,
    );
    if (normalizedBaseUrl == null) {
      return false;
    }
    return normalizedBaseUrl != _config.baseUrl ||
        _apiKeyController.text.trim() != _config.apiKey;
  }

  Future<void> _persistManualModelIds() async {
    try {
      await ModelProviderConfigService.saveManualModelIds(_manualModelIds);
    } catch (_) {
      // no-op
    }
  }

  Future<void> _persistConfigDraft() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    if (_isSavingConfig) {
      _saveQueued = true;
      return;
    }

    do {
      _saveQueued = false;
      final baseUrl = _baseUrlController.text.trim();
      final normalizedBaseUrl = ModelProviderConfigService.normalizeApiBase(
        baseUrl,
      );
      final apiKey = _apiKeyController.text.trim();

      if (normalizedBaseUrl == null) {
        return;
      }
      if (normalizedBaseUrl == _config.baseUrl && apiKey == _config.apiKey) {
        return;
      }

      _isSavingConfig = true;
      try {
        final config = await ModelProviderConfigService.saveConfig(
          baseUrl: baseUrl,
          apiKey: apiKey,
        );
        if (!mounted) return;

        final latestNormalizedBaseUrl =
            ModelProviderConfigService.normalizeApiBase(
              _baseUrlController.text,
            );
        final latestApiKey = _apiKeyController.text.trim();
        final draftChangedWhileSaving =
            latestNormalizedBaseUrl != normalizedBaseUrl ||
            latestApiKey != apiKey;

        if (draftChangedWhileSaving) {
          _saveQueued = true;
        } else {
          _applyConfig(config, syncControllers: false);
        }
      } catch (_) {
        // Auto-save failures should not interrupt typing.
      } finally {
        _isSavingConfig = false;
      }
    } while (_saveQueued && mounted);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final config = await ModelProviderConfigService.getConfig();
      final results = await Future.wait<dynamic>([
        ModelProviderConfigService.getManualModelIds(),
        ModelProviderConfigService.getCachedFetchedModels(
          apiBase: config.baseUrl,
        ),
      ]);
      if (!mounted) return;

      final manualModelIds = results[0] as List<String>;
      final cachedFetchedModels = results[1] as List<ProviderModelOption>;

      _syncController(_baseUrlController, config.baseUrl);
      _syncController(_apiKeyController, config.apiKey);

      setState(() {
        _config = config;
        _manualModelIds = manualModelIds;
        _remoteModels = cachedFetchedModels;
      });
    } catch (_) {
      if (!mounted) return;
      showToast('加载模型提供商配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyConfig(ModelProviderConfig config, {bool syncControllers = true}) {
    if (syncControllers) {
      _syncController(_baseUrlController, config.baseUrl);
      _syncController(_apiKeyController, config.apiKey);
    }
    setState(() {
      _config = config;
    });
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    _isSyncingControllers = true;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _isSyncingControllers = false;
  }

  Future<void> _fetchModels({bool silentError = false}) async {
    if (_isFetchingModels) return;
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      if (!silentError) {
        showToast('请先填写 Base URL', type: ToastType.warning);
      }
      return;
    }
    if (!ModelProviderConfigService.isValidApiBase(baseUrl)) {
      if (!silentError) {
        showToast('Base URL 格式不正确，请输入 http(s) 地址', type: ToastType.error);
      }
      return;
    }

    setState(() => _isFetchingModels = true);
    try {
      final models = await ModelProviderConfigService.fetchModels(
        apiBase: baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      setState(() {
        _remoteModels = models;
      });
      if (!silentError) {
        showToast(
          models.isEmpty ? '未获取到可用模型' : '已获取 ${models.length} 个模型',
          type: models.isEmpty ? ToastType.warning : ToastType.success,
        );
      }
    } catch (e) {
      if (!mounted || silentError) return;
      showToast('获取模型列表失败：$e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isFetchingModels = false);
      }
    }
  }

  Future<void> _promptAddModel() async {
    final modelId = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (_) => const _AddModelIdDialog(),
    );

    if (!mounted) return;
    if (modelId == null) {
      return;
    }
    final normalized = modelId.trim();
    if (!ModelProviderConfigService.isValidModelName(normalized)) {
      showToast('模型 ID 不能为空且不能以 scene. 开头', type: ToastType.error);
      return;
    }

    final existsInManual = _manualModelIds.any((item) => item == normalized);
    final existsInRemote = _remoteModels.any((item) => item.id == normalized);
    if (existsInManual || existsInRemote) {
      showToast('模型已存在', type: ToastType.warning);
      return;
    }

    final nextManual = [..._manualModelIds, normalized];
    setState(() {
      _manualModelIds = nextManual;
    });

    await _persistManualModelIds();
    showToast('已添加模型', type: ToastType.success);
  }

  Future<void> _deleteModel(_ProviderModelItem item) async {
    if (_deletingModelIds.contains(item.id)) {
      return;
    }

    final prevManual = List<String>.from(_manualModelIds);
    final prevRemote = List<ProviderModelOption>.from(_remoteModels);

    setState(() {
      _deletingModelIds = {..._deletingModelIds, item.id};
      _manualModelIds = _manualModelIds.where((id) => id != item.id).toList();
      _remoteModels = _remoteModels.where((m) => m.id != item.id).toList();
    });

    try {
      final cacheBase = _config.baseUrl.isNotEmpty
          ? _config.baseUrl
          : (_baseUrlController.text.trim());

      await Future.wait([
        ModelProviderConfigService.saveManualModelIds(_manualModelIds),
        ModelProviderConfigService.saveCachedFetchedModels(
          apiBase: cacheBase,
          models: _remoteModels,
        ),
      ]);

      if (!mounted) return;
      showToast('已删除模型', type: ToastType.success);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _manualModelIds = prevManual;
        _remoteModels = prevRemote;
      });
      showToast('删除模型失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _deletingModelIds = {..._deletingModelIds}..remove(item.id);
        });
      }
    }
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [AppColors.boxShadow],
      ),
      child: child,
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.text50,
        fontSize: 13,
        fontFamily: 'PingFang SC',
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0x1A000000)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0x1A000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF2C7FEB)),
      ),
    );
  }

  Widget _buildModelActionButton({
    required String svg,
    required VoidCallback? onPressed,
    bool highlighted = false,
    bool loading = false,
  }) {
    final isEnabled = onPressed != null;
    final useHighlightStyle = highlighted || loading;
    final backgroundColor = !isEnabled && !loading
        ? const Color(0xFFE8ECF3)
        : useHighlightStyle
        ? const Color(0xFF2C7FEB)
        : Colors.white;
    final iconColor = !isEnabled && !loading
        ? AppColors.text50
        : useHighlightStyle
        ? Colors.white
        : AppColors.text;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : SvgPicture.string(
                    svg,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeModelItem(_ProviderModelItem item) {
    final isDeleting = _deletingModelIds.contains(item.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: IgnorePointer(
        ignoring: isDeleting,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isDeleting ? 0.72 : 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final initialActionWidth =
                  constraints.maxWidth * _modelDeleteExtentRatio;
              final deleteIconRightPadding =
                  ((initialActionWidth - _modelDeleteIconSize) / 2)
                      .clamp(0.0, double.infinity)
                      .toDouble();

              return Slidable(
                key: ValueKey<String>('provider-model-${item.id}'),
                groupTag: 'provider-model-items',
                closeOnScroll: true,
                endActionPane: ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: _modelDeleteExtentRatio,
                  dismissible: DismissiblePane(
                    dismissThreshold: 0.4,
                    closeOnCancel: true,
                    motion: const InversedDrawerMotion(),
                    onDismissed: () => _deleteModel(item),
                  ),
                  children: [
                    CustomSlidableAction(
                      onPressed: (_) => _deleteModel(item),
                      backgroundColor: AppColors.alertRed,
                      borderRadius: _modelDeleteActionRadius,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: deleteIconRightPadding),
                        child: SvgPicture.asset(
                          'assets/memory/memory_delete.svg',
                          width: _modelDeleteIconSize,
                          height: _modelDeleteIconSize,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [AppColors.boxShadow],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.id,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text,
                                  fontFamily: 'PingFang SC',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.sourceLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.text.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelItems = _modelItems;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: '模型提供商', primary: true),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Provider 配置',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _baseUrlController,
                                decoration: _buildInputDecoration(
                                  hint:
                                      '例如：https://api.openai.com 或 https://xxx/v1',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '支持直接输入根地址、/v1、/v1/models 或 /v1/chat/completions，保存时会自动归一化。',
                                style: TextStyle(
                                  color: AppColors.text50,
                                  fontSize: 12,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _apiKeyController,
                                obscureText: _obscureApiKey,
                                decoration: _buildInputDecoration(
                                  hint: '例如：sk-xxxx',
                                  suffixIcon: IconButton(
                                    splashRadius: 18,
                                    onPressed: () {
                                      setState(() {
                                        _obscureApiKey = !_obscureApiKey;
                                      });
                                    },
                                    icon: Icon(
                                      _obscureApiKey
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: AppColors.text50,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '未填写 API Key 时，会以无鉴权方式请求 Provider。',
                                style: TextStyle(
                                  color: AppColors.text50,
                                  fontSize: 12,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '模型列表',
                                          style: TextStyle(
                                            color: AppColors.text,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'PingFang SC',
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '共 ${modelItems.length} 个模型',
                                          style: const TextStyle(
                                            color: AppColors.text70,
                                            fontSize: 12,
                                            fontFamily: 'PingFang SC',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildModelActionButton(
                                    svg: _kPlusSvg,
                                    onPressed: _promptAddModel,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildModelActionButton(
                                    svg: _kArrowBigDownSvg,
                                    onPressed: _isFetchingModels
                                        ? null
                                        : _fetchModels,
                                    highlighted: true,
                                    loading: _isFetchingModels,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                height: 280,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4F7FB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x1A000000)),
                                ),
                                child: modelItems.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SvgPicture.string(
                                              _kPackageSvg,
                                              width: 64,
                                              height: 64,
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                    AppColors.text50,
                                                    BlendMode.srcIn,
                                                  ),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              '请添加模型！',
                                              style: TextStyle(
                                                color: AppColors.text70,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'PingFang SC',
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: modelItems.length,
                                        itemBuilder: (context, index) {
                                          return _buildSwipeModelItem(
                                            modelItems[index],
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
      ),
    );
  }
}

class _AddModelIdDialog extends StatefulWidget {
  const _AddModelIdDialog();

  @override
  State<_AddModelIdDialog> createState() => _AddModelIdDialogState();
}

class _AddModelIdDialogState extends State<_AddModelIdDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    _focusNode.unfocus();
    Navigator.of(context).pop(value);
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
        title: const Text('添加模型 ID'),
        content: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            hintText: '输入模型 ID',
          ),
          onSubmitted: (_) => _close(_controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => _close(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => _close(_controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
