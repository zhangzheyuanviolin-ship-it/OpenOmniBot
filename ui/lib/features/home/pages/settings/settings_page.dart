import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/services/assists_core_service.dart';
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
    _configChangedSubscription = AssistsMessageService
        .agentAiConfigChangedStream
        .listen((event) {
          if (event.source != 'file' || !mounted) {
            return;
          }
          _loadWorkspaceMemoryState();
        });
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
      showToast('设置后台隐藏失败', type: ToastType.error);
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
      showToast(value ? '任务完成后将自动返回聊天' : '任务完成后将停留在当前页面');
    } catch (e) {
      if (!mounted) return;
      showToast('设置失败', type: ToastType.error);
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
          showToast('MCP 已开启：$endpoint', type: ToastType.success);
        }
      } else {
        showToast('MCP 已关闭');
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      showToast(e.message ?? 'MCP 开关失败', type: ToastType.error);
      setState(() {
        _mcpEnabled = !enable;
      });
    } catch (e) {
      if (!mounted) return;
      showToast('MCP 开关失败', type: ToastType.error);
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
              const Text(
                '本机服务',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text('地址'),
              SelectableText(info.endpoint),
              const SizedBox(height: 8),
              const Text('Token'),
              SelectableText(info.token.isEmpty ? '未生成' : info.token),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: info.endpoint));
                      Navigator.of(context).pop();
                      showToast('已复制访问地址');
                    },
                    child: const Text('复制地址'),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: info.token));
                      Navigator.of(context).pop();
                      showToast('已复制 Token');
                    },
                    child: const Text('复制 Token'),
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
                        showToast('已刷新 Token');
                      } catch (_) {
                        showToast('刷新 Token 失败', type: ToastType.error);
                      }
                    },
                    child: const Text('刷新 Token'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '请在同一局域网内使用 Authorization: Bearer <Token> 调用 /mcp/v1/task/vlm，避免将地址或 Token 暴露到公网。',
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
        ? '加载中...'
        : workspaceMemoryConfigured
        ? '已启用 workspace 记忆（嵌入检索可用）'
        : '使用 workspace 记忆（当前为词法检索）';
    final sections = _buildSections(workspaceMemorySubtitle);

    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: const CommonAppBar(title: '设置', primary: true),
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
    return [
      _SettingSection(
        label: '模型与记忆',
        items: [
          _SettingItem(
            icon: Icons.smart_toy_outlined,
            iconSvg: 'assets/home/vlm_model_setting_icon.svg',
            title: '模型提供商',
            subtitle: '配置模型地址、密钥与模型列表',
            onTap: () {
              GoRouterManager.push('/home/vlm_model_setting');
            },
          ),
          _SettingItem(
            icon: Icons.tune_outlined,
            iconSvg: 'assets/home/scene_model_setting_icon.svg',
            title: '场景模型配置',
            subtitle: '按场景绑定模型，未绑定场景使用默认模型',
            onTap: () {
              GoRouterManager.push('/home/scene_model_setting');
            },
          ),
          _SettingItem(
            icon: Icons.memory_outlined,
            iconSvg: 'assets/home/local_model_cpu_icon.svg',
            title: '本地模型服务',
            subtitle: '管理本地模型、推理、API 服务与语音模型',
            onTap: () {
              GoRouterManager.push('/home/local_models?tab=service');
            },
          ),
          _SettingItem(
            icon: Icons.cloud_sync_outlined,
            iconSvg: 'assets/home/mem0_cloud_setting_icon.svg',
            title: 'Workspace 记忆配置',
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
        label: '服务与环境',
        items: [
          _SettingItem(
            icon: Icons.extension_outlined,
            iconSvg: 'assets/home/mcp_tools_setting_icon.svg',
            title: 'MCP 工具',
            subtitle: '添加、启停和管理远端 MCP 服务',
            onTap: () {
              GoRouterManager.push('/home/mcp_tools');
            },
          ),
          _SettingItem(
            icon: Icons.cloud_outlined,
            iconSvg: 'assets/home/local_mcp_service_setting_icon.svg',
            title: '本机服务',
            subtitle: '在局域网内访问小万 MCP 和 webchat服务',
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
            title: 'Alpine 环境',
            subtitle: '查看与打开应用内 Alpine 终端环境',
            onTap: () {
              GoRouterManager.push('/home/termux_setting');
            },
          ),
          _SettingItem(
            icon: Icons.visibility_off_outlined,
            iconSvg: 'assets/home/hide_recents_setting_icon.svg',
            title: '后台隐藏',
            subtitle: '开启后应用将从最近任务列表中隐藏',
            trailing: _buildSwitchTrailing(
              value: hideFromRecentsEnabled,
              onToggle: _onHideFromRecentsChanged,
            ),
          ),
        ],
      ),
      _SettingSection(
        label: '体验与外观',
        items: [
          _SettingItem(
            icon: Icons.alarm_outlined,
            title: '闹钟设置',
            subtitle: '配置默认铃声、本地 mp3 或 mp3 直链',
            onTap: () {
              GoRouterManager.push('/home/alarm_setting');
            },
          ),
          _SettingItem(
            icon: Icons.wallpaper_outlined,
            title: '外观设置',
            subtitle: '配置主题模式、共享背景图、聊天字号和文本颜色',
            onTap: () {
              GoRouterManager.push('/home/background_setting');
            },
          ),
          _SettingItem(
            icon: Icons.vibration,
            iconSvg: 'assets/home/vibration_icon.svg',
            title: '振动反馈',
            subtitle: '执行任务时，通过振动进行操作提醒',
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
            title: '任务完成后自动回聊天',
            subtitle: '关闭后，任务结束将停留在当前完成页面',
            trailing: _buildSwitchTrailing(
              value: _autoBackToChatAfterTaskEnabled,
              onToggle: _onAutoBackToChatAfterTaskChanged,
            ),
          ),
        ],
      ),
      _SettingSection(
        label: '权限与信息',
        items: [
          _SettingItem(
            icon: Icons.security,
            iconSvg: 'assets/home/companion_permission_setting_icon.svg',
            title: '陪伴权限授权',
            subtitle: '仅访问您授权的 App，隐私安全更有保障',
            onTap: () async {
              try {
                final granted = await ensureInstalledAppsPermission();
                if (granted == true) {
                  GoRouterManager.push('/home/companion_setting');
                }
              } catch (e) {
                debugPrint('请求读取应用列表权限失败: $e');
                showToast('请求应用列表权限失败');
              }
            },
          ),
          _SettingItem(
            icon: Icons.info_outline,
            iconSvg: 'assets/home/about_icon.svg',
            title: '关于小万',
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
                section.label,
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
                      item.title,
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
                        item.subtitle!,
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
