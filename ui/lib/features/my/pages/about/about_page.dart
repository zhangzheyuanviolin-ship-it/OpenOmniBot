import 'package:flutter/material.dart';
import 'package:ui/services/app_update_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/app_update_dialog.dart';
import 'package:ui/widgets/gradient_button.dart';
import 'package:ui/utils/ui.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  AppUpdateStatus? _updateStatus;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    AppUpdateService.statusNotifier.addListener(_handleUpdateStatusChanged);
    _loadVersion();
    _loadUpdateStatus();
  }

  @override
  void dispose() {
    AppUpdateService.statusNotifier.removeListener(_handleUpdateStatusChanged);
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final versionInfo = await DeviceService.getAppVersion();
      if (!mounted) return;
      if (versionInfo != null) {
        final versionName = versionInfo['versionName'] as String?;
        setState(() {
          _version = 'Version ${versionName ?? '-'}';
        });
        return;
      }
      setState(() {
        _version = 'Version -';
      });
    } catch (e) {
      print('加载版本号失败: $e');
      if (!mounted) return;
      setState(() {
        _version = 'Version -';
      });
    }
  }

  Future<void> _loadUpdateStatus() async {
    await AppUpdateService.initialize();
    if (!mounted) return;
    setState(() {
      _updateStatus = AppUpdateService.statusNotifier.value;
    });
  }

  void _handleUpdateStatusChanged() {
    if (!mounted) return;
    setState(() {
      _updateStatus = AppUpdateService.statusNotifier.value;
    });
  }

  Future<void> _handleCheckUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final status = await AppUpdateService.checkNow();
      if (!mounted) return;
      if (status == null) {
        showToast('检查更新失败', type: ToastType.error);
        return;
      }
      if (status.hasUpdate) {
        await showAppUpdateDialog(context, status);
        return;
      }
      showToast('已是最新版', type: ToastType.success);
    } catch (_) {
      if (!mounted) return;
      showToast('检查更新失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  Future<void> _handlePrimaryAction() async {
    final status = _updateStatus;
    if (status != null && status.hasUpdate) {
      await showAppUpdateDialog(context, status);
      return;
    }
    await _handleCheckUpdate();
  }

  String _buildUpdateHint() {
    final status = _updateStatus;
    if (status == null) {
      return '检查 GitHub Release 获取最新版本';
    }
    if (status.hasUpdate) {
      return '发现新版本 ${status.latestVersionLabel}';
    }
    if (status.checkedAt > 0) {
      return '已是最新版';
    }
    return '检查 GitHub Release 获取最新版本';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : Colors.white,
      appBar: const CommonAppBar(title: '关于小万', primary: true),
      body: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              // Logo
              SizedBox(
                width: 167,
                height: 120,
                child: Center(
                  child: Image.asset(
                    'assets/my/about_icon.png',
                    width: 167,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.image,
                        size: 96,
                        color: AppColors.primaryBlue,
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 描述文字
              Text(
                '小万，是一款以智能对话为核心的手机AI助\n手，通过语义理解与持续学习能力，协助用户\n完成信息处理、决策辅助和日常管理。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: context.isDarkTheme
                      ? palette.textSecondary
                      : AppColors.text70,
                  letterSpacing: 0.39,
                  height: 1.5,
                ),
              ),

              const Spacer(),

              // 版本号
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _version,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.33,
                          height: 1.5,
                        ).copyWith(
                          color: context.isDarkTheme
                              ? palette.textSecondary
                              : AppColors.text70,
                        ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              Text(
                _buildUpdateHint(),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                      height: 1.5,
                    ).copyWith(
                      color: context.isDarkTheme
                          ? palette.textTertiary
                          : AppColors.text50,
                    ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                text: _isCheckingUpdate
                    ? '检查中...'
                    : (_updateStatus?.hasUpdate == true ? '查看新版本' : '检查更新'),
                width: 180,
                height: 44,
                enabled: !_isCheckingUpdate,
                onTap: () {
                  _handlePrimaryAction();
                },
              ),
              const SizedBox(height: 154),
            ],
          ),
        ),
      ),
    );
  }
}
