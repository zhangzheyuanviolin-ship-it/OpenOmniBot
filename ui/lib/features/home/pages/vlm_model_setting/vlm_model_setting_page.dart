import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/popup_menu_anchor_position.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/settings_section_title.dart';

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

const double _kProviderSwitchPopupMaxHeight = 320;

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
  final TextEditingController _nameController = TextEditingController();
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
  bool _isSavingProfile = false;
  bool _saveQueued = false;
  bool _isSwitchingProfile = false;
  String _selectedProtocolType = 'openai_compatible';

  Timer? _autoSaveTimer;
  StreamSubscription<AgentAiConfigChangedEvent>? _configChangedSubscription;

  List<ModelProviderProfileSummary> _profiles = const [];
  String _editingProfileId = '';
  List<ProviderModelOption> _remoteModels = const [];
  List<String> _manualModelIds = const [];
  Set<String> _deletingModelIds = <String>{};

  ModelProviderProfileSummary? get _currentProfile {
    for (final profile in _profiles) {
      if (profile.id == _editingProfileId) {
        return profile;
      }
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  bool get _isDarkTheme => context.isDarkTheme;
  Color get _pageBackground =>
      _isDarkTheme ? context.omniPalette.pageBackground : AppColors.background;
  Color get _cardColor =>
      _isDarkTheme ? context.omniPalette.surfacePrimary : Colors.white;
  Color get _surfaceColor => _isDarkTheme
      ? context.omniPalette.surfaceSecondary
      : const Color(0xFFF8FAFC);
  Color get _primaryTextColor =>
      _isDarkTheme ? context.omniPalette.textPrimary : AppColors.text;
  Color get _secondaryTextColor =>
      _isDarkTheme ? context.omniPalette.textSecondary : AppColors.text70;
  Color get _tertiaryTextColor =>
      _isDarkTheme ? context.omniPalette.textTertiary : AppColors.text50;
  BorderSide get _subtleBorder => BorderSide(
    color: _isDarkTheme
        ? context.omniPalette.borderSubtle
        : const Color(0x1A000000),
  );

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

  @override
  void initState() {
    super.initState();
    _loadData();
    _configChangedSubscription = AssistsMessageService
        .agentAiConfigChangedStream
        .listen((event) {
          if (event.source != 'file' || !mounted) {
            return;
          }
          unawaited(_loadData());
        });
    _nameController.addListener(_onProfileChanged);
    _baseUrlController.addListener(_onProfileChanged);
    _apiKeyController.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    _configChangedSubscription?.cancel();
    _autoSaveTimer?.cancel();
    if (_shouldAutoSaveDraft) {
      unawaited(_persistProfileDraft());
    }
    unawaited(_persistManualModelIds());
    _nameController.removeListener(_onProfileChanged);
    _baseUrlController.removeListener(_onProfileChanged);
    _apiKeyController.removeListener(_onProfileChanged);
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (_isSyncingControllers || _isLoading || _isSwitchingProfile) {
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
      unawaited(_persistProfileDraft());
    });
  }

  bool get _shouldAutoSaveDraft {
    final current = _currentProfile;
    if (current == null || current.readOnly) {
      return false;
    }
    final normalizedBaseUrl = ModelProviderConfigService.normalizeApiBase(
      _baseUrlController.text,
    );
    final currentBaseUrl =
        ModelProviderConfigService.normalizeApiBase(current.baseUrl) ?? '';
    final nextBaseUrl = normalizedBaseUrl ?? '';
    return _nameController.text.trim() != current.name ||
        nextBaseUrl != currentBaseUrl ||
        _apiKeyController.text.trim() != current.apiKey;
  }

  Future<void> _persistManualModelIds() async {
    final current = _currentProfile;
    if (current == null) {
      return;
    }
    try {
      await ModelProviderConfigService.saveManualModelIds(
        profileId: current.id,
        ids: _manualModelIds,
      );
    } catch (_) {
      // no-op
    }
  }

  Future<void> _persistProfileDraft() async {
    final current = _currentProfile;
    if (current == null || current.readOnly) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    if (_isSavingProfile) {
      _saveQueued = true;
      return;
    }

    do {
      _saveQueued = false;
      final nextName = _nameController.text.trim();
      final nextBaseUrl =
          ModelProviderConfigService.normalizeApiBase(
            _baseUrlController.text,
          ) ??
          '';
      final nextApiKey = _apiKeyController.text.trim();
      final currentBaseUrl =
          ModelProviderConfigService.normalizeApiBase(current.baseUrl) ?? '';

      if (nextName == current.name &&
          nextBaseUrl == currentBaseUrl &&
          nextApiKey == current.apiKey) {
        return;
      }

      _isSavingProfile = true;
      try {
        final saved = await ModelProviderConfigService.saveProfile(
          id: current.id,
          name: nextName.isEmpty ? current.name : nextName,
          baseUrl: _baseUrlController.text.trim(),
          apiKey: nextApiKey,
          protocolType: _selectedProtocolType,
        );
        if (!mounted) return;
        setState(() {
          _profiles = _profiles
              .map((profile) => profile.id == saved.id ? saved : profile)
              .toList();
          _editingProfileId = saved.id;
        });
      } catch (_) {
        // Auto-save failures should not interrupt typing.
      } finally {
        _isSavingProfile = false;
      }
    } while (_saveQueued && mounted);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final payload = await ModelProviderConfigService.listProfiles();
      if (!mounted) return;

      final editingProfile = payload.profiles.firstWhere(
        (profile) => profile.id == payload.editingProfileId,
        orElse: () => payload.profiles.first,
      );
      final storedModels = await Future.wait<dynamic>([
        ModelProviderConfigService.getManualModelIds(
          profileId: editingProfile.id,
        ),
        ModelProviderConfigService.getCachedFetchedModels(
          profileId: editingProfile.id,
          apiBase: editingProfile.baseUrl,
        ),
      ]);
      if (!mounted) return;

      _applyProfile(
        profiles: payload.profiles,
        editingProfileId: editingProfile.id,
        manualModelIds: storedModels[0] as List<String>,
        remoteModels: storedModels[1] as List<ProviderModelOption>,
        syncControllers: true,
      );
    } catch (_) {
      if (!mounted) return;
      showToast('加载模型提供商配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyProfile({
    required List<ModelProviderProfileSummary> profiles,
    required String editingProfileId,
    required List<String> manualModelIds,
    required List<ProviderModelOption> remoteModels,
    required bool syncControllers,
  }) {
    final current = profiles.firstWhere(
      (profile) => profile.id == editingProfileId,
      orElse: () => profiles.first,
    );
    if (syncControllers) {
      _syncController(_nameController, current.name);
      _syncController(_baseUrlController, current.baseUrl);
      _syncController(_apiKeyController, current.apiKey);
    }
    setState(() {
      _profiles = profiles;
      _editingProfileId = current.id;
      _manualModelIds = manualModelIds;
      _remoteModels = remoteModels;
      _selectedProtocolType = current.protocolType;
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

  String? _buildBaseUrlHelperText(String rawValue) {
    final input = rawValue.trim();
    if (input.isEmpty) {
      return null;
    }

    return ModelProviderConfigService.buildChatCompletionsRequestUrl(input);
  }

  Future<void> _switchToProfile(String profileId) async {
    if (_isSwitchingProfile || profileId == _editingProfileId) {
      return;
    }
    final index = _profiles.indexWhere((profile) => profile.id == profileId);
    if (index == -1) {
      return;
    }
    _isSwitchingProfile = true;
    try {
      if (_shouldAutoSaveDraft) {
        await _persistProfileDraft();
      }
      final selected = await ModelProviderConfigService.setEditingProfile(
        profileId,
      );
      final storedModels = await Future.wait<dynamic>([
        ModelProviderConfigService.getManualModelIds(profileId: selected.id),
        ModelProviderConfigService.getCachedFetchedModels(
          profileId: selected.id,
          apiBase: selected.baseUrl,
        ),
      ]);
      if (!mounted) return;
      _applyProfile(
        profiles: _profiles,
        editingProfileId: selected.id,
        manualModelIds: storedModels[0] as List<String>,
        remoteModels: storedModels[1] as List<ProviderModelOption>,
        syncControllers: true,
      );
    } catch (e) {
      if (!mounted) return;
      showToast('切换提供商失败：$e', type: ToastType.error);
    } finally {
      _isSwitchingProfile = false;
    }
  }

  Future<void> _fetchModels({bool silentError = false}) async {
    final current = _currentProfile;
    if (current == null || _isFetchingModels) return;
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
        profileId: current.id,
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

  Future<void> _promptAddProfile() async {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final name = (await AppDialog.input(
      context,
      title: '新增 Provider',
      hintText: '例如：DeepSeek',
      confirmText: '新增',
      cancelText: '取消',
    ))?.trim();
    if (name == null || name.isEmpty) {
      return;
    }
    try {
      final saved = await ModelProviderConfigService.saveProfile(
        name: name,
        baseUrl: '',
        apiKey: '',
      );
      if (!mounted) return;
      final nextProfiles = [..._profiles, saved];
      _applyProfile(
        profiles: nextProfiles,
        editingProfileId: saved.id,
        manualModelIds: const [],
        remoteModels: const [],
        syncControllers: true,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showToast('已新增 Provider', type: ToastType.success);
      });
    } catch (e) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showToast('新增 Provider 失败：$e', type: ToastType.error);
      });
    }
  }

  Future<void> _deleteCurrentProfile() async {
    final current = _currentProfile;
    if (current == null || current.readOnly || _profiles.length <= 1) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除 Provider'),
          content: Text('确定删除“${current.name}”吗？场景绑定会保留，但需要重新选择可用 Provider。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    try {
      final payload = await ModelProviderConfigService.deleteProfile(
        current.id,
      );
      if (!mounted) return;
      final fallback = payload.profiles.firstWhere(
        (profile) => profile.id == payload.editingProfileId,
        orElse: () => payload.profiles.first,
      );
      final storedModels = await Future.wait<dynamic>([
        ModelProviderConfigService.getManualModelIds(profileId: fallback.id),
        ModelProviderConfigService.getCachedFetchedModels(
          profileId: fallback.id,
          apiBase: fallback.baseUrl,
        ),
      ]);
      if (!mounted) return;
      _applyProfile(
        profiles: payload.profiles,
        editingProfileId: fallback.id,
        manualModelIds: storedModels[0] as List<String>,
        remoteModels: storedModels[1] as List<ProviderModelOption>,
        syncControllers: true,
      );
      showToast('已删除 Provider', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('删除 Provider 失败：$e', type: ToastType.error);
    }
  }

  Future<void> _promptAddModel() async {
    final current = _currentProfile;
    if (current == null || current.readOnly) {
      return;
    }
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

    await ModelProviderConfigService.saveManualModelIds(
      profileId: current.id,
      ids: nextManual,
    );
    showToast('已添加模型', type: ToastType.success);
  }

  Future<void> _deleteModel(_ProviderModelItem item) async {
    final current = _currentProfile;
    if (current == null || _deletingModelIds.contains(item.id)) {
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
      await Future.wait([
        ModelProviderConfigService.saveManualModelIds(
          profileId: current.id,
          ids: _manualModelIds,
        ),
        ModelProviderConfigService.saveCachedFetchedModels(
          profileId: current.id,
          apiBase: _baseUrlController.text.trim(),
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

  Widget _buildProtocolOption({
    required String label,
    required String value,
  }) {
    final selected = _selectedProtocolType == value;
    return GestureDetector(
      onTap: () async {
        if (_selectedProtocolType == value) return;
        final current = _currentProfile;
        if (current == null || current.readOnly) return;
        setState(() => _selectedProtocolType = value);
        try {
          final saved = await ModelProviderConfigService.saveProfile(
            id: current.id,
            name: current.name,
            baseUrl: current.baseUrl,
            apiKey: current.apiKey,
            protocolType: value,
          );
          if (!mounted) return;
          setState(() {
            _profiles = _profiles
                .map((p) => p.id == saved.id ? saved : p)
                .toList();
          });
        } catch (_) {
          if (!mounted) return;
          setState(() => _selectedProtocolType = current.protocolType);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2C7FEB) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF2C7FEB)
                : const Color(0x1A000000),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AppColors.text,
            fontFamily: 'PingFang SC',
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return SizedBox(width: double.infinity, child: child);
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: _tertiaryTextColor,
        fontSize: 13,
        fontFamily: 'PingFang SC',
      ),
      filled: true,
      fillColor: _surfaceColor,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: _subtleBorder,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: _subtleBorder,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: _isDarkTheme
              ? context.omniPalette.accentPrimary
              : const Color(0xFF2C7FEB),
        ),
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
        ? (_isDarkTheme
              ? context.omniPalette.surfaceElevated
              : const Color(0xFFE8ECF3))
        : useHighlightStyle
        ? (_isDarkTheme
              ? context.omniPalette.accentPrimary
              : const Color(0xFF2C7FEB))
        : _cardColor;
    final iconColor = !isEnabled && !loading
        ? _tertiaryTextColor
        : useHighlightStyle
        ? (_isDarkTheme
              ? Theme.of(context).colorScheme.onPrimary
              : Colors.white)
        : _primaryTextColor;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: !useHighlightStyle && _isDarkTheme
              ? Border.all(color: context.omniPalette.borderSubtle)
              : null,
        ),
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
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isDarkTheme
                          ? context.omniPalette.borderSubtle
                          : const Color(0x14000000),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(12),
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
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _primaryTextColor,
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
                                color: _tertiaryTextColor,
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

  Future<void> _openProviderSwitchMenu(BuildContext anchorContext) async {
    if (_profiles.isEmpty) {
      return;
    }
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlay == null || anchorBox == null || !anchorBox.hasSize) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final anchorRect = Rect.fromPoints(topLeft, bottomRight);
    final popupWidth = anchorRect.width.clamp(220.0, 300.0).toDouble();
    final estimatedHeight = (_profiles.length * 48 + 24)
        .clamp(120.0, _kProviderSwitchPopupMaxHeight)
        .toDouble();
    final position = PopupMenuAnchorPosition.fromAnchorRect(
      anchorRect: anchorRect,
      overlaySize: overlay.size,
      estimatedMenuHeight: estimatedHeight,
      reservedBottom: MediaQuery.of(context).viewInsets.bottom,
      verticalGap: 6,
    );
    final selected = await showMenu<String>(
      context: context,
      color: _cardColor,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
      position: position,
      items: [
        _ProviderSwitchPopupEntry(
          width: popupWidth,
          estimatedHeight: estimatedHeight,
          profiles: _profiles,
          selectedProfileId: _editingProfileId,
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    await _switchToProfile(selected);
  }

  Widget _buildProviderConfigTitle() {
    final current = _currentProfile;
    final name = current?.name.trim();
    final displayName = (name == null || name.isEmpty) ? 'Provider' : name;
    return Builder(
      builder: (anchorContext) {
        return InkWell(
          onTap: _profiles.isEmpty
              ? null
              : () {
                  unawaited(_openProviderSwitchMenu(anchorContext));
                },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'PingFang SC',
                        ),
                      ),
                      if (current != null &&
                          (current.readOnly || current.statusText.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            current.statusText.isNotEmpty
                                ? current.statusText
                                : (current.ready
                                      ? '内置 Provider'
                                      : '内置 Provider 未就绪'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _tertiaryTextColor,
                              fontSize: 11,
                              fontFamily: 'PingFang SC',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (current?.readOnly == true)
                  Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: _tertiaryTextColor,
                    ),
                  ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: _secondaryTextColor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelItems = _modelItems;

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: CommonAppBar(title: '模型提供商', primary: true),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  const SettingsSectionTitle(
                    label: 'Provider 配置',
                    subtitle: '新增、切换并维护模型服务提供商的名称、地址与密钥。',
                  ),
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildProviderConfigTitle()),
                            _buildModelActionButton(
                              svg: '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M3 6h18"/>
  <path d="M8 6V4h8v2"/>
  <path d="M19 6l-1 14H6L5 6"/>
  <path d="M10 11v6"/>
  <path d="M14 11v6"/>
</svg>
''',
                              onPressed:
                                  _profiles.length <= 1 ||
                                      _currentProfile?.readOnly == true
                                  ? null
                                  : _deleteCurrentProfile,
                            ),
                            const SizedBox(width: 8),
                            _buildModelActionButton(
                              svg: _kPlusSvg,
                              onPressed: _promptAddProfile,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameController,
                          enabled: !(_currentProfile?.readOnly ?? false),
                          decoration: _buildInputDecoration(
                            hint: 'Provider 名称',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _baseUrlController,
                          enabled: !(_currentProfile?.readOnly ?? false),
                          decoration: _buildInputDecoration(
                            hint: '例如：https://api.openai.com 或 https://xxx/v1',
                          ),
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _baseUrlController,
                          builder: (context, value, child) {
                            final url = _buildBaseUrlHelperText(value.text);
                            if (url == null) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              url,
                              style: TextStyle(
                                color: _tertiaryTextColor,
                                fontSize: 12,
                                fontFamily: 'PingFang SC',
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _apiKeyController,
                          enabled: !(_currentProfile?.readOnly ?? false),
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
                                color: _tertiaryTextColor,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '未填写 API Key 时，会以无鉴权方式请求 Provider。',
                          style: TextStyle(
                            color: _tertiaryTextColor,
                            fontSize: 12,
                            fontFamily: 'PingFang SC',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '协议类型',
                          style: TextStyle(
                            color: AppColors.text70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'PingFang SC',
                          ),
                        ),
                        const SizedBox(height: 8),
                        IgnorePointer(
                          ignoring: _currentProfile?.readOnly ?? false,
                          child: Row(
                            children: [
                              _buildProtocolOption(
                                label: 'OpenAI Compatible',
                                value: 'openai_compatible',
                              ),
                              const SizedBox(width: 8),
                              _buildProtocolOption(
                                label: 'Anthropic',
                                value: 'anthropic',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SettingsSectionTitle(
                    label: '模型列表',
                    subtitle: '支持手动补充模型，也可从当前 Provider 拉取远端模型清单。',
                  ),
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '共 ${modelItems.length} 个模型',
                                style: TextStyle(
                                  color: _secondaryTextColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                            ),
                            _buildModelActionButton(
                              svg: _kPlusSvg,
                              onPressed: _currentProfile?.readOnly == true
                                  ? null
                                  : _promptAddModel,
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
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: _surfaceColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isDarkTheme
                                  ? context.omniPalette.borderSubtle
                                  : const Color(0x1A000000),
                            ),
                          ),
                          child: modelItems.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SvgPicture.string(
                                          _kPackageSvg,
                                          width: 64,
                                          height: 64,
                                          colorFilter: ColorFilter.mode(
                                            _tertiaryTextColor,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          '请添加模型！',
                                          style: TextStyle(
                                            color: _secondaryTextColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'PingFang SC',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(10),
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

class _ProviderSwitchPopupEntry extends PopupMenuEntry<String> {
  const _ProviderSwitchPopupEntry({
    required this.width,
    required this.estimatedHeight,
    required this.profiles,
    required this.selectedProfileId,
  });

  final double width;
  final double estimatedHeight;
  final List<ModelProviderProfileSummary> profiles;
  final String selectedProfileId;

  @override
  double get height => estimatedHeight;

  @override
  bool represents(String? value) => false;

  @override
  State<_ProviderSwitchPopupEntry> createState() =>
      _ProviderSwitchPopupEntryState();
}

class _ProviderSwitchPopupEntryState extends State<_ProviderSwitchPopupEntry> {
  Widget _buildProviderTile(ModelProviderProfileSummary profile) {
    final palette = context.omniPalette;
    final selected = profile.id == widget.selectedProfileId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop(profile.id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? (_isDarkTheme(context)
                      ? palette.segmentThumb
                      : const Color(0xFFEAF3FF))
                : (_isDarkTheme(context)
                      ? palette.surfaceSecondary
                      : const Color(0xFFF8FAFD)),
            borderRadius: BorderRadius.circular(12),
            border: _isDarkTheme(context)
                ? Border.all(color: palette.borderSubtle)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: _isDarkTheme(context)
                        ? palette.textPrimary
                        : AppColors.text,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'PingFang SC',
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: _isDarkTheme(context)
                      ? palette.accentPrimary
                      : const Color(0xFF2C7FEB),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final mediaQuery = MediaQuery.of(context);
    final dynamicMaxHeight =
        (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 96)
            .clamp(120.0, widget.estimatedHeight)
            .toDouble();
    return SizedBox(
      width: widget.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dynamicMaxHeight),
        child: widget.profiles.isEmpty
            ? Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '暂无 Provider',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isDarkTheme(context)
                        ? palette.textTertiary
                        : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'PingFang SC',
                  ),
                ),
              )
            : Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.profiles.length,
                  itemBuilder: (context, index) {
                    return _buildProviderTile(widget.profiles[index]);
                  },
                ),
              ),
      ),
    );
  }
}

bool _isDarkTheme(BuildContext context) => context.isDarkTheme;

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
          decoration: const InputDecoration(hintText: '输入模型 ID'),
          onSubmitted: (_) => _close(_controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => _close(), child: const Text('取消')),
          TextButton(
            onPressed: () => _close(_controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
