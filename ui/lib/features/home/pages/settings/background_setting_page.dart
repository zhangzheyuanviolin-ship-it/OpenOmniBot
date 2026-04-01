import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/app_background_widgets.dart';
import 'package:ui/widgets/common_app_bar.dart';

class BackgroundSettingPage extends StatefulWidget {
  const BackgroundSettingPage({super.key});

  @override
  State<BackgroundSettingPage> createState() => _BackgroundSettingPageState();
}

class _BackgroundSettingPageState extends State<BackgroundSettingPage> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _remoteUrlController = TextEditingController();

  late AppBackgroundConfig _savedConfig;
  late AppBackgroundConfig _draftConfig;
  BackgroundPreviewKind _previewKind = BackgroundPreviewKind.chat;
  bool _saving = false;
  String? _sessionImportedLocalPath;

  bool get _isDirty =>
      _savedConfig.toJson().toString() != _draftConfig.toJson().toString();

  AppBackgroundConfig get _previewConfig {
    return _draftConfig.copyWith(enabled: _draftConfig.hasResolvedImage);
  }

  @override
  void initState() {
    super.initState();
    _savedConfig = AppBackgroundService.current;
    _draftConfig = _savedConfig;
    _remoteUrlController.text = _draftConfig.remoteImageUrl;
    _remoteUrlController.addListener(_handleRemoteUrlChanged);
  }

  @override
  void dispose() {
    _remoteUrlController
      ..removeListener(_handleRemoteUrlChanged)
      ..dispose();
    final sessionImportedLocalPath = _sessionImportedLocalPath;
    if (sessionImportedLocalPath != null &&
        sessionImportedLocalPath != _savedConfig.localImagePath) {
      AppBackgroundService.deleteManagedLocalImage(sessionImportedLocalPath);
    }
    super.dispose();
  }

  void _handleRemoteUrlChanged() {
    if (_draftConfig.sourceType != AppBackgroundSourceType.remote) {
      return;
    }
    final nextUrl = _remoteUrlController.text.trim();
    if (nextUrl == _draftConfig.remoteImageUrl) {
      return;
    }
    setState(() {
      _draftConfig = _draftConfig.copyWith(remoteImageUrl: nextUrl);
    });
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
    } catch (error) {
      showToast('选择图片失败：$error', type: ToastType.error);
    }
  }

  void _setSourceType(AppBackgroundSourceType sourceType) {
    setState(() {
      _draftConfig = _draftConfig.copyWith(
        enabled: sourceType == AppBackgroundSourceType.none
            ? false
            : _draftConfig.enabled,
        sourceType: sourceType,
        localImagePath: sourceType == AppBackgroundSourceType.local
            ? _draftConfig.localImagePath
            : '',
        remoteImageUrl: sourceType == AppBackgroundSourceType.remote
            ? _remoteUrlController.text.trim()
            : '',
      );
    });
  }

  void _restoreDefaults() {
    final previousImported = _sessionImportedLocalPath;
    setState(() {
      _draftConfig = AppBackgroundConfig.defaults;
      _remoteUrlController.text = '';
      _sessionImportedLocalPath = null;
    });
    if (previousImported != null &&
        previousImported != _savedConfig.localImagePath) {
      AppBackgroundService.deleteManagedLocalImage(previousImported);
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final normalized = _normalizedDraft();
    final validationError = await _validateConfig(normalized);
    if (validationError != null) {
      showToast(validationError, type: ToastType.warning);
      return;
    }

    setState(() => _saving = true);
    final previousSaved = _savedConfig;
    final unusedImported = _sessionImportedLocalPath;
    try {
      if (previousSaved.sourceType == AppBackgroundSourceType.local &&
          previousSaved.localImagePath.isNotEmpty &&
          previousSaved.localImagePath != normalized.localImagePath) {
        await AppBackgroundService.deleteManagedLocalImage(
          previousSaved.localImagePath,
        );
      }
      if (unusedImported != null &&
          unusedImported != normalized.localImagePath) {
        await AppBackgroundService.deleteManagedLocalImage(unusedImported);
      }
      await AppBackgroundService.save(normalized);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedConfig = normalized;
        _draftConfig = normalized;
        _sessionImportedLocalPath = null;
      });
      showToast('背景设置已保存', type: ToastType.success);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showToast('保存失败：$error', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: '背景设置', primary: true),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSourceCard(),
              const SizedBox(height: 12),
              _buildPreviewCard(),
              const SizedBox(height: 12),
              _buildAdjustCard(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('background-reset-button'),
                      onPressed: _saving ? null : _restoreDefaults,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('background-save-button'),
                      onPressed: !_isDirty || _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(_saving ? '保存中...' : '保存'),
                    ),
                  ),
                ],
              ),
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
            showDragHint: true,
            onFocalPointChanged: (offset) {
              setState(() {
                _draftConfig = _draftConfig.copyWith(
                  focalX: offset.dx,
                  focalY: offset.dy,
                );
              });
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
              '同时作用于聊天页和 Workspace 页面',
              style: TextStyle(fontSize: 12, color: AppColors.text70),
            ),
            value: _draftConfig.enabled,
            onChanged: (value) {
              setState(() {
                _draftConfig = _draftConfig.copyWith(enabled: value);
              });
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('background-source-none'),
                label: const Text('不使用'),
                selected: sourceType == AppBackgroundSourceType.none,
                onSelected: (_) => _setSourceType(AppBackgroundSourceType.none),
              ),
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
              decoration: const InputDecoration(
                labelText: '图片直链',
                hintText: 'https://example.com/background.jpg',
                border: OutlineInputBorder(),
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
              setState(() {
                _draftConfig = _draftConfig.copyWith(blurSigma: value);
              });
            },
          ),
          _buildSliderRow(
            label: '蒙版强度',
            subtitle: '增强统一蒙版，让页面元素更干净',
            value: _draftConfig.frostOpacity,
            min: 0,
            max: 0.55,
            onChanged: (value) {
              setState(() {
                _draftConfig = _draftConfig.copyWith(frostOpacity: value);
              });
            },
          ),
          _buildSliderRow(
            label: '蒙版明暗',
            subtitle: '提亮或压暗蒙版，不会直接修改原图',
            value: _draftConfig.brightness,
            min: 0.5,
            max: 1.5,
            onChanged: (value) {
              setState(() {
                _draftConfig = _draftConfig.copyWith(brightness: value);
              });
            },
          ),
          const SizedBox(height: 4),
          Text(
            '图片位置请直接在上方预览区域里拖动调整。',
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
                value.toStringAsFixed(2),
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
}
