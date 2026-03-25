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
  WorkspaceMemoryRollupStatus? _rollupStatus;

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
        _rollupStatus = results[1] as WorkspaceMemoryRollupStatus;
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
                '本机 MCP 服务',
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
    final workspaceMemoryConfigured = _embeddingConfig?.configured == true;
    final workspaceMemorySubtitle = !_workspaceMemoryLoaded
        ? '加载中...'
        : workspaceMemoryConfigured
        ? '已启用 workspace 记忆（嵌入检索可用）'
        : '使用 workspace 记忆（当前为词法检索）';
    final sections = _buildSections(workspaceMemorySubtitle);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: '设置', primary: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int index = 0; index < sections.length; index++) ...[
                _buildSettingsSection(sections[index]),
                if (index != sections.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<_SettingSection> _buildSections(String workspaceMemorySubtitle) {
    return [
      _SettingSection(
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
            title: '本机 MCP 服务',
            subtitle: '在局域网内访问当前手机提供的 MCP 服务',
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
            title: 'Ubuntu 与 OpenClaw',
            subtitle: '管理应用内 Ubuntu、OpenClaw Gateway 与 workspace 映射',
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Column(
        children: List.generate(section.items.length, (index) {
          final isLast = index == section.items.length - 1;
          return Column(
            children: [
              _buildSettingTile(
                section.items[index],
                isFirst: index == 0,
                isLast: isLast,
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.only(left: 40, right: 16),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFECEFF4),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSettingTile(
    _SettingItem item, {
    required bool isFirst,
    required bool isLast,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(18) : Radius.zero,
          bottom: isLast ? const Radius.circular(18) : Radius.zero,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            isFirst ? 16 : 12,
            16,
            isLast ? 16 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildLeadingIcon(item),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                        height: 1.57,
                        fontFamily: 'PingFang SC',
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      Text(
                        item.subtitle!,
                        style: const TextStyle(
                          color: AppColors.text70,
                          fontSize: 10,
                          fontFamily: 'PingFang SC',
                          fontWeight: FontWeight.w400,
                          height: 1.60,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.trailing != null)
                item.trailing!
              else if (item.onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.text20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(_SettingItem item) {
    return SizedBox(
      width: 16,
      height: 16,
      child: item.iconSvg != null
          ? SvgPicture.asset(
              item.iconSvg!,
              width: 16,
              height: 16,
              colorFilter: item.iconColor != null
                  ? ColorFilter.mode(item.iconColor!, BlendMode.srcIn)
                  : null,
            )
          : item.icon != null
          ? Icon(item.icon, size: 16, color: item.iconColor)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSwitchTrailing({
    required bool value,
    required ValueChanged<bool> onToggle,
    bool enabled = true,
    bool loading = false,
  }) {
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
                  color: AppColors.fillStandardSecondary,
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
                    activeColor: const Color(0xFF2C7FEB),
                    inactiveColor: AppColors.fillStandardSecondary,
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
  final List<_SettingItem> items;

  const _SettingSection({required this.items});
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
