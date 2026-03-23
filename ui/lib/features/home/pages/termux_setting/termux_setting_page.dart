import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class TermuxSettingPage extends StatefulWidget {
  const TermuxSettingPage({super.key});

  @override
  State<TermuxSettingPage> createState() => _TermuxSettingPageState();
}

class _TermuxSettingPageState extends State<TermuxSettingPage>
    with WidgetsBindingObserver {
  static const int _maxPrepareLogLines = 160;

  bool _isLoadingStatus = true;
  bool _isDeviceSupported = false;
  bool _isRuntimeReady = false;
  bool _isBasePackagesReady = false;
  bool _isWorkspaceStorageGranted = false;
  List<String> _missingCommands = const <String>[];
  String _runtimeStatusMessage = '';

  bool _isPreparingWrapper = false;
  bool _isOpeningWorkspaceStorageSettings = false;
  bool _isLoadingGatewayStatus = true;
  bool _isUpdatingGatewayAutoStart = false;
  bool _isStartingGateway = false;
  bool _isStoppingGateway = false;
  bool _isOpeningNativeTerminal = false;

  String? _wrapperMessage;
  bool? _wrapperReady;
  String? _prepareStage;
  double _prepareProgress = 0.0;
  final List<String> _prepareLogLines = <String>[];
  late final ScrollController _prepareLogScrollController;
  Timer? _prepareSnapshotPoller;
  OpenClawGatewayStatus? _gatewayStatus;

  bool get _isFullyReady {
    return _isDeviceSupported && _isRuntimeReady && _isBasePackagesReady;
  }

  bool get _shouldShowPrepareConsole {
    return _isPreparingWrapper ||
        (_wrapperReady == false && _prepareLogLines.isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    _prepareLogScrollController = ScrollController();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    _prepareSnapshotPoller?.cancel();
    _prepareLogScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
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
        _isWorkspaceStorageGranted = status.workspaceAccessGranted;
        _missingCommands = status.missingCommands;
        _runtimeStatusMessage = status.message;
        _wrapperReady = status.allReady;
        _gatewayStatus = gatewayStatus;
        _isLoadingStatus = false;
        _isLoadingGatewayStatus = false;
      });
    } on PlatformException {
      final supported = await isTermuxInstalled();
      final workspaceStorageGranted = await isWorkspaceStorageAccessGranted();
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
        _isWorkspaceStorageGranted = workspaceStorageGranted;
        _missingCommands = const <String>[];
        _runtimeStatusMessage = '状态探测失败，请尝试初始化。';
        _wrapperReady = false;
        _isLoadingStatus = false;
        _gatewayStatus = gatewayStatus;
        _isLoadingGatewayStatus = false;
      });
    } catch (_) {
      final supported = await isTermuxInstalled();
      final workspaceStorageGranted = await isWorkspaceStorageAccessGranted();
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
        _isWorkspaceStorageGranted = workspaceStorageGranted;
        _missingCommands = const <String>[];
        _runtimeStatusMessage = '状态探测失败，请尝试初始化。';
        _wrapperReady = false;
        _isLoadingStatus = false;
        _gatewayStatus = gatewayStatus;
        _isLoadingGatewayStatus = false;
      });
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

  Future<void> _handleOpenNativeTerminal() async {
    if (_isOpeningNativeTerminal) {
      return;
    }
    setState(() {
      _isOpeningNativeTerminal = true;
    });
    try {
      await openNativeTerminal();
    } on PlatformException catch (e) {
      showToast(e.message ?? '打开原生终端失败', type: ToastType.error);
    } catch (_) {
      showToast('打开原生终端失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningNativeTerminal = false;
        });
      }
    }
  }

  Future<void> _handleOpenWorkspaceStorageSettings() async {
    if (_isOpeningWorkspaceStorageSettings) {
      return;
    }
    setState(() {
      _isOpeningWorkspaceStorageSettings = true;
    });
    try {
      await openWorkspaceStorageSettings();
    } on PlatformException catch (e) {
      showToast(e.message ?? '打开公共 workspace 权限页失败', type: ToastType.error);
    } catch (_) {
      showToast('打开公共 workspace 权限页失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningWorkspaceStorageSettings = false;
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
      _wrapperMessage = null;
      _wrapperReady = null;
      _prepareStage = '准备开始';
      _prepareProgress = 0.02;
      _prepareLogLines
        ..clear()
        ..add('[系统] 正在启动内嵌 Ubuntu 环境初始化...');
    });
    _startPrepareSnapshotPolling();
    _schedulePrepareLogAutoScroll();
    try {
      final result = await prepareTermuxLiveWrapper();
      final success = result['success'] == true;
      final message = (result['message'] as String?)?.trim();
      await _pollPrepareSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _wrapperReady = success;
        _wrapperMessage = message;
      });
      showToast(
        message?.isNotEmpty == true ? message! : '内嵌终端环境已完成检查',
        type: success ? ToastType.success : ToastType.warning,
      );
    } on PlatformException catch (e) {
      await _pollPrepareSnapshot();
      if (mounted) {
        setState(() {
          _prepareStage = '初始化失败';
          _prepareLogLines.add('[错误] ${e.message ?? '检查内嵌终端环境失败'}');
        });
        _schedulePrepareLogAutoScroll();
      }
      showToast(e.message ?? '检查内嵌终端环境失败', type: ToastType.error);
    } catch (_) {
      await _pollPrepareSnapshot();
      if (mounted) {
        setState(() {
          _prepareStage = '初始化失败';
          _prepareLogLines.add('[错误] 检查内嵌终端环境失败');
        });
        _schedulePrepareLogAutoScroll();
      }
      showToast('检查内嵌终端环境失败', type: ToastType.error);
    } finally {
      await _pollPrepareSnapshot();
      _stopPrepareSnapshotPolling();
      if (mounted) {
        setState(() {
          _isPreparingWrapper = false;
        });
        await _refreshStatus();
      }
    }
  }

  void _startPrepareSnapshotPolling() {
    _stopPrepareSnapshotPolling();
    _pollPrepareSnapshot();
    _prepareSnapshotPoller = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) {
      _pollPrepareSnapshot();
    });
  }

  void _stopPrepareSnapshotPolling() {
    _prepareSnapshotPoller?.cancel();
    _prepareSnapshotPoller = null;
  }

  Future<void> _pollPrepareSnapshot() async {
    try {
      final snapshot = await getEmbeddedTerminalInitSnapshot();
      if (!mounted) {
        return;
      }

      final nextLogLines = snapshot.logLines.length > _maxPrepareLogLines
          ? snapshot.logLines.sublist(
              snapshot.logLines.length - _maxPrepareLogLines,
            )
          : snapshot.logLines;
      final shouldScroll =
          nextLogLines.isNotEmpty &&
          nextLogLines.join('\n') != _prepareLogLines.join('\n');

      setState(() {
        if (snapshot.stage.isNotEmpty) {
          _prepareStage = snapshot.stage;
        }
        _prepareProgress = snapshot.progress;
        if (nextLogLines.isNotEmpty) {
          _prepareLogLines
            ..clear()
            ..addAll(nextLogLines);
        }
        if (snapshot.success != null) {
          _wrapperReady = snapshot.success;
        }
      });

      if (shouldScroll) {
        _schedulePrepareLogAutoScroll();
      }

      if (snapshot.completed) {
        _stopPrepareSnapshotPolling();
      }
    } catch (_) {
      return;
    }
  }

  void _schedulePrepareLogAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_prepareLogScrollController.hasClients) {
        return;
      }
      _prepareLogScrollController.jumpTo(
        _prepareLogScrollController.position.maxScrollExtent,
      );
    });
  }

  String _buildRuntimeSubtitle() {
    if (_isLoadingStatus) {
      return '正在进行运行时功能检查';
    }
    if (!_isDeviceSupported) {
      return '当前设备 ABI 不受支持，仅支持 arm64-v8a';
    }
    if (!_isRuntimeReady) {
      return _runtimeStatusMessage.isNotEmpty
          ? _runtimeStatusMessage
          : '内嵌 Ubuntu 运行时未就绪，请先初始化。';
    }
    if (!_isBasePackagesReady) {
      if (_missingCommands.isNotEmpty) {
        return '缺失基础 CLI：${_missingCommands.join(", ")}';
      }
      return _runtimeStatusMessage.isNotEmpty
          ? _runtimeStatusMessage
          : '基础 Agent CLI 包未就绪，请执行初始化。';
    }
    return 'Ubuntu 运行时与基础 CLI 包已就绪。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: const CommonAppBar(title: '内嵌终端设置', primary: true),
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
              : (_isPreparingWrapper
                    ? '初始化中...'
                    : (_isFullyReady ? '已就绪' : '初始化')));
    final runtimeActionColor = _isLoadingStatus
        ? AppColors.text50
        : (!_isDeviceSupported
              ? const Color(0xFFB34A40)
              : (_isPreparingWrapper
                    ? const Color(0xFFD08A00)
                    : (_isFullyReady
                          ? const Color(0xFF1E9E63)
                          : const Color(0xFFE58A00))));
    final runtimeActionEnabled =
        !_isLoadingStatus &&
        _isDeviceSupported &&
        !_isPreparingWrapper &&
        !_isFullyReady;

    final workspaceActionText = _isLoadingStatus
        ? '检测中'
        : (_isWorkspaceStorageGranted
              ? '已就绪'
              : (_isOpeningWorkspaceStorageSettings ? '打开中...' : '去授权'));
    final workspaceActionColor = _isLoadingStatus
        ? AppColors.text50
        : (_isWorkspaceStorageGranted
              ? const Color(0xFF1E9E63)
              : AppColors.buttonPrimary);
    final workspaceActionEnabled =
        !_isLoadingStatus &&
        !_isWorkspaceStorageGranted &&
        !_isOpeningWorkspaceStorageSettings;

    return _buildSectionCard(
      title: '当前状态与操作',
      child: Column(
        children: [
          _StatusActionRow(
            title: '内嵌 Ubuntu 运行时',
            subtitle: _buildRuntimeSubtitle(),
            actionText: runtimeActionText,
            actionColor: runtimeActionColor,
            onTap: runtimeActionEnabled ? _handlePrepareWrapper : null,
          ),
          const SizedBox(height: 12),
          _StatusActionRow(
            title: '公共 workspace 访问',
            subtitle: _isLoadingStatus
                ? '正在检测共享工作区访问能力'
                : (_isWorkspaceStorageGranted
                      ? '已允许访问 /storage/emulated/0/workspace'
                      : '未授权，文件工具和工作区预览会受限'),
            actionText: workspaceActionText,
            actionColor: workspaceActionColor,
            onTap: workspaceActionEnabled
                ? _handleOpenWorkspaceStorageSettings
                : null,
          ),
          const SizedBox(height: 14),
          _buildPrepareActionButton(),
          if (_shouldShowPrepareConsole) ...[
            const SizedBox(height: 14),
            _buildPrepareConsolePanel(),
          ],
          if (_wrapperMessage != null &&
              _wrapperMessage!.isNotEmpty &&
              !_shouldShowPrepareConsole) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_wrapperReady == true)
                    ? const Color(0x141E9E63)
                    : const Color(0x14EF6B5F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _wrapperMessage!,
                style: TextStyle(
                  color: _wrapperReady == true
                      ? const Color(0xFF1E9E63)
                      : const Color(0xFFB34A40),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrepareConsolePanel() {
    final stageText =
        _prepareStage ?? (_isPreparingWrapper ? '初始化进行中' : '最近一次初始化日志');
    final consoleText = _prepareLogLines.isEmpty
        ? '[系统] 初始化已启动，等待终端输出...'
        : _prepareLogLines.join('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isPreparingWrapper
                      ? const Color(0xFFF6C94C)
                      : (_wrapperReady == true
                            ? const Color(0xFF1E9E63)
                            : const Color(0xFF8091A7)),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stageText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220, minHeight: 120),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111B2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: SingleChildScrollView(
              controller: _prepareLogScrollController,
              child: SelectableText(
                consoleText,
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrepareActionButton() {
    final progress = _isPreparingWrapper
        ? _prepareProgress.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final progressPercent = (progress * 100).round();

    final bool disabled =
        _isPreparingWrapper || !_isDeviceSupported || _isFullyReady;
    final bool showInitState =
        _isDeviceSupported && !_isPreparingWrapper && !_isFullyReady;
    final buttonText = _isPreparingWrapper
        ? '初始化中... $progressPercent%'
        : (!_isDeviceSupported
              ? '当前设备不支持（仅 arm64-v8a）'
              : (_isFullyReady ? '内嵌 Ubuntu 已就绪' : '初始化内嵌 Ubuntu 环境'));
    final gradientColors = _isPreparingWrapper
        ? const [Color(0xFF1930D9), Color(0xFF2DA5F0)]
        : (!_isDeviceSupported
              ? const [Color(0xFFBFC7D5), Color(0xFFA6AFBE)]
              : (showInitState
                    ? const [Color(0xFFE58A00), Color(0xFFFFB84D)]
                    : const [Color(0xFF1E9E63), Color(0xFF45C07B)]));

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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    if (_isPreparingWrapper)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: constraints.maxWidth * progress,
                            height: double.infinity,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [Color(0x4DFFFFFF), Color(0x2AFFFFFF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Center(
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
                  ],
                );
              },
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
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  gatewayStatus?.dashboardUrl?.isNotEmpty == true
                      ? gatewayStatus!.dashboardUrl!
                      : '部署成功后会固定回连到 http://127.0.0.1:18789',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed:
                    (_isLoadingGatewayStatus ||
                        _isStartingGateway ||
                        gatewayStatus == null)
                    ? null
                    : () => _handleStartGateway(forceRestart: false),
                child: Text(_isStartingGateway ? '启动中...' : '启动 Gateway'),
              ),
              FilledButton.tonal(
                onPressed:
                    (_isLoadingGatewayStatus ||
                        _isStartingGateway ||
                        gatewayStatus == null)
                    ? null
                    : () => _handleStartGateway(forceRestart: true),
                child: const Text('重启 Gateway'),
              ),
              OutlinedButton(
                onPressed: (_isLoadingGatewayStatus || _isStoppingGateway)
                    ? null
                    : _handleStopGateway,
                child: Text(_isStoppingGateway ? '停止中...' : '停止 Gateway'),
              ),
              OutlinedButton(
                onPressed: _isOpeningNativeTerminal
                    ? null
                    : _handleOpenNativeTerminal,
                child: Text(_isOpeningNativeTerminal ? '打开中...' : '打开原生终端'),
              ),
            ],
          ),
        ],
      ),
    );
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
      final uptimeText = status.uptimeSeconds == null
          ? ''
          : '，已运行 ${_formatUptime(status.uptimeSeconds!)}';
      return 'Gateway 正在运行且健康$uptimeText';
    }
    if (status.running) {
      return 'Gateway 已启动，正在等待健康检查';
    }
    return 'Gateway 当前未运行';
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
