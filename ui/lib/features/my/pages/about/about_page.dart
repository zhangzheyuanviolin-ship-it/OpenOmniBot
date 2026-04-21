import 'package:flutter/material.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/services/app_update_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/services/device_service.dart';
import 'package:ui/services/storage_service.dart';
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
  static const String _omniFlowDebugUnlockedKey = 'omni_flow_debug_unlocked';

  String _version = '';
  AppUpdateStatus? _updateStatus;
  bool _isCheckingUpdate = false;
  int _versionTapCount = 0;

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
      debugPrint('加载版本号失败: $e');
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
        showToast(context.trLegacy('检查更新失败'), type: ToastType.error);
        return;
      }
      if (status.hasUpdate) {
        await showAppUpdateDialog(context, status);
        return;
      }
      showToast(context.trLegacy('已是最新版'), type: ToastType.success);
    } catch (_) {
      if (!mounted) return;
      showToast(context.trLegacy('检查更新失败'), type: ToastType.error);
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
      return context.trLegacy('检查 GitHub Release 获取最新版本');
    }
    if (status.hasUpdate) {
      return '${context.trLegacy('发现新版本')} ${status.latestVersionLabel}';
    }
    if (status.checkedAt > 0) {
      return context.trLegacy('已是最新版');
    }
    return context.trLegacy('检查 GitHub Release 获取最新版本');
  }

  Future<void> _handleVersionTap() async {
    final alreadyUnlocked =
        StorageService.getBool(
          _omniFlowDebugUnlockedKey,
          defaultValue: false,
        ) ??
        false;
    if (alreadyUnlocked) {
      showToast('OmniFlow 轨迹执行 [debug] 已解锁，请返回设置页访问');
      return;
    }
    final nextCount = _versionTapCount + 1;
    if (nextCount >= 5) {
      await StorageService.setBool(_omniFlowDebugUnlockedKey, true);
      if (!mounted) return;
      setState(() {
        _versionTapCount = 0;
      });
      showToast('已解锁 OmniFlow 轨迹执行 [debug]，请返回设置页访问');
      return;
    }
    if (!mounted) return;
    setState(() {
      _versionTapCount = nextCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final darkAccent = HSLColor.fromColor(palette.accentPrimary);
    final updateButtonGradient = context.isDarkTheme
        ? <Color>[
            darkAccent
                .withSaturation((darkAccent.saturation * 0.72).clamp(0.0, 1.0))
                .withLightness((darkAccent.lightness - 0.08).clamp(0.0, 1.0))
                .toColor(),
            darkAccent
                .withSaturation((darkAccent.saturation * 0.66).clamp(0.0, 1.0))
                .withLightness((darkAccent.lightness + 0.02).clamp(0.0, 1.0))
                .toColor(),
          ]
        : const <Color>[Color(0xFF1930D9), Color(0xFF2DA5F0)];
    final updateButtonTextColor = context.isDarkTheme
        ? (ThemeData.estimateBrightnessForColor(updateButtonGradient.last) ==
                  Brightness.dark
              ? Colors.white
              : const Color(0xFF171916))
        : Colors.white;
    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : Colors.white,
      appBar: CommonAppBar(title: context.l10n.settingsAboutTitle, primary: true),
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
                context.l10n.aboutDescription,
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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleVersionTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
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
                    ? context.trLegacy('检查中...')
                    : (_updateStatus?.hasUpdate == true ? context.trLegacy('查看新版本') : context.trLegacy('检查更新')),
                width: 180,
                height: 44,
                gradientColors: updateButtonGradient,
                textStyle: TextStyle(
                  color: updateButtonTextColor,
                  fontSize: 16,
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  letterSpacing: 0.5,
                ),
                enabled: !_isCheckingUpdate,
                onTap: () {
                  _handlePrimaryAction();
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  GoRouterManager.push('/my/about/request-logs');
                },
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(context.trLegacy('请求日志')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(180, 44),
                  foregroundColor: context.isDarkTheme
                      ? palette.textPrimary
                      : AppColors.text,
                  side: BorderSide(
                    color: context.isDarkTheme
                        ? const Color(0xFF2B3444)
                        : const Color(0xFFD6E0EE),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 154),
            ],
          ),
        ),
      ),
    );
  }
}
