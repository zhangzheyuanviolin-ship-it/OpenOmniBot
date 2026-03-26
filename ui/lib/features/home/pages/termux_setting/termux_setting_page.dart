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
  bool _isLoadingStatus = true;
  bool _isDeviceSupported = false;
  bool _isRuntimeReady = false;
  bool _isBasePackagesReady = false;
  List<String> _missingCommands = const <String>[];
  String _runtimeStatusMessage = '';
  bool _nodeReady = false;
  String? _nodeVersion;
  int _nodeMinMajor = 22;
  bool _pnpmReady = false;
  String? _pnpmVersion;

  bool _isPreparingWrapper = false;
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
    _refreshStatus();
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
      _refreshStatus();
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

  Future<void> _refreshStatus() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingStatus = true;
      _isLoadingGatewayStatus = true;
    });

    try {
      final results = await Future.wait<dynamic>([
        getEmbeddedTerminalRuntimeStatus(),
        getOpenClawGatewayStatus(),
      ]);
      final status = results[0] as EmbeddedTerminalRuntimeStatus;
      final gatewayStatus = results[1] as OpenClawGatewayStatus;
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeviceSupported = status.supported;
        _isRuntimeReady = status.runtimeReady;
        _isBasePackagesReady = status.basePackagesReady;
        _missingCommands = status.missingCommands;
        _runtimeStatusMessage = status.message;
        _nodeReady = status.nodeReady;
        _nodeVersion = status.nodeVersion;
        _nodeMinMajor = status.nodeMinMajor;
        _pnpmReady = status.pnpmReady;
        _pnpmVersion = status.pnpmVersion;
        _gatewayStatus = gatewayStatus;
        _gatewayStatusSnapshotAt = DateTime.now();
        _isLoadingStatus = false;
        _isLoadingGatewayStatus = false;
      });
    } on PlatformException {
      final supported = await isTermuxInstalled();
      OpenClawGatewayStatus? gatewayStatus;
      try {
        gatewayStatus = await getOpenClawGatewayStatus();
      } catch (_) {
        gatewayStatus = null;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeviceSupported = supported;
        _isRuntimeReady = false;
        _isBasePackagesReady = false;
        _missingCommands = const <String>[];
        _runtimeStatusMessage = '状态探测失败，请尝试初始化。';
        _nodeReady = false;
        _nodeVersion = null;
        _nodeMinMajor = 22;
        _pnpmReady = false;
        _pnpmVersion = null;
        _isLoadingStatus = false;
        _gatewayStatus = gatewayStatus;
        _gatewayStatusSnapshotAt = gatewayStatus == null
            ? null
            : DateTime.now();
        _isLoadingGatewayStatus = false;
      });
    } catch (_) {
      final supported = await isTermuxInstalled();
      OpenClawGatewayStatus? gatewayStatus;
      try {
        gatewayStatus = await getOpenClawGatewayStatus();
      } catch (_) {
        gatewayStatus = null;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeviceSupported = supported;
        _isRuntimeReady = false;
        _isBasePackagesReady = false;
        _missingCommands = const <String>[];
        _runtimeStatusMessage = '状态探测失败，请尝试初始化。';
        _nodeReady = false;
        _nodeVersion = null;
        _nodeMinMajor = 22;
        _pnpmReady = false;
        _pnpmVersion = null;
        _isLoadingStatus = false;
        _gatewayStatus = gatewayStatus;
        _gatewayStatusSnapshotAt = gatewayStatus == null
            ? null
            : DateTime.now();
        _isLoadingGatewayStatus = false;
      });
    }
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
      await _refreshStatus();
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
      await _refreshStatus();
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
      await _refreshStatus();
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

  Future<void> _handlePrepareWrapper() async {
    if (_isPreparingWrapper) {
      return;
    }
    if (!_isDeviceSupported) {
      showToast('当前设备暂不支持内嵌终端，仅支持 arm64-v8a', type: ToastType.warning);
      return;
    }

    setState(() {
      _isPreparingWrapper = true;
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
          _isPreparingWrapper = false;
        });
      }
    }
  }

  String _buildRuntimeSubtitle() {
    if (_isLoadingStatus) {
      return '正在检查 Ubuntu 运行时与环境工具状态';
    }
    if (!_isDeviceSupported) {
      return '当前设备 ABI 不受支持，仅支持 arm64-v8a';
    }
    if (!_isRuntimeReady) {
      return _runtimeStatusMessage.isNotEmpty
          ? _runtimeStatusMessage
          : '内嵌 Ubuntu 运行时未就绪，请打开终端环境配置完成初始化。';
    }
    if (!_isBasePackagesReady) {
      if (_missingCommands.isNotEmpty) {
        return 'Ubuntu 已就绪，可前往终端“环境配置”按需安装 Node.js、Python、SSH、Java 等工具。当前探测缺少：${_missingCommands.join(", ")}';
      }
      return _runtimeStatusMessage.isNotEmpty
          ? _runtimeStatusMessage
          : 'Ubuntu 已就绪，可前往终端“环境配置”按需安装 Node.js、Python、SSH、Java 等工具。';
    }
    return 'Ubuntu 运行时已就绪，可继续在终端“环境配置”中管理 Node.js、Python、SSH、Java 等工具。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: const CommonAppBar(title: 'Ubuntu 与 OpenClaw', primary: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshStatus,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusAndActionsCard(),
                const SizedBox(height: 12),
                _buildGatewayCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusAndActionsCard() {
    final runtimeActionText = _isLoadingStatus
        ? '检测中'
        : (!_isDeviceSupported
              ? '不支持'
              : (_isPreparingWrapper ? '打开中...' : '去配置'));
    final runtimeActionColor = _isLoadingStatus
        ? AppColors.text50
        : (!_isDeviceSupported
              ? const Color(0xFFB34A40)
              : (_isPreparingWrapper
                    ? const Color(0xFFD08A00)
                    : const Color(0xFF1E9E63)));
    final runtimeActionEnabled =
        !_isLoadingStatus && _isDeviceSupported && !_isPreparingWrapper;

    return _buildSectionCard(
      title: '当前状态与操作',
      child: Column(
        children: [
          _StatusActionRow(
            title: 'Ubuntu 运行时与环境配置',
            subtitle: _buildRuntimeSubtitle(),
            actionText: runtimeActionText,
            actionColor: runtimeActionColor,
            onTap: runtimeActionEnabled ? _handlePrepareWrapper : null,
          ),
          const SizedBox(height: 14),
          _buildPrepareActionButton(),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x14000000)),
            ),
            child: const Text(
              '点击后会直接进入终端内的“环境配置”页面，按分类安装 Node.js、Python、SSH 工具、Java 环境等组件。',
              style: TextStyle(
                color: AppColors.text70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildNodeAndPnpmStatusPanel(),
        ],
      ),
    );
  }

  Widget _buildNodeAndPnpmStatusPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Node.js / PNPM 状态',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _buildRuntimeToolStatusTile(
            name: 'Node.js',
            ready: _nodeReady,
            detail: _nodeVersion?.isNotEmpty == true
                ? 'v$_nodeVersion'
                : '未检测到',
            notReadyReason: _nodeVersion?.isNotEmpty == true
                ? '版本过低，最低要求 v$_nodeMinMajor'
                : '未安装或不可用',
          ),
          const SizedBox(height: 8),
          _buildRuntimeToolStatusTile(
            name: 'PNPM',
            ready: _pnpmReady,
            detail: _pnpmVersion?.isNotEmpty == true ? _pnpmVersion! : '未检测到',
            notReadyReason: '未安装或不可用',
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeToolStatusTile({
    required String name,
    required bool ready,
    required String detail,
    required String notReadyReason,
  }) {
    final badgeColor = ready
        ? const Color(0x141E9E63)
        : const Color(0x14EF6B5F);
    final badgeTextColor = ready
        ? const Color(0xFF1E9E63)
        : const Color(0xFFB34A40);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$name：$detail',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                ready ? 'ready' : 'not ready',
                style: TextStyle(
                  color: badgeTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (!ready)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              notReadyReason,
              style: const TextStyle(
                color: Color(0xFFB34A40),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPrepareActionButton() {
    final bool disabled =
        _isLoadingStatus || _isPreparingWrapper || !_isDeviceSupported;
    final buttonText = _isPreparingWrapper
        ? '正在打开环境配置...'
        : (!_isDeviceSupported ? '当前设备不支持（仅 arm64-v8a）' : '打开终端环境配置');
    final gradientColors = _isPreparingWrapper
        ? const [Color(0xFF1930D9), Color(0xFF2DA5F0)]
        : (!_isDeviceSupported
              ? const [Color(0xFFBFC7D5), Color(0xFFA6AFBE)]
              : const [Color(0xFF1E9E63), Color(0xFF45C07B)]);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: const Alignment(0.14, -1.09),
            end: const Alignment(1.10, 1.26),
            colors: gradientColors,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : _handlePrepareWrapper,
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: Center(
              child: Text(
                buttonText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

class _StatusActionRow extends StatelessWidget {
  static const double _subtitleSlotHeight = 36;
  static const double _actionButtonMinWidth = 72;

  const _StatusActionRow({
    required this.title,
    required this.subtitle,
    required this.actionText,
    required this.actionColor,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionText;
  final Color actionColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: _subtitleSlotHeight,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text.withValues(alpha: 0.66),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 36,
              constraints: const BoxConstraints(
                minWidth: _actionButtonMinWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: enabled ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                actionText,
                style: TextStyle(
                  color: enabled
                      ? actionColor
                      : actionColor.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
