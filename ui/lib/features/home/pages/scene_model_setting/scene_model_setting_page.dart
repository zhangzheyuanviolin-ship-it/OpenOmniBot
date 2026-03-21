import 'package:flutter/material.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/services/scene_model_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class SceneModelSettingPage extends StatefulWidget {
  const SceneModelSettingPage({super.key});

  @override
  State<SceneModelSettingPage> createState() => _SceneModelSettingPageState();
}

class _SceneModelSettingPageState extends State<SceneModelSettingPage> {
  final TextEditingController _manualModelController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRefreshingModels = false;

  List<SceneCatalogItem> _catalog = const [];
  List<SceneModelOverrideEntry> _overrides = const [];
  List<ProviderModelOption> _providerModels = const [];

  String _selectedSceneId = '';
  String _selectedModelId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _manualModelController.dispose();
    super.dispose();
  }

  SceneCatalogItem? get _selectedScene {
    if (_selectedSceneId.isEmpty) return null;
    for (final item in _catalog) {
      if (item.sceneId == _selectedSceneId) {
        return item;
      }
    }
    return null;
  }

  bool get _providerConfigured {
    return _catalog.any((item) => item.providerConfigured);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SceneModelConfigService.getSceneCatalog(),
        SceneModelConfigService.getSceneModelOverrides(),
        ModelProviderConfigService.fetchModels(),
      ]);
      if (!mounted) return;
      final catalog = results[0] as List<SceneCatalogItem>;
      final overrides = results[1] as List<SceneModelOverrideEntry>;
      final providerModels = results[2] as List<ProviderModelOption>;
      final initialSceneId = _selectedSceneId.isNotEmpty
          ? _selectedSceneId
          : (catalog.isNotEmpty ? catalog.first.sceneId : '');

      setState(() {
        _catalog = catalog;
        _overrides = overrides;
        _providerModels = providerModels;
        _selectedSceneId = initialSceneId;
        _syncSelectionFromOverride();
      });
    } catch (_) {
      if (!mounted) return;
      showToast('加载场景配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _syncSelectionFromOverride() {
    final scene = _selectedScene;
    if (scene == null) {
      _manualModelController.clear();
      _selectedModelId = '';
      return;
    }
    final overrideEntry = _overrides.where(
      (item) => item.sceneId == scene.sceneId,
    );
    final overrideModel = overrideEntry.isEmpty
        ? ''
        : overrideEntry.first.model;
    _manualModelController.text = overrideModel;
    if (_providerModels.any((item) => item.id == overrideModel)) {
      _selectedModelId = overrideModel;
    } else {
      _selectedModelId = '';
    }
  }

  Future<void> _refreshProviderModels() async {
    if (_isRefreshingModels || _isSaving) return;
    setState(() => _isRefreshingModels = true);
    try {
      final models = await ModelProviderConfigService.fetchModels();
      if (!mounted) return;
      setState(() {
        _providerModels = models;
        if (_selectedModelId.isNotEmpty &&
            !_providerModels.any((item) => item.id == _selectedModelId)) {
          _selectedModelId = '';
        }
      });
      showToast(
        models.isEmpty ? '未获取到 Provider 模型列表' : '已刷新 ${models.length} 个模型',
        type: models.isEmpty ? ToastType.warning : ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showToast('刷新模型列表失败：$e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isRefreshingModels = false);
      }
    }
  }

  Future<String?> _showSearchablePicker<T>({
    required String title,
    required List<T> items,
    required String Function(T item) titleBuilder,
    required String Function(T item) subtitleBuilder,
    required String Function(T item) valueBuilder,
    required String currentValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return _SearchablePickerSheet<T>(
          title: title,
          items: items,
          titleBuilder: titleBuilder,
          subtitleBuilder: subtitleBuilder,
          valueBuilder: valueBuilder,
          currentValue: currentValue,
        );
      },
    );
  }

  Future<void> _pickScene() async {
    if (_catalog.isEmpty) {
      showToast('暂无可配置场景', type: ToastType.warning);
      return;
    }
    final selected = await _showSearchablePicker<SceneCatalogItem>(
      title: '选择场景',
      items: _catalog,
      titleBuilder: (item) => item.sceneId,
      subtitleBuilder: (item) => item.description.isEmpty
          ? '${item.defaultModel} · ${item.transport}'
          : item.description,
      valueBuilder: (item) => item.sceneId,
      currentValue: _selectedSceneId,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedSceneId = selected;
      });
      _syncSelectionFromOverride();
      setState(() {});
    }
  }

  Future<void> _pickModel() async {
    if (_providerModels.isEmpty) {
      showToast('当前没有可选模型，请先在模型提供商页配置并拉取模型', type: ToastType.warning);
      return;
    }
    final selected = await _showSearchablePicker<ProviderModelOption>(
      title: '选择 Provider 模型',
      items: _providerModels,
      titleBuilder: (item) => item.displayName,
      subtitleBuilder: (item) =>
          item.ownedBy == null ? item.id : '${item.id} · ${item.ownedBy}',
      valueBuilder: (item) => item.id,
      currentValue: _selectedModelId,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedModelId = selected;
        _manualModelController.text = selected;
      });
    }
  }

  Future<void> _saveOverride() async {
    final scene = _selectedScene;
    if (scene == null) {
      showToast('请先选择场景', type: ToastType.warning);
      return;
    }
    final model = _manualModelController.text.trim().isNotEmpty
        ? _manualModelController.text.trim()
        : _selectedModelId.trim();
    if (model.isEmpty) {
      showToast('请先选择或输入模型名', type: ToastType.warning);
      return;
    }
    if (!SceneModelConfigService.isValidModelName(model)) {
      showToast('模型名不能以 scene. 开头', type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final overrides = await SceneModelConfigService.saveSceneModelOverride(
        sceneId: scene.sceneId,
        model: model,
      );
      if (!mounted) return;
      _overrides = overrides;
      await _loadData();
      if (!mounted) return;
      showToast(
        _providerConfigured ? '场景模型已保存并生效' : '场景模型已保存，待配置模型提供商后生效',
        type: ToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showToast('保存场景模型失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _clearOverride() async {
    final scene = _selectedScene;
    if (scene == null) {
      showToast('请先选择场景', type: ToastType.warning);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final overrides = await SceneModelConfigService.clearSceneModelOverride(
        scene.sceneId,
      );
      if (!mounted) return;
      _overrides = overrides;
      await _loadData();
      if (!mounted) return;
      showToast('已清空该场景自定义模型', type: ToastType.success);
    } catch (_) {
      if (!mounted) return;
      showToast('清空场景模型失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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

  Widget _buildLabelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.text70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = _selectedScene;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: '场景模型配置', primary: true),
      body: SafeArea(
        top: false,
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
                              colors: [Color(0xFFFFF5E8), Color(0xFFFFFFFF)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0x26E48B1A)),
                            boxShadow: [AppColors.boxShadow],
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.tune_outlined,
                                    size: 18,
                                    color: Color(0xFFE48B1A),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Scene 级模型绑定',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                '先选择场景，再给这个场景绑定自定义模型。已绑定场景会使用对应模型，未绑定场景使用当前默认模型。',
                                style: TextStyle(
                                  color: AppColors.text70,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (!_providerConfigured)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7E8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0x33E48B1A),
                              ),
                            ),
                            child: const Text(
                              '当前未配置模型提供商，scene 绑定会先保存。请先到“模型提供商”页面配置 Base URL 和 API Key，配置后即可生效。',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                          ),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '选择场景',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _pickScene,
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
                                          scene?.sceneId ?? '选择一个场景',
                                          style: TextStyle(
                                            color: scene == null
                                                ? AppColors.text50
                                                : AppColors.text,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.expand_more),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _isRefreshingModels
                                          ? null
                                          : _refreshProviderModels,
                                      icon: _isRefreshingModels
                                          ? const SizedBox(
                                              height: 14,
                                              width: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.refresh, size: 16),
                                      label: const Text('刷新 Provider 模型'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (scene != null) ...[
                          _buildCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabelValue(
                                  '场景描述',
                                  scene.description.isEmpty
                                      ? '暂无描述'
                                      : scene.description,
                                ),
                                const SizedBox(height: 12),
                                _buildLabelValue('默认模型', scene.defaultModel),
                                const SizedBox(height: 12),
                                _buildLabelValue(
                                  '当前生效模型',
                                  scene.effectiveModel,
                                ),
                                const SizedBox(height: 12),
                                _buildLabelValue('当前生效路由', scene.transport),
                                const SizedBox(height: 12),
                                _buildLabelValue(
                                  '当前 override',
                                  scene.overrideModel.isEmpty
                                      ? '未配置'
                                      : scene.overrideModel,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '设置该场景的模型',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                                  decoration: InputDecoration(
                                    hintText: '也可以直接输入模型名',
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '手动输入优先于列表选择。适合只想给某个 scene 绑定一个特定模型名的情况。',
                                  style: TextStyle(
                                    color: AppColors.text50,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 44,
                                        child: OutlinedButton(
                                          onPressed: _isSaving
                                              ? null
                                              : _clearOverride,
                                          child: const Text('清空当前场景'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: 44,
                                        child: ElevatedButton(
                                          onPressed: _isSaving
                                              ? null
                                              : _saveOverride,
                                          style: ElevatedButton.styleFrom(
                                            elevation: 0,
                                            backgroundColor: const Color(
                                              0xFF2C7FEB,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: _isSaving
                                              ? const SizedBox(
                                                  height: 16,
                                                  width: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  '保存当前场景',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _buildCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '已配置场景',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_overrides.isEmpty)
                                const Text(
                                  '暂未配置任何场景自定义模型',
                                  style: TextStyle(
                                    color: AppColors.text70,
                                    fontSize: 12,
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _overrides.map((entry) {
                                    return ActionChip(
                                      label: Text(
                                        '${entry.sceneId} -> ${entry.model}',
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _selectedSceneId = entry.sceneId;
                                        });
                                        _syncSelectionFromOverride();
                                      },
                                    );
                                  }).toList(),
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

class _SearchablePickerSheet<T> extends StatefulWidget {
  const _SearchablePickerSheet({
    required this.title,
    required this.items,
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.valueBuilder,
    required this.currentValue,
  });

  final String title;
  final List<T> items;
  final String Function(T item) titleBuilder;
  final String Function(T item) subtitleBuilder;
  final String Function(T item) valueBuilder;
  final String currentValue;

  @override
  State<_SearchablePickerSheet<T>> createState() =>
      _SearchablePickerSheetState<T>();
}

class _SearchablePickerSheetState<T> extends State<_SearchablePickerSheet<T>> {
  late final TextEditingController _searchController;
  late List<T> _filteredItems;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredItems = List<T>.from(widget.items);
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
            '${widget.titleBuilder(item)} ${widget.subtitleBuilder(item)}'
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
    final sheetHeight = (availableHeight * 0.82)
        .clamp(320.0, 620.0)
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
                Text(
                  widget.title,
                  style: const TextStyle(
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
                      hintText: '搜索',
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
                      final selected =
                          widget.valueBuilder(item) == widget.currentValue;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: selected
                            ? const Color(0xFFF0F7FF)
                            : const Color(0xFFF8FAFC),
                        title: Text(widget.titleBuilder(item)),
                        subtitle: Text(
                          widget.subtitleBuilder(item),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFF2C7FEB),
                              )
                            : null,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(widget.valueBuilder(item)),
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
