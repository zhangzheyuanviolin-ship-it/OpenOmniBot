import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/gradient_button.dart';

class TermuxSettingPage extends StatefulWidget {
  const TermuxSettingPage({super.key});

  @override
  State<TermuxSettingPage> createState() => _TermuxSettingPageState();
}

class _TermuxSettingPageState extends State<TermuxSettingPage>
    with WidgetsBindingObserver {
  static const String _termuxDownloadUrl =
      'https://cloud.tsinghua.edu.cn/f/b44766c47a7a4e799d82/?dl=1';
  static const String _termuxInitCommand =
      r'''value="true"; key="allow-external-apps"; file="/data/data/com.termux/files/home/.termux/termux.properties"; workspace_root="/storage/emulated/0/workspace"; mkdir -p "$(dirname "$file")"; chmod 700 "$(dirname "$file")"; if ! grep -E '^'"$key"'=.*' "$file" >/dev/null 2>&1; then [[ -s "$file" && -n "$(tail -c 1 "$file")" ]] && newline=$'\n' || newline=""; echo "$newline$key=$value" >> "$file"; else sed -i'' -E 's/^'"$key"'=.*/'"$key=$value"'/' "$file"; fi; termux-reload-settings; termux-setup-storage; mkdir -p "$workspace_root" "$workspace_root/.omnibot"; if ! command -v proot-distro >/dev/null 2>&1; then pkg update -y && pkg install -y proot-distro; fi; if ! proot-distro login ubuntu --bind "$workspace_root:/workspace" --shared-tmp -- bash -lc 'exit 0' >/dev/null 2>&1; then proot-distro install ubuntu; fi; alias_line="alias u='proot-distro login ubuntu --bind /storage/emulated/0/workspace:/workspace'"; touch ~/.bashrc; sed -i '/^alias u=/d' ~/.bashrc; echo "$alias_line" >> ~/.bashrc; bash -ic "u --shared-tmp -- bash -lc 'test -d /workspace && test -w /workspace'" >/dev/null 2>&1''';

  bool _isLoadingStatus = true;
  bool _isTermuxInstalled = false;
  bool _isRunCommandGranted = false;
  bool _isUnknownAppInstallAllowed = false;
  bool _isWorkspaceStorageGranted = false;

  bool _isRequestingPermission = false;
  bool _isInstallingTermux = false;
  bool _isOpeningAppSettings = false;
  bool _isPreparingWrapper = false;
  bool _isOpeningWorkspaceStorageSettings = false;

  String? _wrapperMessage;
  bool? _wrapperReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
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
    setState(() {
      _isLoadingStatus = true;
    });

    final installed = await isTermuxInstalled();
    final granted = installed
        ? await isTermuxRunCommandPermissionGranted()
        : false;
    final unknownAppInstallAllowed = await isUnknownAppInstallAllowed();
    final workspaceStorageGranted = await isWorkspaceStorageAccessGranted();

    if (!mounted) {
      return;
    }
    setState(() {
      _isTermuxInstalled = installed;
      _isRunCommandGranted = granted;
      _isUnknownAppInstallAllowed = unknownAppInstallAllowed;
      _isWorkspaceStorageGranted = workspaceStorageGranted;
      _isLoadingStatus = false;
    });
  }

  Future<void> _handleRequestPermission() async {
    if (_isRequestingPermission) {
      return;
    }
    if (!_isTermuxInstalled) {
      showToast('请先安装 Termux', type: ToastType.warning);
      return;
    }

    setState(() {
      _isRequestingPermission = true;
    });

    try {
      final granted = await requestTermuxRunCommandPermission();
      await _refreshStatus();
      if (!mounted) {
        return;
      }
      if (granted || _isRunCommandGranted) {
        showToast('RUN_COMMAND 权限已授权', type: ToastType.success);
      } else {
        showToast('未完成授权，请尝试打开系统权限页手动开启', type: ToastType.warning);
      }
    } on PlatformException catch (e) {
      showToast(e.message ?? '请求权限失败', type: ToastType.error);
    } catch (e) {
      showToast('请求权限失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermission = false;
        });
      }
    }
  }

  Future<void> _handleOpenAppDetails() async {
    if (_isOpeningAppSettings) {
      return;
    }
    setState(() {
      _isOpeningAppSettings = true;
    });
    try {
      await openAppDetailsSettings();
    } on PlatformException catch (e) {
      showToast(e.message ?? '打开系统权限页失败', type: ToastType.error);
    } catch (e) {
      showToast('打开系统权限页失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAppSettings = false;
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
    } catch (e) {
      showToast('打开公共 workspace 权限页失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningWorkspaceStorageSettings = false;
        });
      }
    }
  }

  Future<void> _handleInstallTermux() async {
    if (_isInstallingTermux) {
      return;
    }
    setState(() {
      _isInstallingTermux = true;
    });
    try {
      final result = await downloadAndInstallTermuxApk(_termuxDownloadUrl);
      final success = result['success'] == true;
      final status = (result['status'] as String?)?.trim();
      final message = (result['message'] as String?)?.trim();

      if (message?.isNotEmpty == true) {
        showToast(
          message!,
          type: success ? ToastType.success : ToastType.warning,
        );
      }

      if (status == 'install_permission_required') {
        await _refreshStatus();
      }
    } on PlatformException catch (e) {
      showToast(e.message ?? '下载安装 Termux 失败', type: ToastType.error);
    } catch (e) {
      showToast('下载安装 Termux 失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isInstallingTermux = false;
        });
      }
    }
  }

  Future<void> _handlePrepareWrapper() async {
    if (_isPreparingWrapper) {
      return;
    }
    if (!_isTermuxInstalled) {
      showToast('请先安装 Termux', type: ToastType.warning);
      return;
    }
    if (!_isRunCommandGranted) {
      showToast('请先完成 RUN_COMMAND 权限授权', type: ToastType.warning);
      return;
    }

    setState(() {
      _isPreparingWrapper = true;
    });
    try {
      final result = await prepareTermuxLiveWrapper();
      final success = result['success'] == true;
      final message = (result['message'] as String?)?.trim();
      if (!mounted) {
        return;
      }
      setState(() {
        _wrapperReady = success;
        _wrapperMessage = message;
      });
      showToast(
        message?.isNotEmpty == true ? message! : '已完成检查',
        type: success ? ToastType.success : ToastType.warning,
      );
    } on PlatformException catch (e) {
      showToast(e.message ?? '检查 Wrapper 失败', type: ToastType.error);
    } catch (e) {
      showToast('检查 Wrapper 失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingWrapper = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: const CommonAppBar(title: 'Termux 设置', primary: true),
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
                      _buildHeroCard(),
                      const SizedBox(height: 12),
                      _buildStatusCard(),
                      const SizedBox(height: 12),
                      _buildActionsCard(),
                      const SizedBox(height: 12),
                      _buildGuideCard(),
                      const SizedBox(height: 12),
                      _buildWrapperCard(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeroCard() {
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.terminal_rounded,
              color: AppColors.buttonPrimary,
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '这里集中管理 Termux 相关能力，包括安装入口、RUN_COMMAND 权限授权，以及实时终端输出所需的基础准备。',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Termux 是统一 Agent 的可选增强能力，不影响基础无障碍自动化；安装完成后，回到本页会自动刷新状态。',
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.68),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return _buildSectionCard(
      title: '当前状态',
      child: Column(
        children: [
          _StatusRow(
            title: 'Termux App',
            subtitle: _isLoadingStatus
                ? '正在检测安装状态'
                : (_isTermuxInstalled ? '已检测到 com.termux' : '尚未安装'),
            isEnabled: _isTermuxInstalled,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            title: 'RUN_COMMAND 权限',
            subtitle: _isLoadingStatus
                ? '正在检测权限状态'
                : (_isRunCommandGranted ? '已授权' : '未授权'),
            isEnabled: _isRunCommandGranted,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            title: '安装未知应用',
            subtitle: _isLoadingStatus
                ? '正在检测安装权限'
                : (_isUnknownAppInstallAllowed ? '已允许本应用拉起安装器' : '尚未允许'),
            isEnabled: _isUnknownAppInstallAllowed,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            title: '公共 workspace 访问',
            subtitle: _isLoadingStatus
                ? '正在检测共享工作区访问能力'
                : (_isWorkspaceStorageGranted
                      ? '已允许访问 /storage/emulated/0/workspace'
                      : '未授权，文件工具和工作区预览会受限'),
            isEnabled: _isWorkspaceStorageGranted,
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard() {
    return _buildSectionCard(
      title: '快速操作',
      child: Column(
        children: [
          GradientButton(
            text: _isRequestingPermission ? '请求中...' : '请求 RUN_COMMAND 权限',
            width: double.infinity,
            height: 46,
            borderRadius: 12,
            enabled: !_isRequestingPermission,
            onTap: _handleRequestPermission,
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '如果系统没有弹出授权对话框，或者授权后状态仍未刷新，可以继续使用下面的系统权限页入口。',
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.64),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _ActionTile(
            title: '打开本应用权限页',
            description: '进入系统的应用详情/权限页，手动开启 Termux 的自定义权限。',
            buttonText: _isOpeningAppSettings ? '打开中...' : '去设置',
            onTap: _handleOpenAppDetails,
            enabled: !_isOpeningAppSettings,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            title: '打开公共 workspace 权限页',
            description: '允许 Omnibot 访问 /storage/emulated/0/workspace，文件工具、skills 和工作区预览都依赖它。',
            buttonText: _isOpeningWorkspaceStorageSettings ? '打开中...' : '去授权',
            onTap: _handleOpenWorkspaceStorageSettings,
            enabled: !_isOpeningWorkspaceStorageSettings,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            title: '一键下载安装 Termux',
            description: '直接在 App 内下载 APK，完成后自动拉起系统安装器。',
            buttonText: _isInstallingTermux
                ? '处理中...'
                : (_isTermuxInstalled ? '重新下载安装' : '立即安装'),
            onTap: _handleInstallTermux,
            enabled: !_isInstallingTermux,
          ),
        ],
      ),
    );
  }

  Widget _buildWrapperCard() {
    final hasMessage = _wrapperMessage != null && _wrapperMessage!.isNotEmpty;

    return _buildSectionCard(
      title: 'Wrapper 与实时输出',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'live_exec wrapper 不是一个需要常驻后台保持运行的进程。当前实现会在每次终端工具执行前自动校验并按需重新部署，所以通常不需要你手动“先跑起来”。',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '如果你怀疑 Termux 环境被重置、wrapper 丢失，或者实时输出始终没有刷出来，可以手动执行一次检查与重新部署。',
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.68),
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          _ActionTile(
            title: '检查并重新部署 Wrapper',
            description: '会校验 allow-external-apps、wrapper 脚本和共享存储写入能力。',
            buttonText: _isPreparingWrapper ? '检查中...' : '立即检查',
            onTap: _handlePrepareWrapper,
            enabled: !_isPreparingWrapper,
          ),
          if (hasMessage) ...[
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

  Widget _buildGuideCard() {
    return _buildSectionCard(
      title: '配置说明',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GuideText(
            index: '1',
            text:
                '先使用上方的一键安装完成 Termux，再打开一次 Termux，确保基础环境已经初始化；然后在 Termux 里执行下方这条一键初始化指令即可。',
          ),
          const SizedBox(height: 8),
          const _GuideText(
            index: '2',
            text:
                '回到本页授权 com.termux.permission.RUN_COMMAND，并同时开启公共 workspace 访问；如果系统不弹窗，请打开对应的系统设置页手动开启。',
          ),
          const SizedBox(height: 8),
          const _GuideText(
            index: '3',
            text:
                '执行完成后会自动安装 Ubuntu、写入 alias u 并做登录验证；后续终端工具会直接在 Ubuntu 内执行，并通过 /workspace 与安卓公共目录共享文件。',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Termux 一键初始化指令',
                  style: TextStyle(
                    color: AppColors.text.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _termuxInitCommand),
                  );
                  showToast(
                    '已复制一键初始化指令，正在打开 Termux',
                    type: ToastType.success,
                  );
                  try {
                    final opened = await openTermuxApp();
                    if (!opened) {
                      showToast('未检测到 Termux，请先安装', type: ToastType.warning);
                    }
                  } on PlatformException catch (e) {
                    showToast(e.message ?? '打开 Termux 失败', type: ToastType.error);
                  } catch (e) {
                    showToast('打开 Termux 失败', type: ToastType.error);
                  }
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('复制并打开 Termux'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const SelectableText(
              _termuxInitCommand,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '将该指令整行复制到 Termux 执行一次即可（已包含 allow-external-apps、reload、storage、proot-distro、Ubuntu 安装和 alias u 配置）。',
            style: const TextStyle(
              color: AppColors.text70,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
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

class _StatusRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isEnabled;

  const _StatusRow({
    required this.title,
    required this.subtitle,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final color = isEnabled ? const Color(0xFF1E9E63) : const Color(0xFFB34A40);

    return Row(
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
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.text.withValues(alpha: 0.66),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isEnabled ? '已就绪' : '未就绪',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onTap;
  final bool enabled;

  const _ActionTile({
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
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
                Text(
                  description,
                  style: TextStyle(
                    color: AppColors.text.withValues(alpha: 0.65),
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFFEDF4FF)
                    : const Color(0xFFF1F1F1),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                buttonText,
                style: TextStyle(
                  color: enabled ? AppColors.buttonPrimary : AppColors.text50,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideText extends StatelessWidget {
  final String index;
  final String text;

  const _GuideText({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Color(0xFFECF5FF),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            index,
            style: const TextStyle(
              color: AppColors.buttonPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.76),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}
