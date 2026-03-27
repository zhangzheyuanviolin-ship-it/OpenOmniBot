import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:url_launcher/url_launcher_string.dart';

class TermuxSettingPage extends StatefulWidget {
  const TermuxSettingPage({super.key});

  @override
  State<TermuxSettingPage> createState() => _TermuxSettingPageState();
}

class _TermuxSettingPageState extends State<TermuxSettingPage>
    with WidgetsBindingObserver {
  bool _isOpeningSetup = false;

  bool _isLoadingGatewayStatus = true;
  bool _isUpdatingGatewayAutoStart = false;
  bool _isStartingGateway = false;
  bool _isStoppingGateway = false;
  bool _isPollingGatewayStatus = false;

  Timer? _gatewayStatusPoller;
  Timer? _gatewayUptimeTicker;
  OpenClawGatewayStatus? _gatewayStatus;
  DateTime? _gatewayStatusSnapshotAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startGatewayStatusPolling();
    _startGatewayUptimeTicker();
    _refreshGatewayStatusOnly(showLoading: true);
  }

  @override
  void dispose() {
    _gatewayStatusPoller?.cancel();
    _gatewayUptimeTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startGatewayStatusPolling();
      _startGatewayUptimeTicker();
      _refreshGatewayStatusOnly(showLoading: true);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _gatewayStatusPoller?.cancel();
      _gatewayStatusPoller = null;
      _gatewayUptimeTicker?.cancel();
      _gatewayUptimeTicker = null;
    }
  }

  void _startGatewayStatusPolling() {
    _gatewayStatusPoller?.cancel();
    _gatewayStatusPoller = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refreshGatewayStatusOnly());
    });
  }

  void _startGatewayUptimeTicker() {
    _gatewayUptimeTicker?.cancel();
    _gatewayUptimeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final status = _gatewayStatus;
      if (status == null || !(status.running && status.healthy)) {
        return;
      }
      setState(() {});
    });
  }

  Future<void> _refreshGatewayStatusOnly({bool showLoading = false}) async {
    if (!mounted || _isPollingGatewayStatus) {
      return;
    }
    if (showLoading) {
      setState(() {
        _isLoadingGatewayStatus = true;
      });
    }
    _isPollingGatewayStatus = true;
    try {
      final gatewayStatus = await getOpenClawGatewayStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _gatewayStatus = gatewayStatus;
        _gatewayStatusSnapshotAt = DateTime.now();
        _isLoadingGatewayStatus = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (showLoading) {
        setState(() {
          _isLoadingGatewayStatus = false;
        });
      }
    } finally {
      _isPollingGatewayStatus = false;
    }
  }

  Future<void> _handleGatewayAutoStartChanged(bool enabled) async {
    if (_isUpdatingGatewayAutoStart) {
      return;
    }
    setState(() {
      _isUpdatingGatewayAutoStart = true;
    });
    try {
      await setOpenClawGatewayAutoStart(enabled);
      await _refreshGatewayStatusOnly(showLoading: true);
    } on PlatformException catch (e) {
      showToast(e.message ?? '更新自动守护开关失败', type: ToastType.error);
    } catch (_) {
      showToast('更新自动守护开关失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingGatewayAutoStart = false;
        });
      }
    }
  }

  Future<void> _handleStartGateway({bool forceRestart = false}) async {
    if (_isStartingGateway) {
      return;
    }
    setState(() {
      _isStartingGateway = true;
    });
    try {
      await startOpenClawGateway(forceRestart: forceRestart);
      showToast(
        forceRestart ? 'Gateway 正在重启' : 'Gateway 正在启动',
        type: ToastType.success,
      );
      await _refreshGatewayStatusOnly(showLoading: true);
    } on PlatformException catch (e) {
      showToast(e.message ?? '启动 Gateway 失败', type: ToastType.error);
    } catch (_) {
      showToast('启动 Gateway 失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isStartingGateway = false;
        });
      }
    }
  }

  Future<void> _handleStopGateway() async {
    if (_isStoppingGateway) {
      return;
    }
    setState(() {
      _isStoppingGateway = true;
    });
    try {
      await stopOpenClawGateway();
      showToast('Gateway 已停止', type: ToastType.success);
      await _refreshGatewayStatusOnly(showLoading: true);
    } on PlatformException catch (e) {
      showToast(e.message ?? '停止 Gateway 失败', type: ToastType.error);
    } catch (_) {
      showToast('停止 Gateway 失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isStoppingGateway = false;
        });
      }
    }
  }

  Future<void> _handleOpenSetupPage() async {
    if (_isOpeningSetup) {
      return;
    }
    setState(() {
      _isOpeningSetup = true;
    });
    try {
      await openNativeTerminal(openSetup: true);
    } on PlatformException catch (e) {
      showToast(e.message ?? '打开终端环境配置失败', type: ToastType.error);
    } catch (_) {
      showToast('打开终端环境配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningSetup = false;
        });
      }
    }
  }

  Widget _buildEnvironmentSetupCard() {
    return _buildSectionCard(
      title: '环境配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '不再集中管理开发环境配置，请自行安装或者叫小万安装',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isOpeningSetup ? null : _handleOpenSetupPage,
              icon: const Icon(Icons.terminal_rounded),
              label: _isOpeningSetup
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('打开终端'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: const CommonAppBar(title: 'Alpine 与 OpenClaw', primary: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _refreshGatewayStatusOnly(showLoading: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEnvironmentSetupCard(),
                const SizedBox(height: 12),
                _buildGatewayCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGatewayCard() {
    final gatewayStatus = _gatewayStatus;
    final lastError = gatewayStatus?.lastError?.trim() ?? '';
    final statusText = _buildGatewayStatusText(gatewayStatus);
    final subtitle = _isLoadingGatewayStatus
        ? '正在检查 OpenClaw Gateway 状态'
        : statusText;
    final isRunning = gatewayStatus?.running == true;
    final canOperate =
        gatewayStatus != null &&
        !_isLoadingGatewayStatus &&
        !_isStartingGateway &&
        !_isStoppingGateway;

    return _buildSectionCard(
      title: 'OpenClaw Gateway',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x14000000)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGatewayIconAction(
                          icon: Icons.refresh_rounded,
                          tooltip: '重启 Gateway',
                          onTap: canOperate
                              ? () => _handleStartGateway(forceRestart: true)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        _buildGatewayIconAction(
                          icon: isRunning
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_fill_rounded,
                          tooltip: isRunning ? '停止 Gateway' : '启动 Gateway',
                          onTap: canOperate
                              ? () {
                                  if (isRunning) {
                                    _handleStopGateway();
                                  } else {
                                    _handleStartGateway(forceRestart: false);
                                  }
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildGatewayAddressLink(gatewayStatus),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '应用内 Auto-start Gateway',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            gatewayStatus?.autoStartEnabled == true
                                ? 'App 冷启动时会自动恢复 GatewayService'
                                : '默认关闭，避免未确认的后台保活',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: gatewayStatus?.autoStartEnabled == true,
                      onChanged:
                          (_isLoadingGatewayStatus ||
                              _isUpdatingGatewayAutoStart ||
                              gatewayStatus == null)
                          ? null
                          : _handleGatewayAutoStartChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (lastError.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x14EF6B5F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                lastError,
                style: const TextStyle(
                  color: Color(0xFFB34A40),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGatewayIconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        iconSize: 20,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          maximumSize: const Size(34, 34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          foregroundColor: enabled
              ? AppColors.buttonPrimary
              : const Color(0xFF9CA3AF),
          backgroundColor: enabled
              ? const Color(0x1A4A7CFF)
              : const Color(0x10000000),
        ),
      ),
    );
  }

  Widget _buildGatewayAddressLink(OpenClawGatewayStatus? status) {
    final url = (status?.dashboardUrl ?? '').trim();
    final normalizedUrl = url.isNotEmpty ? url : 'http://127.0.0.1:18789';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '地址：',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _openExternalUrl(normalizedUrl),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                normalizedUrl,
                style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF2563EB),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final launched = await launchUrlString(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      showToast('打开 Gateway 地址失败', type: ToastType.error);
    }
  }

  String _buildGatewayStatusText(OpenClawGatewayStatus? status) {
    if (status == null) {
      return '尚未获取到 Gateway 状态';
    }
    if (!status.installed) {
      return 'OpenClaw CLI 尚未安装，请先在聊天页完成一键部署';
    }
    if (!status.configured) {
      return 'OpenClaw 配置尚未写入，请先完成部署';
    }
    if (status.legacyConfigNeedsRedeploy) {
      return '检测到旧版部署痕迹，需要重新保存或重新部署一次';
    }
    if (status.restarting) {
      return 'Gateway 正在退避重启中';
    }
    if (status.running && status.healthy) {
      final liveUptimeSeconds = _effectiveGatewayUptimeSeconds(status);
      final uptimeText = liveUptimeSeconds == null
          ? ''
          : '，已运行 ${_formatUptime(liveUptimeSeconds)}';
      return 'Gateway 正在运行且健康$uptimeText';
    }
    if (status.running) {
      return 'Gateway 已启动，正在等待健康检查';
    }
    return 'Gateway 当前未运行';
  }

  int? _effectiveGatewayUptimeSeconds(OpenClawGatewayStatus status) {
    final base = status.uptimeSeconds;
    if (base == null) {
      return null;
    }
    if (!status.running) {
      return base;
    }
    final snapshotAt = _gatewayStatusSnapshotAt;
    if (snapshotAt == null) {
      return base;
    }
    final elapsed = DateTime.now().difference(snapshotAt).inSeconds;
    if (elapsed <= 0) {
      return base;
    }
    return base + elapsed;
  }

  String _formatUptime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [AppColors.boxShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
