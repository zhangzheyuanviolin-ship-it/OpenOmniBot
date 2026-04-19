import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/utils/cache_util.dart';
import 'package:ui/widgets/common_app_bar.dart';

/// 应用权限授权页面
class AuthorizeSettingPage extends StatefulWidget {
  const AuthorizeSettingPage({super.key});

  @override
  State<AuthorizeSettingPage> createState() => _AuthorizeSettingPageState();
}

class _AuthorizeSettingPageState extends State<AuthorizeSettingPage> with WidgetsBindingObserver {
  bool notificationEnabled = true; // 接收消息通知
  bool personalizedEnabled = true; // 个性化推荐
  
  // 权限状态
  bool _backgroundRunning = false;
  bool _overlayPermission = false;
  bool _installedAppsPermission = false;
  bool _accessibilityPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final notification = await CacheUtil.getBool("notification_enabled");
      final personalized = await CacheUtil.getBool("personalized_enabled");
      setState(() {
        notificationEnabled = notification;
        personalizedEnabled = personalized;
      });
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final backgroundRunning = await spePermission.invokeMethod('isIgnoringBatteryOptimizations') ?? false;
      final overlayPermission = await spePermission.invokeMethod('isOverlayPermission') ?? false;
      final installedAppsPermission = await spePermission.invokeMethod('isInstalledAppsPermissionGranted') ?? false;
      final accessibilityPermission = await spePermission.invokeMethod('isAccessibilityServiceEnabled') ?? false;
      
      if (mounted) {
        setState(() {
          _backgroundRunning = backgroundRunning;
          _overlayPermission = overlayPermission;
          _installedAppsPermission = installedAppsPermission;
          _accessibilityPermission = accessibilityPermission;
        });
      }
    } catch (e) {
      print('Error checking permissions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: CommonAppBar(
        title: Localizations.localeOf(context).languageCode == 'en'
            ? 'App Permission Authorization'
            : '应用权限授权',
        primary: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 通知设置组
              _buildSettingsCard([
                _buildSwitchItem(
                  title: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Receive message notifications'
                      : '接收消息通知',
                  subtitle: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Enable this to get task progress updates in time'
                      : '打开后可以及时了解任务进展',
                  value: notificationEnabled,
                  onChanged: (val) async {
                    await CacheUtil.cacheBool("notification_enabled", val);
                    setState(() {
                      notificationEnabled = val;
                    });
                  },
                )
              ]),
              
              const SizedBox(height: 10),
              
              // 权限设置组
              _buildSettingsCard([
                _buildPermissionItem(
                  title: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Background running permission'
                      : '后台运行权限',
                  subtitle: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Omnibot can better understand your preferences while assisting'
                      : '小万可以在陪伴时更了解您的喜好',
                  isEnabled: _backgroundRunning,
                  isTop: true,
                  onTap: () {
                    spePermission.invokeMethod('openBatteryOptimizationSettings');
                  },
                ),
                _buildPermissionItem(
                  title: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Overlay permission'
                      : '悬浮窗权限',
                  subtitle: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Allow Omnibot to stay active on screen and assist anytime'
                      : '小万可在屏幕中实时活动，随时给予陪伴',
                  isEnabled: _overlayPermission,
                  onTap: () {
                    spePermission.invokeMethod('openOverlaySettings');
                  },
                ),
                _buildPermissionItem(
                  title: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Installed apps access'
                      : '应用列表读取',
                  subtitle: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Help Omnibot know what tasks it can do for you'
                      : '小万可以知道能帮你做什么事情',
                  isEnabled: _installedAppsPermission,
                  onTap: () {
                    spePermission.invokeMethod('openInstalledAppsSettings');
                  },
                ),
                _buildPermissionItem(
                  title: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Accessibility permission'
                      : '无障碍辅助权限',
                  subtitle: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Required so Omnibot can operate when executing tasks'
                      : '小万执行任务时，需要给予我操作的权限',
                  isEnabled: _accessibilityPermission,
                  isBottom: true,
                  onTap: () {
                    spePermission.invokeMethod('openAccessibilitySettings');
                  },
                ),
              ]),
              
              const SizedBox(height: 10),
              
              // 清除缓存
              _buildSettingsCard([
                _buildSimpleItem(
                  title: Localizations.localeOf(context).languageCode == 'en'
                      ? 'Clear cache'
                      : '清除缓存',
                  isTop: true,
                  isBottom: true,
                  onTap: () {
                    // TODO: 实现清除缓存
                  },
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建设置卡片
  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 4,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  /// 构建开关设置项
  Widget _buildSwitchItem({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2336),
                    fontFamily: 'PingFang SC',
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF999999),
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                ],
              ],
            ),
          ),
          FlutterSwitch(
            width: 32,
            height: 18.67,
            toggleSize: 11.3,
            padding: 3,
            activeColor: Color(0xFF202F51),
            inactiveColor: AppColors.fillStandardSecondary,
            borderRadius: 28.75,
            value: value,
            onToggle: onChanged,
          ),
        ],
      ),
    );
  }

  /// 构建权限设置项
  Widget _buildPermissionItem({
    required String title,
    required String subtitle,
    required bool isEnabled,
    bool? isTop,
    bool? isBottom,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isTop == true ? const Radius.circular(4) : Radius.zero,
          bottom: isBottom == true ? const Radius.circular(4) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1F2336),
                        fontFamily: 'PingFang SC',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF999999),
                        fontFamily: 'PingFang SC',
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Localizations.localeOf(context).languageCode == 'en'
                        ? (isEnabled ? 'Enabled' : 'Enable now')
                        : (isEnabled ? '已开启' : '去开启'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isEnabled ? const Color(0xFF999999) : const Color(0xFF3B74FF),
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: const Color(0xFF999999),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建简单设置项
  Widget _buildSimpleItem({
    required String title,
    bool? isTop,
    bool? isBottom,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isTop == true ? const Radius.circular(4) : Radius.zero,
          bottom: isBottom == true ? const Radius.circular(4) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2336),
                  fontFamily: 'SF Pro',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
