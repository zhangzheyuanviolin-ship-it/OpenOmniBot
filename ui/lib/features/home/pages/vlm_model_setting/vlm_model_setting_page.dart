import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class VlmModelSettingPage extends StatefulWidget {
  const VlmModelSettingPage({super.key});

  @override
  State<VlmModelSettingPage> createState() => _VlmModelSettingPageState();
}

class _VlmModelSettingPageState extends State<VlmModelSettingPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _manualModelController = TextEditingController();

  static const Duration _autoSaveDebounce = Duration(milliseconds: 600);

  bool _isLoading = true;
  bool _isFetchingModels = false;
  bool _obscureApiKey = true;
  bool _isSyncingControllers = false;
  bool _isSavingConfig = false;
  bool _saveQueued = false;

  Timer? _autoSaveTimer;

  ModelProviderConfig _config = ModelProviderConfig.empty();
  List<ProviderModelOption> _models = const [];
  String _selectedModelId = '';

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _baseUrlController.addListener(_onConfigChanged);
    _apiKeyController.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_shouldAutoSaveDraft) {
      unawaited(_persistConfigDraft());
    }
    _baseUrlController.removeListener(_onConfigChanged);
    _apiKeyController.removeListener(_onConfigChanged);
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _manualModelController.dispose();
    super.dispose();
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

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final config = await ModelProviderConfigService.getConfig();
      if (!mounted) return;
      _applyConfig(config);
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

  String get _maskedApiKey {
    final trimmed = _config.apiKey.trim();
    if (trimmed.isEmpty) {
      return '未配置';
    }
    if (trimmed.length <= 8) {
      return '${trimmed.substring(0, 2)}****';
    }
    return '${trimmed.substring(0, 4)}****${trimmed.substring(trimmed.length - 4)}';
  }

  String get _sourceLabel {
    switch (_config.source) {
      case 'user':
      case 'global':
        return '本地配置';
      default:
        return '未配置';
    }
  }

  Future<void> _clearConfig() async {
    if (_isFetchingModels) return;
    try {
      final config = await ModelProviderConfigService.clearConfig();
      if (!mounted) return;
      _manualModelController.clear();
      setState(() {
        _models = const [];
        _selectedModelId = '';
      });
      _applyConfig(config);
      showToast('已清空模型提供商配置', type: ToastType.success);
    } catch (_) {
      if (!mounted) return;
      showToast('清空配置失败', type: ToastType.error);
    }
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
        _models = models;
        if (_selectedModelId.isNotEmpty &&
            !models.any((item) => item.id == _selectedModelId)) {
          _selectedModelId = '';
        }
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

  Future<void> _pickModel() async {
    if (_models.isEmpty) {
      await _fetchModels();
      if (!mounted) return;
      if (_models.isEmpty) return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return _ProviderModelPickerSheet(
          items: _models,
          currentValue: _selectedModelId,
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedModelId = selected;
        _manualModelController.text = selected;
      });
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

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.text70,
            fontSize: 12,
            fontFamily: 'PingFang SC',
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: 'PingFang SC',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      body: SafeArea(
        child: Column(
          children: [
            const CommonAppBar(title: '模型提供商'),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFEAF4FF), Color(0xFFFFFFFF)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x1A2C7FEB)),
                            boxShadow: [AppColors.boxShadow],
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.hub_outlined,
                                    size: 18,
                                    color: Color(0xFF2C7FEB),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'OpenAI-Compatible 模型提供商',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'PingFang SC',
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                '在这里配置全局自定义 Provider。配置会自动保存，只有被场景页绑定了模型的 scene 才会真正走这个 Provider。',
                                style: TextStyle(
                                  color: AppColors.text70,
                                  fontSize: 12,
                                  height: 1.5,
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
                              _buildInfoRow('当前配置来源', _sourceLabel),
                              const SizedBox(height: 10),
                              _buildInfoRow(
                                '当前生效 Base URL',
                                _config.baseUrl.isEmpty
                                    ? '未配置'
                                    : _config.baseUrl,
                              ),
                              const SizedBox(height: 10),
                              _buildInfoRow('当前 API Key', _maskedApiKey),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
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
                                  const Expanded(
                                    child: Text(
                                      '模型列表',
                                      style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'PingFang SC',
                                      ),
                                    ),
                                  ),
                                  if (_isFetchingModels)
                                    const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    Text(
                                      _models.isEmpty
                                          ? '点击展开拉取'
                                          : '共 ${_models.length} 个模型',
                                      style: const TextStyle(
                                        color: AppColors.text70,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _pickModel,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0x1A000000),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedModelId.isEmpty
                                              ? '从 Provider 模型列表中选择'
                                              : _selectedModelId,
                                          style: TextStyle(
                                            color: _selectedModelId.isEmpty
                                                ? AppColors.text50
                                                : AppColors.text,
                                            fontSize: 13,
                                            fontFamily: 'PingFang SC',
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.expand_more),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _manualModelController,
                                decoration: _buildInputDecoration(
                                  hint: '也可以手动输入模型名',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '手动输入优先于列表选择；适用于 /v1/models 不完整或 Provider 不返回模型列表的情况。',
                                style: TextStyle(
                                  color: AppColors.text50,
                                  fontSize: 12,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 44,
                                child: OutlinedButton(
                                  onPressed: _isFetchingModels
                                      ? null
                                      : _clearConfig,
                                  child: const Text('恢复默认'),
                                ),
                              ),
                            ),
                          ],
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

class _ProviderModelPickerSheet extends StatefulWidget {
  const _ProviderModelPickerSheet({
    required this.items,
    required this.currentValue,
  });

  final List<ProviderModelOption> items;
  final String currentValue;

  @override
  State<_ProviderModelPickerSheet> createState() =>
      _ProviderModelPickerSheetState();
}

class _ProviderModelPickerSheetState extends State<_ProviderModelPickerSheet> {
  late final TextEditingController _searchController;
  late List<ProviderModelOption> _filteredItems;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredItems = List<ProviderModelOption>.from(widget.items);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilter(String keyword) {
    final query = keyword.trim().toLowerCase();
    setState(() {
      _filteredItems = widget.items.where((item) {
        final haystack =
            '${item.id} ${item.displayName} ${item.ownedBy ?? ''}'
                .toLowerCase();
        return haystack.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final sheetHeight = (availableHeight * 0.78)
        .clamp(420.0, 620.0)
        .toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: Container(
          color: Colors.white,
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0x22000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '选择模型',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _updateFilter,
                    decoration: InputDecoration(
                      hintText: '搜索模型 ID',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    physics: const ClampingScrollPhysics(),
                    clipBehavior: Clip.hardEdge,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isSelected = item.id == widget.currentValue;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        tileColor: isSelected
                            ? const Color(0xFFF0F7FF)
                            : const Color(0xFFF8FAFC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        title: Text(item.displayName),
                        subtitle: Text(
                          item.ownedBy == null
                              ? item.id
                              : '${item.id} · ${item.ownedBy}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFF2C7FEB),
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(item.id),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemCount: _filteredItems.length,
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
