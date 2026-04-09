import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/cache_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/image_util.dart';
import 'package:ui/widgets/common_app_bar.dart';

/// 应用权限授权页面
class CompanionSettingPage extends StatefulWidget {
  const CompanionSettingPage({super.key});

  @override
  State<CompanionSettingPage> createState() => _CompanionSettingPageState();
}

class _CompanionSettingPageState extends State<CompanionSettingPage> {
  bool _isLoading = false;
  List<AppInfo> _appInfos = [];

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 获取设备上已安装的应用列表
      final installedApps =
          await AssistsMessageService.getInstalledApplicationsWithIconUpdate();

      if (installedApps.isEmpty) {
        print('从原生获取已安装应用列表失败或为空');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;

      // 预缓存应用图标
      final appIconMap = await ImageUtil.batchLoadAppIcons(
        installedApps.map((app) => app['package_name'] as String).toSet(),
        context,
      );

      // 将已安装应用转换为 AppInfo 列表
      List<AppInfo> loadedAppInfos = [];
      for (final app in installedApps) {
        final packageName = app['package_name'] as String?;
        final appName = app['app_name'] as String?;

        if (packageName == null || packageName.isEmpty) continue;

        loadedAppInfos.add(
          AppInfo(
            packageName: packageName,
            appName: appName ?? '',
            appIcon: appIconMap[packageName],
          ),
        );
      }

      final blockedApps = await CacheService.getStringList(
        'companion_blocked_apps',
      );
      print('已禁用的应用列表(黑名单): $blockedApps');
      loadedAppInfos = loadedAppInfos.map((appInfo) {
        return AppInfo(
          packageName: appInfo.packageName,
          appName: appInfo.appName,
          appIcon: appInfo.appIcon,
          isAuthorized: !blockedApps.contains(appInfo.packageName),
        );
      }).toList();
      print('加载陪伴授权状态完成，应用数: ${loadedAppInfos.length}');

      setState(() {
        _appInfos = loadedAppInfos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('加载AppInfo失败: $e');
      return;
    }
  }

  void _onToggleAuthorization(int index, bool isAuthorized) async {
    try {
      setState(() {
        _appInfos[index].isAuthorized = isAuthorized;
      });
      final blockedApps = _appInfos
          .where((app) => !app.isAuthorized)
          .map((app) => app.packageName)
          .toList();
      await CacheService.setStringList('companion_blocked_apps', blockedApps);
      print('保存: 已禁用的应用列表(黑名单): $blockedApps');
    } catch (e) {
      print('保存陪伴授权状态失败: $e');
    }
  }

  BoxDecoration _buildCardDecoration() {
    final palette = context.omniPalette;
    return BoxDecoration(
      color: context.isDarkTheme ? palette.surfacePrimary : Colors.white,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      border: context.isDarkTheme
          ? Border.all(color: palette.borderSubtle)
          : null,
      boxShadow: context.isDarkTheme
          ? [
              BoxShadow(
                color: palette.shadowColor.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : const Color(0xFFF6F8FA),
      appBar: const CommonAppBar(title: '应用权限授权', primary: true),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _buildCardDecoration(),
                child: Center(
                  child: Column(
                    children: [
                      SvgPicture.asset(
                        height: 24,
                        width: 24,
                        'assets/home/companion_setting_icon.svg',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '陪伴权限管理',
                        style: TextStyle(
                          color: context.isDarkTheme
                              ? palette.textPrimary
                              : AppColors.text,
                          fontSize: 20,
                          fontFamily: 'PingFang SC',
                          fontWeight: FontWeight.w500,
                          height: 1.10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        constraints: BoxConstraints(maxWidth: 235),
                        child: Text(
                          '关闭对应的授权后，小万仍会显示，但不会展示任务执行内容',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.isDarkTheme
                                ? palette.textSecondary
                                : const Color(0xFF999999),
                            fontSize: 14,
                            fontFamily: 'PingFang SC',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: _buildCardDecoration(),
                  child: Column(
                    children: [
                      ListView.builder(
                        physics: NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: _appInfos.length,
                        itemBuilder: (context, index) {
                          final appInfo = _appInfos[index];
                          return _buildListItem(appInfo, index);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(AppInfo appInfo, int index) {
    return Padding(
      padding: EdgeInsets.only(
        top: index == 0 ? 12 : 7,
        bottom: index == _appInfos.length - 1 ? 12 : 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (appInfo.appIcon != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image(
                image: appInfo.appIcon!,
                width: 16,
                height: 16,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: context.isDarkTheme
                          ? context.omniPalette.surfaceSecondary
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Icon(
                      Icons.apps,
                      size: 14,
                      color: context.isDarkTheme
                          ? context.omniPalette.textSecondary
                          : Colors.grey[600],
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: context.isDarkTheme
                    ? context.omniPalette.surfaceSecondary
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
              child: Icon(
                Icons.apps,
                size: 14,
                color: context.isDarkTheme
                    ? context.omniPalette.textSecondary
                    : Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              appInfo.appName.isNotEmpty
                  ? appInfo.appName
                  : appInfo.packageName,
              style: TextStyle(
                color: context.isDarkTheme
                    ? context.omniPalette.textPrimary
                    : AppColors.text,
                fontSize: 14,
                fontFamily: 'PingFang SC',
                fontWeight: FontWeight.w500,
                height: 1.57,
              ),
            ),
          ),
          FlutterSwitch(
            width: 32,
            height: 18.4,
            toggleSize: 11.3,
            padding: 3,
            activeColor: context.isDarkTheme
                ? context.omniPalette.accentPrimary
                : const Color(0xFF202F51),
            inactiveColor: context.isDarkTheme
                ? context.omniPalette.surfaceElevated
                : AppColors.fillStandardSecondary,
            borderRadius: 28.75,
            value: appInfo.isAuthorized,
            onToggle: (val) {
              _onToggleAuthorization(index, val);
            },
          ),
        ],
      ),
    );
  }
}

class AppInfo {
  final String packageName;
  final String appName;
  final ImageProvider? appIcon;
  bool isAuthorized;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.appIcon,
    this.isAuthorized = true,
  });
}
