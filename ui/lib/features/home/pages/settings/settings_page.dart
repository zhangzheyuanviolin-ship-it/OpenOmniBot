import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/data_sync_service.dart';
import 'package:ui/services/hide_from_recents_service.dart';
import 'package:ui/services/mcp_server_service.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/services/workspace_memory_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/cache_util.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool vibrationEnabled = true;
  bool hideFromRecentsEnabled = false;
  bool _autoBackToChatAfterTaskEnabled = true;
  bool _mcpEnabled = false;
  bool _mcpLoaded = false;
  bool _mcpBusy = false;
  McpServerInfo? _mcpInfo;
  bool _workspaceMemoryLoaded = false;
  WorkspaceMemoryEmbeddingConfig? _embeddingConfig;
  DataSyncStatus? _dataSyncStatus;
  StreamSubscription<AgentAiConfigChangedEvent>? _configChangedSubscription;

  @override
  void initState() {
    super.initState();
    _autoBackToChatAfterTaskEnabled =
        StorageService.getBool(
          StorageService.kAutoBackToChatAfterTaskKey,
          defaultValue: true,
        ) ??
        true;
    _loadVibrationState();
    _loadHideFromRecentsState();
    _loadAutoBackToChatAfterTaskState();
    _loadMcpServerState();
    _loadWorkspaceMemoryState();
    _loadDataSyncStatus();
    _configChangedSubscription = AssistsMessageService
        .agentAiConfigChangedStream
        .listen((event) {
          if (event.source != 'file' || !mounted) {
            return;
          }
          _loadWorkspaceMemoryState();
        });
  }

  Future<void> _loadDataSyncStatus() async {
    try {
      final status = await DataSyncService.getStatus();
      if (!mounted) return;
      setState(() {
        _dataSyncStatus = status;
      });
    } catch (e) {
      debugPrint('Load data sync status failed: $e');
    }
  }

  @override
  void dispose() {
    _configChangedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadVibrationState() async {
    try {
      final enabled = await CacheUtil.getBool(
        'app_vibrate',
        defaultValue: true,
      );
      setState(() {
        vibrationEnabled = enabled;
      });
      debugPrint('Vibration state loaded: $vibrationEnabled');
    } catch (e) {
      debugPrint('Error loading vibration state: $e');
    }
  }

  Future<void> _loadHideFromRecentsState() async {
    try {
      final enabled =
          StorageService.getBool('hide_from_recents', defaultValue: false) ??
          false;
      setState(() {
        hideFromRecentsEnabled = enabled;
      });
    } catch (e) {
      debugPrint('Error loading hide from recents state: $e');
    }
  }

  Future<void> _onHideFromRecentsChanged(bool value) async {
    setState(() {
      hideFromRecentsEnabled = value;
    });

    final success = await HideFromRecentsService.setExcludeFromRecents(value);
    if (!success) {
      if (!mounted) return;
      setState(() {
        hideFromRecentsEnabled = !value;
      });
      showToast(
        LegacyTextLocalizer.isEnglish
            ? 'Failed to update hide-from-recents'
            : '设置后台隐藏失败',
        type: ToastType.error,
      );
    }
  }

  Future<void> _loadAutoBackToChatAfterTaskState() async {
    try {
      final enabled = await StorageService.isAutoBackToChatAfterTaskEnabled();
      if (!mounted) return;
      if (_autoBackToChatAfterTaskEnabled == enabled) return;
      setState(() {
        _autoBackToChatAfterTaskEnabled = enabled;
      });
    } catch (e) {
      debugPrint('Error loading auto back to chat setting: $e');
    }
  }

  Future<void> _onAutoBackToChatAfterTaskChanged(bool value) async {
    try {
      await StorageService.setAutoBackToChatAfterTaskEnabled(value);
      final synced =
          await AssistsMessageService.setAutoBackToChatAfterTaskEnabled(value);
      if (!synced) {
        throw Exception('native_sync_failed');
      }
      if (!mounted) return;
      setState(() {
        _autoBackToChatAfterTaskEnabled = value;
      });
      showToast(
        LegacyTextLocalizer.isEnglish
            ? (value
                ? 'The app will return to chat after tasks finish'
                : 'The app will stay on the current page after tasks finish')
            : (value ? '任务完成后将自动返回聊天' : '任务完成后将停留在当前页面'),
      );
    } catch (e) {
      if (!mounted) return;
      showToast(
        LegacyTextLocalizer.isEnglish ? 'Failed to save settings' : '设置失败',
        type: ToastType.error,
      );
    }
  }

  Future<void> _loadMcpServerState() async {
    try {
      final info = await McpServerService.getState();
      if (!mounted) return;
      setState(() {
        _mcpInfo = info;
        _mcpEnabled = info?.enabled == true;
        _mcpLoaded = true;
      });
    } catch (e) {
      debugPrint('Load MCP state failed: $e');
      if (!mounted) return;
      setState(() {
        _mcpLoaded = true;
      });
    }
  }

  Future<void> _loadWorkspaceMemoryState() async {
    try {
      final results = await Future.wait([
        WorkspaceMemoryService.getEmbeddingConfig(),
        WorkspaceMemoryService.getRollupStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _embeddingConfig = results[0] as WorkspaceMemoryEmbeddingConfig;
        _workspaceMemoryLoaded = true;
      });
    } catch (e) {
      debugPrint('Load workspace memory state failed: $e');
      if (!mounted) return;
      setState(() {
        _workspaceMemoryLoaded = true;
      });
    }
  }

  Future<void> _toggleMcpServer(bool enable) async {
    if (_mcpBusy) return;
    setState(() {
      _mcpBusy = true;
      _mcpEnabled = enable;
    });
    try {
      final info = await McpServerService.setEnabled(enable);
      if (!mounted) return;
      setState(() {
        _mcpInfo = info;
        _mcpEnabled = info?.enabled == true;
      });
      if (enable) {
        final endpoint = info?.endpoint ?? '';
        if (endpoint.isNotEmpty) {
          showToast(
          LegacyTextLocalizer.localize('MCP 已开启：$endpoint'),
          type: ToastType.success,
        );
        }
      } else {
        showToast(
          LegacyTextLocalizer.isEnglish ? 'MCP disabled' : 'MCP 已关闭',
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      showToast(
        e.message ??
            (LegacyTextLocalizer.isEnglish
                ? 'Failed to toggle MCP'
                : 'MCP 开关失败'),
        type: ToastType.error,
      );
      setState(() {
        _mcpEnabled = !enable;
      });
    } catch (e) {
      if (!mounted) return;
      showToast(
        LegacyTextLocalizer.isEnglish ? 'Failed to toggle MCP' : 'MCP 开关失败',
        type: ToastType.error,
      );
      setState(() {
        _mcpEnabled = !enable;
      });
    } finally {
      if (mounted) {
        setState(() {
          _mcpBusy = false;
        });
      }
    }
  }

  void _showMcpInfo() {
    final info = _mcpInfo;
    if (info == null || info.endpoint.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.settingsMcpLocalService,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(context.l10n.settingsMcpAddress),
              SelectableText(info.endpoint),
              const SizedBox(height: 8),
              Text(context.l10n.settingsMcpToken),
              SelectableText(
                info.token.isEmpty ? context.l10n.settingsNotGenerated : info.token,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: info.endpoint));
                      Navigator.of(context).pop();
                      showToast(
                        LegacyTextLocalizer.isEnglish
                            ? 'Address copied'
                            : '已复制访问地址',
                      );
                    },
                    child: Text(context.l10n.settingsCopyAddress),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: info.token));
                      Navigator.of(context).pop();
                      showToast(
                        LegacyTextLocalizer.isEnglish
                            ? 'Token copied'
                            : '已复制 Token',
                      );
                    },
                    child: Text(context.l10n.settingsCopyToken),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      try {
                        final refreshed = await McpServerService.refreshToken();
                        if (!mounted) return;
                        setState(() {
                          _mcpInfo = refreshed ?? _mcpInfo;
                        });
                        showToast(
                          LegacyTextLocalizer.isEnglish
                              ? 'Token refreshed'
                              : '已刷新 Token',
                        );
                      } catch (_) {
                        showToast(
                          LegacyTextLocalizer.isEnglish
                              ? 'Failed to refresh token'
                              : '刷新 Token 失败',
                          type: ToastType.error,
                        );
                      }
                    },
                    child: Text(context.l10n.settingsRefreshToken),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.settingsMcpSecurityNotice,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final workspaceMemoryConfigured = _embeddingConfig?.configured == true;
    final workspaceMemorySubtitle = !_workspaceMemoryLoaded
        ? context.l10n.settingsWorkspaceMemoryLoading
        : workspaceMemoryConfigured
        ? context.l10n.settingsWorkspaceMemoryEnabled
        : context.l10n.settingsWorkspaceMemoryLexical;
    final sections = _buildSections(workspaceMemorySubtitle);

    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: CommonAppBar(title: context.l10n.settingsTitle, primary: true),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          itemCount: sections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 24),
          itemBuilder: (context, index) {
            return _buildSettingsSection(sections[index]);
          },
        ),
      ),
    );
  }

  List<_SettingSection> _buildSections(String workspaceMemorySubtitle) {
    final dataSyncSubtitle = () {
      final status = _dataSyncStatus;
      if (status == null) {
        return Localizations.localeOf(context).languageCode == 'en'
            ? 'Loading sync status...'
            : '正在加载同步状态...';
      }
      if (!status.enabled) {
        return Localizations.localeOf(context).languageCode == 'en'
            ? 'Disabled'
            : '未启用';
      }
      if (status.state == 'syncing') {
        return status.progress.detail.isNotEmpty
            ? status.progress.detail
            : (Localizations.localeOf(context).languageCode == 'en'
                ? 'Sync in progress'
                : '正在同步');
      }
      if (status.state == 'error') {
        return status.lastError.isNotEmpty
            ? status.lastError
            : (Localizations.localeOf(context).languageCode == 'en'
                ? 'Sync failed'
                : '同步失败');
      }
      if (status.lastSuccessAt > 0) {
        return Localizations.localeOf(context).languageCode == 'en'
            ? 'Last sync succeeded'
            : '最近一次同步成功';
      }
      return Localizations.localeOf(context).languageCode == 'en'
          ? 'Ready to sync'
          : '已就绪';
    }();
    return [
      _SettingSection(
        label: context.l10n.settingsSectionModelMemory,
        items: [
          _SettingItem(
            icon: Icons.smart_toy_outlined,
            iconSvg: 'assets/home/vlm_model_setting_icon.svg',
            title: context.l10n.settingsModelProviderTitle,
            subtitle: context.l10n.settingsModelProviderSubtitle,
            onTap: () {
              GoRouterManager.push('/home/vlm_model_setting');
            },
          ),
          _SettingItem(
            icon: Icons.tune_outlined,
            iconSvg: 'assets/home/scene_model_setting_icon.svg',
            title: context.l10n.settingsSceneModelTitle,
            subtitle: context.l10n.settingsSceneModelSubtitle,
            onTap: () {
              GoRouterManager.push('/home/scene_model_setting');
            },
          ),
          _SettingItem(
            icon: Icons.memory_outlined,
            iconSvg: 'assets/home/local_model_cpu_icon.svg',
            title: context.l10n.settingsLocalModelsTitle,
            subtitle: context.l10n.settingsLocalModelsSubtitle,
            onTap: () {
              GoRouterManager.push('/home/local_models?tab=service');
            },
          ),
          _SettingItem(
            icon: Icons.cloud_sync_outlined,
            iconSvg: 'assets/home/mem0_cloud_setting_icon.svg',
            title: context.l10n.settingsWorkspaceMemoryTitle,
            subtitle: workspaceMemorySubtitle,
            onTap: () async {
              await GoRouterManager.pushForResult(
                '/home/workspace_memory_setting',
              );
              _loadWorkspaceMemoryState();
            },
          ),
        ],
      ),
      _SettingSection(
        label: context.l10n.settingsSectionServiceEnvironment,
        items: [
          _SettingItem(
            icon: Icons.sync_outlined,
            title: Localizations.localeOf(context).languageCode == 'en'
                ? 'Data Sync'
                : '数据同步',
            subtitle: dataSyncSubtitle,
            onTap: () async {
              await GoRouterManager.pushForResult('/home/data_sync_setting');
              _loadDataSyncStatus();
            },
          ),
          _SettingItem(
            icon: Icons.extension_outlined,
            iconSvg: 'assets/home/mcp_tools_setting_icon.svg',
            title: context.l10n.settingsMcpToolsTitle,
            subtitle: context.l10n.settingsMcpToolsSubtitle,
            onTap: () {
              GoRouterManager.push('/home/mcp_tools');
            },
          ),
          _SettingItem(
            icon: Icons.cloud_outlined,
            iconSvg: 'assets/home/local_mcp_service_setting_icon.svg',
            title: context.l10n.settingsLocalServiceTitle,
            subtitle: context.l10n.settingsLocalServiceSubtitle,
            trailing: _buildSwitchTrailing(
              value: _mcpEnabled,
              enabled: _mcpLoaded && !_mcpBusy,
              loading: !_mcpLoaded,
              onToggle: (val) async {
                await _toggleMcpServer(val);
              },
            ),
            onTap: _mcpEnabled && !_mcpBusy ? _showMcpInfo : null,
          ),
          _SettingItem(
            icon: Icons.code,
            iconSvg: 'assets/home/termux.svg',
            iconColor: AppColors.buttonPrimary,
            title: context.l10n.settingsAlpineTitle,
            subtitle: context.l10n.settingsAlpineSubtitle,
            onTap: () {
              GoRouterManager.push('/home/termux_setting');
            },
          ),
          _SettingItem(
            icon: Icons.visibility_off_outlined,
            iconSvg: 'assets/home/hide_recents_setting_icon.svg',
            title: context.l10n.settingsHideRecentsTitle,
            subtitle: context.l10n.settingsHideRecentsSubtitle,
            trailing: _buildSwitchTrailing(
              value: hideFromRecentsEnabled,
              onToggle: _onHideFromRecentsChanged,
            ),
          ),
        ],
      ),
      _SettingSection(
        label: context.l10n.settingsSectionExperienceAppearance,
        items: [
          _SettingItem(
            icon: Icons.alarm_outlined,
            title: context.l10n.settingsAlarmTitle,
            subtitle: context.l10n.settingsAlarmSubtitle,
            onTap: () {
              GoRouterManager.push('/home/alarm_setting');
            },
          ),
          _SettingItem(
            icon: Icons.wallpaper_outlined,
            title: context.l10n.settingsAppearanceTitle,
            subtitle: context.l10n.settingsAppearanceSubtitle,
            onTap: () {
              GoRouterManager.push('/home/background_setting');
            },
          ),
          _SettingItem(
            icon: Icons.vibration,
            iconSvg: 'assets/home/vibration_icon.svg',
            title: context.l10n.settingsVibrationTitle,
            subtitle: context.l10n.settingsVibrationSubtitle,
            trailing: _buildSwitchTrailing(
              value: vibrationEnabled,
              onToggle: (val) async {
                await CacheUtil.cacheBool('app_vibrate', val);
                setState(() {
                  vibrationEnabled = val;
                });
              },
            ),
          ),
          _SettingItem(
            icon: Icons.chat_outlined,
            iconSvg: 'assets/home/auto_back_chat_setting_icon.svg',
            title: context.l10n.settingsAutoBackTitle,
            subtitle: context.l10n.settingsAutoBackSubtitle,
            trailing: _buildSwitchTrailing(
              value: _autoBackToChatAfterTaskEnabled,
              onToggle: _onAutoBackToChatAfterTaskChanged,
            ),
          ),
        ],
      ),
      _SettingSection(
        label: context.l10n.settingsSectionPermissionInfo,
        items: [
          _SettingItem(
            icon: Icons.security,
            iconSvg: 'assets/home/companion_permission_setting_icon.svg',
            title: context.l10n.settingsCompanionPermissionTitle,
            subtitle: context.l10n.settingsCompanionPermissionSubtitle,
            onTap: () async {
              try {
                final granted = await ensureInstalledAppsPermission();
                if (granted == true) {
                  GoRouterManager.push('/home/companion_setting');
                }
              } catch (e) {
                debugPrint('请求读取应用列表权限失败: $e');
                showToast(
                  LegacyTextLocalizer.isEnglish
                      ? 'Failed to request installed apps permission'
                      : '请求应用列表权限失败',
                );
              }
            },
          ),
          _SettingItem(
            icon: Icons.storage_outlined,
            title: Localizations.localeOf(context).languageCode == 'en'
                ? 'Storage Usage'
                : '存储占用',
            subtitle: Localizations.localeOf(context).languageCode == 'en'
                ? 'View storage usage details and clean up by category'
                : '查看空间占用明细，支持分项清理',
            onTap: () {
              GoRouterManager.push('/home/storage_usage');
            },
          ),
          _SettingItem(
            icon: Icons.info_outline,
            iconSvg: 'assets/home/about_icon.svg',
            title: context.l10n.settingsAboutTitle,
            onTap: () {
              GoRouterManager.push('/my/about');
            },
          ),
        ],
      ),
    ];
  }

  Widget _buildSettingsSection(_SettingSection section) {
    final palette = context.omniPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              Text(
                context.trLegacy(section.label),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: palette.textTertiary,
                  fontFamily: 'PingFang SC',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: palette.borderSubtle.withValues(
                    alpha: context.isDarkTheme ? 0.56 : 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        Column(
          children: List.generate(section.items.length, (index) {
            final isLast = index == section.items.length - 1;
            return Column(
              children: [
                _buildSettingTile(section.items[index], isLast: isLast),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: palette.borderSubtle.withValues(
                        alpha: context.isDarkTheme ? 0.5 : 0.78,
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSettingTile(_SettingItem item, {required bool isLast}) {
    final palette = context.omniPalette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: palette.accentPrimary.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 2, isLast ? 14 : 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildLeadingIcon(item),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.trLegacy(item.title),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                        height: 1.5,
                        fontFamily: 'PingFang SC',
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.trLegacy(item.subtitle!),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11,
                          fontFamily: 'PingFang SC',
                          fontWeight: FontWeight.w400,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.trailing != null)
                item.trailing!
              else if (item.onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(_SettingItem item) {
    final palette = context.omniPalette;
    final iconColor = item.iconColor ?? palette.textPrimary;
    return SizedBox(
      width: 18,
      height: 18,
      child: item.iconSvg != null
          ? SvgPicture.asset(
              item.iconSvg!,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            )
          : item.icon != null
          ? Icon(item.icon, size: 18, color: iconColor)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSwitchTrailing({
    required bool value,
    required ValueChanged<bool> onToggle,
    bool enabled = true,
    bool loading = false,
  }) {
    final palette = context.omniPalette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled && !loading ? () => onToggle(!value) : null,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: loading
            ? Container(
                width: 32,
                height: 18.67,
                decoration: BoxDecoration(
                  color: palette.borderStrong,
                  borderRadius: BorderRadius.circular(28.75),
                ),
              )
            : AbsorbPointer(
                child: Opacity(
                  opacity: enabled ? 1 : 0.5,
                  child: FlutterSwitch(
                    width: 32,
                    height: 18.67,
                    toggleSize: 11.3,
                    padding: 3,
                    activeColor: palette.accentPrimary,
                    inactiveColor: palette.borderStrong,
                    borderRadius: 28.75,
                    value: value,
                    onToggle: onToggle,
                  ),
                ),
              ),
      ),
    );
  }
}

class _SettingSection {
  final String label;
  final List<_SettingItem> items;

  const _SettingSection({required this.label, required this.items});
}

class _SettingItem {
  final IconData? icon;
  final String? iconSvg;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingItem({
    this.icon,
    this.iconSvg,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
}
