import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/app_background_widgets.dart';
import 'package:ui/widgets/common_app_bar.dart';

class _AppearanceTextColorPreset {
  final String label;
  final String hex;
  final Color color;

  const _AppearanceTextColorPreset({
    required this.label,
    required this.hex,
    required this.color,
  });
}

const List<_AppearanceTextColorPreset> _kAppearanceTextColorPresets =
    <_AppearanceTextColorPreset>[
      _AppearanceTextColorPreset(
        label: '白',
        hex: '#FFFFFF',
        color: Color(0xFFFFFFFF),
      ),
      _AppearanceTextColorPreset(
        label: '深灰',
        hex: '#353E53',
        color: Color(0xFF353E53),
      ),
      _AppearanceTextColorPreset(
        label: '浅蓝',
        hex: '#DCEBFF',
        color: Color(0xFFDCEBFF),
      ),
      _AppearanceTextColorPreset(
        label: '藏蓝',
        hex: '#1D3E7B',
        color: Color(0xFF1D3E7B),
      ),
      _AppearanceTextColorPreset(
        label: '青绿',
        hex: '#2F7A4A',
        color: Color(0xFF2F7A4A),
      ),
      _AppearanceTextColorPreset(
        label: '暖黄',
        hex: '#F59E0B',
        color: Color(0xFFF59E0B),
      ),
    ];

class BackgroundSettingPage extends StatefulWidget {
  const BackgroundSettingPage({super.key});

  @override
  State<BackgroundSettingPage> createState() => _BackgroundSettingPageState();
}

class _BackgroundSettingPageState extends State<BackgroundSettingPage> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _remoteUrlController = TextEditingController();
  final TextEditingController _textColorController = TextEditingController();

  late AppBackgroundConfig _savedConfig;
  late AppBackgroundConfig _draftConfig;
  AppBackgroundVisualProfile _draftVisualProfile =
      AppBackgroundVisualProfile.defaultProfile;
  BackgroundPreviewKind _previewKind = BackgroundPreviewKind.chat;
  bool _saving = false;
  String? _sessionImportedLocalPath;
  Timer? _previewProfileDebounceTimer;
  Timer? _autoSaveDebounceTimer;
  int _previewProfileToken = 0;
  int _autoSaveRequestId = 0;

  AppBackgroundConfig get _previewConfig {
    return _draftConfig;
  }

  bool _sameConfig(AppBackgroundConfig left, AppBackgroundConfig right) {
    return left.toJson().toString() == right.toJson().toString();
  }

  bool _hasUnsavedImportedLocalImage(AppBackgroundConfig snapshot) {
    final importedPath = _sessionImportedLocalPath;
    return importedPath != null && importedPath != snapshot.localImagePath;
  }

  String get _autoSaveHint => _saving ? '正在自动保存…' : '更改会自动保存';

  String? get _remoteUrlErrorText {
    if (_draftConfig.sourceType != AppBackgroundSourceType.remote) {
      return null;
    }
    final raw = _remoteUrlController.text.trim();
    if (raw.isEmpty) {
      return _draftConfig.enabled ? '请输入有效的 http(s) 图片直链' : null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return '请输入有效的 http(s) 图片直链';
    }
    return null;
  }

  String? get _textColorErrorText {
    final raw = _textColorController.text.trim();
    if (_draftConfig.chatTextColorMode != AppBackgroundTextColorMode.custom &&
        raw.isEmpty) {
      return null;
    }
    if (raw.isEmpty) {
      return '请输入 #RRGGBB 或 #AARRGGBB';
    }
    return normalizeAppBackgroundHexColor(raw) == null ? '色号格式不正确' : null;
  }

  @override
  void initState() {
    super.initState();
    _savedConfig = AppBackgroundService.current;
    _draftConfig = _savedConfig;
    _draftVisualProfile = AppBackgroundService.currentVisualProfile;
    _remoteUrlController.text = _draftConfig.remoteImageUrl;
    _textColorController.text = _draftConfig.chatTextHexColor;
    _remoteUrlController.addListener(_handleRemoteUrlChanged);
    _textColorController.addListener(_handleTextColorChanged);
    _scheduleDraftVisualProfileRefresh();
  }

  @override
  void dispose() {
    final pendingSnapshot = _normalizedDraft();
    final shouldFlushPendingDraft =
        !_sameConfig(_savedConfig, pendingSnapshot) ||
        _hasUnsavedImportedLocalImage(pendingSnapshot);
    _previewProfileDebounceTimer?.cancel();
    _autoSaveDebounceTimer?.cancel();
    if (shouldFlushPendingDraft) {
      unawaited(_flushPendingDraftOnDispose(pendingSnapshot));
    }
    _remoteUrlController
      ..removeListener(_handleRemoteUrlChanged)
      ..dispose();
    _textColorController
      ..removeListener(_handleTextColorChanged)
      ..dispose();
    super.dispose();
  }

  void _handleRemoteUrlChanged() {
    final nextUrl = _remoteUrlController.text.trim();
    if (_draftConfig.sourceType != AppBackgroundSourceType.remote ||
        nextUrl == _draftConfig.remoteImageUrl) {
      return;
    }
    _applyDraftConfig(_draftConfig.copyWith(remoteImageUrl: nextUrl));
  }

  void _handleTextColorChanged() {
    final normalized = normalizeAppBackgroundHexColor(
      _textColorController.text.trim(),
    );
    if (normalized == null ||
        (_draftConfig.chatTextColorMode == AppBackgroundTextColorMode.custom &&
            normalized == _draftConfig.chatTextHexColor)) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _applyDraftConfig(
      _draftConfig.copyWith(
        chatTextColorMode: AppBackgroundTextColorMode.custom,
        chatTextHexColor: normalized,
      ),
    );
  }

  void _applyDraftConfig(AppBackgroundConfig nextConfig) {
    if (_sameConfig(_draftConfig, nextConfig)) {
      return;
    }
    setState(() {
      _draftConfig = nextConfig;
    });
    _scheduleDraftVisualProfileRefresh();
    _scheduleAutoSave();
  }

  Future<void> _pickLocalImage() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return;
      }
      final importedPath = await AppBackgroundService.importLocalImage(
        file.path,
      );
      final previousImported = _sessionImportedLocalPath;
      if (previousImported != null &&
          previousImported != _savedConfig.localImagePath &&
          previousImported != importedPath) {
        await AppBackgroundService.deleteManagedLocalImage(previousImported);
      }
      if (!mounted) {
        if (importedPath != _savedConfig.localImagePath) {
          await AppBackgroundService.deleteManagedLocalImage(importedPath);
        }
        return;
      }
      setState(() {
        _sessionImportedLocalPath = importedPath == _savedConfig.localImagePath
            ? null
            : importedPath;
        _draftConfig = _draftConfig.copyWith(
          enabled: true,
          sourceType: AppBackgroundSourceType.local,
          localImagePath: importedPath,
          remoteImageUrl: '',
        );
        _remoteUrlController.text = '';
      });
      _scheduleDraftVisualProfileRefresh();
      _scheduleAutoSave();
    } catch (error) {
      showToast('选择图片失败：$error', type: ToastType.error);
    }
  }

  void _setSourceType(AppBackgroundSourceType sourceType) {
    _applyDraftConfig(
      _draftConfig.copyWith(
        enabled: true,
        sourceType: sourceType,
        localImagePath: sourceType == AppBackgroundSourceType.local
            ? _draftConfig.localImagePath
            : '',
        remoteImageUrl: sourceType == AppBackgroundSourceType.remote
            ? _remoteUrlController.text.trim()
            : '',
      ),
    );
  }

  AppBackgroundConfig _normalizedDraft() {
    final remoteUrl = _remoteUrlController.text.trim();
    final sourceType = _draftConfig.sourceType;
    return _draftConfig.copyWith(
      remoteImageUrl: sourceType == AppBackgroundSourceType.remote
          ? remoteUrl
          : '',
      localImagePath: sourceType == AppBackgroundSourceType.local
          ? _draftConfig.localImagePath.trim()
          : '',
      enabled:
          _draftConfig.enabled &&
          (sourceType == AppBackgroundSourceType.local
              ? _draftConfig.localImagePath.trim().isNotEmpty
              : sourceType == AppBackgroundSourceType.remote
              ? remoteUrl.isNotEmpty
              : false),
    );
  }

  Future<String?> _validateConfig(AppBackgroundConfig config) async {
    if (config.sourceType == AppBackgroundSourceType.local &&
        config.localImagePath.trim().isEmpty) {
      return '请先选择本地图片';
    }
    if (config.sourceType == AppBackgroundSourceType.local &&
        config.localImagePath.trim().isNotEmpty &&
        !await File(config.localImagePath).exists()) {
      return '本地图片不存在，请重新选择';
    }
    if (config.sourceType == AppBackgroundSourceType.remote) {
      final uri = Uri.tryParse(config.remoteImageUrl.trim());
      if (uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https') ||
          (uri.host.isEmpty)) {
        return '请输入有效的 http(s) 图片直链';
      }
    }
    return null;
  }

  void _scheduleAutoSave() {
    _autoSaveDebounceTimer?.cancel();
    final snapshot = _normalizedDraft();
    final requestId = ++_autoSaveRequestId;
    _autoSaveDebounceTimer = Timer(const Duration(milliseconds: 220), () {
      unawaited(_persistAutoSave(requestId, snapshot));
    });
  }

  Future<void> _persistAutoSave(
    int requestId,
    AppBackgroundConfig snapshot,
  ) async {
    final importedPath = _sessionImportedLocalPath;
    final validationError = await _validateConfig(snapshot);
    if (validationError != null ||
        _sameConfig(_savedConfig, snapshot)) {
      if (validationError == null) {
        await _cleanupUnsavedImportedImageIfNeeded(
          importedPath: importedPath,
          snapshot: snapshot,
        );
      }
      if (requestId == _autoSaveRequestId) {
        if (mounted) {
          setState(() => _saving = false);
        } else {
          _saving = false;
        }
      }
      return;
    }

    if (mounted && requestId == _autoSaveRequestId) {
      setState(() => _saving = true);
    } else if (!mounted) {
      _saving = true;
    }

    final previousSaved = _savedConfig;
    try {
      await AppBackgroundService.save(snapshot);
      if (requestId != _autoSaveRequestId) {
        return;
      }

      await _cleanupObsoleteLocalImages(
        previousSaved: previousSaved,
        snapshot: snapshot,
        importedPath: importedPath,
      );

      if (!mounted) {
        _savedConfig = snapshot;
        _draftConfig = snapshot;
        _sessionImportedLocalPath = null;
        return;
      }
      setState(() {
        _savedConfig = snapshot;
        _draftConfig = snapshot;
        _sessionImportedLocalPath = null;
      });
    } catch (error) {
      if (mounted && requestId == _autoSaveRequestId) {
        showToast('自动保存失败：$error', type: ToastType.error);
      }
    } finally {
      if (mounted && requestId == _autoSaveRequestId) {
        setState(() => _saving = false);
      } else if (!mounted) {
        _saving = false;
      }
    }
  }

  Future<void> _flushPendingDraftOnDispose(AppBackgroundConfig snapshot) async {
    final importedPath = _sessionImportedLocalPath;
    final validationError = await _validateConfig(snapshot);
    if (validationError != null) {
      return;
    }
    if (_sameConfig(_savedConfig, snapshot)) {
      await _cleanupUnsavedImportedImageIfNeeded(
        importedPath: importedPath,
        snapshot: snapshot,
      );
      return;
    }

    final previousSaved = _savedConfig;
    try {
      await AppBackgroundService.save(snapshot);
      await _cleanupObsoleteLocalImages(
        previousSaved: previousSaved,
        snapshot: snapshot,
        importedPath: importedPath,
      );
      _savedConfig = snapshot;
      _draftConfig = snapshot;
      _sessionImportedLocalPath = null;
    } catch (_) {
      // Silently skip persistence failures while the page is disposing.
    }
  }

  Future<void> _cleanupObsoleteLocalImages({
    required AppBackgroundConfig previousSaved,
    required AppBackgroundConfig snapshot,
    required String? importedPath,
  }) async {
    if (previousSaved.sourceType == AppBackgroundSourceType.local &&
        previousSaved.localImagePath.isNotEmpty &&
        previousSaved.localImagePath != snapshot.localImagePath) {
      await AppBackgroundService.deleteManagedLocalImage(
        previousSaved.localImagePath,
      );
    }
    await _cleanupUnsavedImportedImageIfNeeded(
      importedPath: importedPath,
      snapshot: snapshot,
    );
    _sessionImportedLocalPath = null;
  }

  Future<void> _cleanupUnsavedImportedImageIfNeeded({
    required String? importedPath,
    required AppBackgroundConfig snapshot,
  }) async {
    if (importedPath == null || importedPath == snapshot.localImagePath) {
      return;
    }
    await AppBackgroundService.deleteManagedLocalImage(importedPath);
    _sessionImportedLocalPath = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: '外观设置', primary: true),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  _autoSaveHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _buildSourceCard(),
              const SizedBox(height: 12),
              _buildPreviewCard(),
              const SizedBox(height: 12),
              _buildAdjustCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '效果预览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                children: BackgroundPreviewKind.values.map((kind) {
                  final selected = _previewKind == kind;
                  final label = kind == BackgroundPreviewKind.chat
                      ? '聊天预览'
                      : 'Workspace 预览';
                  return ChoiceChip(
                    key: ValueKey('background-preview-kind-${kind.name}'),
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _previewKind = kind);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppBackgroundPreview(
            config: _previewConfig,
            kind: _previewKind,
            visualProfile: _draftVisualProfile,
            showDragHint: true,
            onViewportChanged: (offset, imageScale) {
              _applyDraftConfig(
                _draftConfig.copyWith(
                  focalX: offset.dx,
                  focalY: offset.dy,
                  imageScale: imageScale,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard() {
    final localPath = _draftConfig.localImagePath.trim();
    final sourceType = _draftConfig.sourceType;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '启用背景图',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            subtitle: const Text(
              '同时作用于聊天页和 Workspace 页面，并自动保存',
              style: TextStyle(fontSize: 12, color: AppColors.text70),
            ),
            value: _draftConfig.enabled,
            onChanged: (value) {
              _applyDraftConfig(_draftConfig.copyWith(enabled: value));
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('background-source-local'),
                label: const Text('本地图片'),
                selected: sourceType == AppBackgroundSourceType.local,
                onSelected: (_) =>
                    _setSourceType(AppBackgroundSourceType.local),
              ),
              ChoiceChip(
                key: const ValueKey('background-source-remote'),
                label: const Text('图片直链'),
                selected: sourceType == AppBackgroundSourceType.remote,
                onSelected: (_) =>
                    _setSourceType(AppBackgroundSourceType.remote),
              ),
            ],
          ),
          if (sourceType == AppBackgroundSourceType.local) ...[
            const SizedBox(height: 12),
            Text(
              localPath.isEmpty ? '尚未选择本地图片' : localPath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.text70),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('background-pick-local-image'),
              onPressed: _pickLocalImage,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(localPath.isEmpty ? '选择图片' : '重新选择'),
            ),
          ],
          if (sourceType == AppBackgroundSourceType.remote) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('background-remote-url-field'),
              controller: _remoteUrlController,
              decoration: InputDecoration(
                labelText: '图片直链',
                hintText: 'https://example.com/background.jpg',
                border: OutlineInputBorder(),
                errorText: _remoteUrlErrorText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdjustCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '效果调整',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: '背景柔化',
            subtitle: '调节图片上方蒙版的柔化程度',
            value: _draftConfig.blurSigma,
            min: 0,
            max: 24,
            onChanged: (value) {
              _applyDraftConfig(_draftConfig.copyWith(blurSigma: value));
            },
          ),
          _buildSliderRow(
            label: '蒙版强度',
            subtitle: '增强统一蒙版，让页面元素更干净',
            value: _draftConfig.frostOpacity,
            min: 0,
            max: 0.55,
            onChanged: (value) {
              _applyDraftConfig(_draftConfig.copyWith(frostOpacity: value));
            },
          ),
          _buildSliderRow(
            label: '蒙版明暗',
            subtitle: '提亮或压暗蒙版，不会直接修改原图',
            value: _draftConfig.brightness,
            min: 0.5,
            max: 1.5,
            onChanged: (value) {
              _applyDraftConfig(_draftConfig.copyWith(brightness: value));
            },
          ),
          _buildSliderRow(
            label: '聊天文本大小',
            subtitle: '仅调整用户消息、AI 回复与思考区字号',
            value: _draftConfig.chatTextSize,
            min: 12,
            max: 22,
            valueFormatter: (value) => '${value.toStringAsFixed(1)}sp',
            onChanged: (value) {
              _applyDraftConfig(_draftConfig.copyWith(chatTextSize: value));
            },
          ),
          const SizedBox(height: 8),
          _buildTextColorSection(),
          const SizedBox(height: 6),
          Text(
            '图片可直接在上方预览里拖动和双指缩放，预览会尽量贴近实际效果。',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String Function(double value)? valueFormatter,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                valueFormatter?.call(value) ?? value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 12, color: AppColors.text70),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.text70),
          ),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildTextColorSection() {
    final selectedHex = normalizeAppBackgroundHexColor(
      _draftConfig.chatTextHexColor,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '聊天文本颜色',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '默认会自动跟随背景明暗，也可以改成固定颜色',
          style: TextStyle(fontSize: 12, color: AppColors.text70),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              key: const ValueKey('appearance-text-color-auto'),
              label: const Text('自动'),
              selected:
                  _draftConfig.chatTextColorMode ==
                  AppBackgroundTextColorMode.auto,
              onSelected: (_) {
                _textColorController.text = '';
                _applyDraftConfig(
                  _draftConfig.copyWith(
                    chatTextColorMode: AppBackgroundTextColorMode.auto,
                    chatTextHexColor: '',
                  ),
                );
              },
            ),
            ..._kAppearanceTextColorPresets.map((preset) {
              final selected =
                  _draftConfig.chatTextColorMode ==
                      AppBackgroundTextColorMode.custom &&
                  selectedHex == preset.hex;
              return InkWell(
                key: ValueKey('appearance-text-color-${preset.hex}'),
                onTap: () {
                  _textColorController.text = preset.hex;
                  _applyDraftConfig(
                    _draftConfig.copyWith(
                      chatTextColorMode: AppBackgroundTextColorMode.custom,
                      chatTextHexColor: preset.hex,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: preset.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.primaryBlue
                          : const Color(0xFFD9E2EF),
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('appearance-text-color-field'),
          controller: _textColorController,
          decoration: InputDecoration(
            labelText: '自定义色号',
            hintText: '#FFFFFF 或 #FF112233',
            border: const OutlineInputBorder(),
            errorText: _textColorErrorText,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: child,
    );
  }

  void _scheduleDraftVisualProfileRefresh() {
    final previewConfig = _previewConfig;
    _previewProfileDebounceTimer?.cancel();
    final fallbackProfile = AppBackgroundVisualProfile.derive(
      config: previewConfig,
    );
    if (mounted) {
      setState(() {
        _draftVisualProfile = fallbackProfile;
      });
    } else {
      _draftVisualProfile = fallbackProfile;
    }
    final token = ++_previewProfileToken;
    _previewProfileDebounceTimer = Timer(const Duration(milliseconds: 140), () {
      unawaited(_refreshDraftVisualProfile(token, previewConfig));
    });
  }

  Future<void> _refreshDraftVisualProfile(
    int token,
    AppBackgroundConfig previewConfig,
  ) async {
    final analyzed = await AppBackgroundService.analyzeVisualProfile(
      previewConfig,
    );
    if (!mounted || token != _previewProfileToken) {
      return;
    }
    setState(() {
      _draftVisualProfile = analyzed;
    });
  }
}
