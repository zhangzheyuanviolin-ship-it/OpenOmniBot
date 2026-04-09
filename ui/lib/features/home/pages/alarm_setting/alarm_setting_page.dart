import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class AlarmSettingPage extends StatefulWidget {
  const AlarmSettingPage({super.key});

  @override
  State<AlarmSettingPage> createState() => _AlarmSettingPageState();
}

class _AlarmSettingPageState extends State<AlarmSettingPage> {
  static const String _sourceDefault = 'default';
  static const String _sourceLocalMp3 = 'local_mp3';
  static const String _sourceRemoteMp3 = 'remote_mp3_url';

  final TextEditingController _remoteUrlController = TextEditingController();

  String _source = _sourceDefault;
  String _localPath = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAlarmSettings();
  }

  @override
  void dispose() {
    _remoteUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadAlarmSettings() async {
    final payload = await AssistsMessageService.getAlarmSettings();
    if (!mounted) return;

    setState(() {
      _source = (payload['source'] ?? _sourceDefault).toString();
      _localPath = (payload['localPath'] ?? '').toString();
      _remoteUrlController.text = (payload['remoteUrl'] ?? '').toString();
      _loading = false;
    });
  }

  Future<bool> _ensureAudioReadPermission() async {
    final info = await DeviceService.getDeviceInfo();
    final sdkVersion = (info?['sdkVersion'] as num?)?.toInt() ?? 0;
    final permission = sdkVersion >= 33
        ? 'android.permission.READ_MEDIA_AUDIO'
        : 'android.permission.READ_EXTERNAL_STORAGE';
    return requestPermission([permission]);
  }

  Future<void> _pickLocalMp3() async {
    final granted = await _ensureAudioReadPermission();
    if (!granted) {
      showToast('读取音频权限未授予', type: ToastType.warning);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }
    final path = result.files.first.path;
    if (path == null || path.isEmpty) {
      showToast('文件路径无效，请重新选择', type: ToastType.warning);
      return;
    }

    if (!mounted) return;
    setState(() {
      _localPath = path;
      _source = _sourceLocalMp3;
    });
  }

  bool _validateBeforeSave() {
    if (_source == _sourceLocalMp3 && _localPath.trim().isEmpty) {
      showToast('请先选择本地 mp3 文件', type: ToastType.warning);
      return false;
    }

    if (_source == _sourceRemoteMp3) {
      final url = _remoteUrlController.text.trim();
      if (!(url.startsWith('http://') || url.startsWith('https://'))) {
        showToast('请输入 http(s) 开头的 mp3 直链', type: ToastType.warning);
        return false;
      }
    }

    return true;
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    if (!_validateBeforeSave()) return;

    setState(() {
      _saving = true;
    });

    final payload = await AssistsMessageService.saveAlarmSettings(
      source: _source,
      localPath: _source == _sourceLocalMp3 ? _localPath.trim() : null,
      remoteUrl: _source == _sourceRemoteMp3
          ? _remoteUrlController.text.trim()
          : null,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
    });

    if (payload['success'] == true) {
      showToast('闹钟设置已保存', type: ToastType.success);
      return;
    }

    final error = (payload['message'] ?? payload['summary'] ?? '保存失败')
        .toString();
    showToast(error, type: ToastType.error);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : AppColors.background,
      appBar: const CommonAppBar(title: '闹钟设置', primary: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSourceCard(),
                    const SizedBox(height: 10),
                    if (_source == _sourceLocalMp3) _buildLocalFileCard(),
                    if (_source == _sourceRemoteMp3) _buildRemoteUrlCard(),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveSettings,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(_saving ? '保存中...' : '保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSourceCard() {
    final palette = context.omniPalette;
    return Container(
      decoration: BoxDecoration(
        color: context.isDarkTheme ? palette.surfacePrimary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: context.isDarkTheme
            ? Border.all(color: palette.borderSubtle)
            : null,
        boxShadow: context.isDarkTheme
            ? [
                BoxShadow(
                  color: palette.shadowColor.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [AppColors.boxShadow],
      ),
      child: Column(
        children: [
          _buildSourceTile(
            value: _sourceDefault,
            title: '系统默认铃声',
            subtitle: '无需额外配置，兼容性最好',
          ),
          _buildSourceTile(
            value: _sourceLocalMp3,
            title: '本地 mp3',
            subtitle: '选择手机内 mp3 作为闹钟铃声',
          ),
          _buildSourceTile(
            value: _sourceRemoteMp3,
            title: 'mp3 直链',
            subtitle: '使用 http(s) 直链播放在线 mp3',
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTile({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final palette = context.omniPalette;
    return RadioListTile<String>(
      value: value,
      groupValue: _source,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      activeColor: AppColors.primaryBlue,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.isDarkTheme ? palette.textPrimary : AppColors.text,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: context.isDarkTheme ? palette.textSecondary : AppColors.text70,
        ),
      ),
      onChanged: (next) {
        if (next == null) return;
        setState(() {
          _source = next;
        });
      },
    );
  }

  Widget _buildLocalFileCard() {
    final palette = context.omniPalette;
    final displayPath = _localPath.isEmpty ? '未选择文件' : _localPath;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.isDarkTheme ? palette.surfacePrimary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: context.isDarkTheme
            ? Border.all(color: palette.borderSubtle)
            : null,
        boxShadow: context.isDarkTheme
            ? [
                BoxShadow(
                  color: palette.shadowColor.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [AppColors.boxShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本地文件',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.isDarkTheme ? palette.textPrimary : AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayPath,
            style: TextStyle(
              fontSize: 12,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : AppColors.text70,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _pickLocalMp3,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryBlue,
              side: const BorderSide(color: AppColors.primaryBlue),
            ),
            child: const Text('选择 mp3 文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteUrlCard() {
    final palette = context.omniPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.isDarkTheme ? palette.surfacePrimary : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: context.isDarkTheme
            ? Border.all(color: palette.borderSubtle)
            : null,
        boxShadow: context.isDarkTheme
            ? [
                BoxShadow(
                  color: palette.shadowColor.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [AppColors.boxShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'mp3 直链',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.isDarkTheme ? palette.textPrimary : AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _remoteUrlController,
            decoration: const InputDecoration(
              hintText: 'https://example.com/alarm.mp3',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
