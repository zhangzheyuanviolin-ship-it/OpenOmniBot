import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class _EnvironmentDefinition {
  const _EnvironmentDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
  });

  final String id;
  final String title;
  final String description;
  final String group;
}

class _EnvironmentViewModel {
  const _EnvironmentViewModel({
    required this.definition,
    required this.ready,
    required this.version,
  });

  final _EnvironmentDefinition definition;
  final bool ready;
  final String? version;
}

const List<_EnvironmentDefinition> _environmentDefinitions =
    <_EnvironmentDefinition>[
      _EnvironmentDefinition(
        id: 'nodejs',
        title: 'nodejs',
        description: 'Node.js 运行时',
        group: '开发环境',
      ),
      _EnvironmentDefinition(
        id: 'npm',
        title: 'npm',
        description: 'Node.js 包管理器',
        group: '开发环境',
      ),
      _EnvironmentDefinition(
        id: 'git',
        title: 'git',
        description: 'Git 版本控制',
        group: '开发环境',
      ),
      _EnvironmentDefinition(
        id: 'python',
        title: 'python',
        description: 'Python 解释器',
        group: '开发环境',
      ),
      _EnvironmentDefinition(
        id: 'uv',
        title: 'uv',
        description: 'Python 项目与包工具',
        group: '开发环境',
      ),
      _EnvironmentDefinition(
        id: 'pip',
        title: 'pip',
        description: 'Python 包安装器',
        group: '开发环境',
      ),
      _EnvironmentDefinition(
        id: 'ssh_client',
        title: 'ssh',
        description: 'SSH 客户端',
        group: 'SSH',
      ),
      _EnvironmentDefinition(
        id: 'sshpass',
        title: 'sshpass',
        description: 'SSH 密码辅助工具',
        group: 'SSH',
      ),
      _EnvironmentDefinition(
        id: 'openssh_server',
        title: 'sshd',
        description: 'OpenSSH 服务器',
        group: 'SSH',
      ),
    ];

class TermuxSettingPage extends StatefulWidget {
  const TermuxSettingPage({super.key});

  @override
  State<TermuxSettingPage> createState() => _TermuxSettingPageState();
}

class _TermuxSettingPageState extends State<TermuxSettingPage>
    with WidgetsBindingObserver {
  bool _isOpeningSetup = false;
  bool _isDetecting = true;
  bool _isAutoStartLoading = true;
  bool _isAutoStartBusy = false;
  bool _hasInitializedSelection = false;
  String? _detectError;
  String? _autoStartError;
  Map<String, EmbeddedTerminalSetupInventoryItem> _inventory =
      const <String, EmbeddedTerminalSetupInventoryItem>{};
  List<EmbeddedTerminalAutoStartTask> _autoStartTasks =
      const <EmbeddedTerminalAutoStartTask>[];
  Set<String> _selectedPackageIds = <String>{};

  List<_EnvironmentViewModel> get _items {
    return _environmentDefinitions
        .map((definition) {
          final item = _inventory[definition.id];
          return _EnvironmentViewModel(
            definition: definition,
            ready: item?.ready == true,
            version: item?.version,
          );
        })
        .toList(growable: false);
  }

  int get _selectedLostCount {
    return _items
        .where(
          (item) =>
              !item.ready && _selectedPackageIds.contains(item.definition.id),
        )
        .length;
  }

  bool get _canStartSetup => !_isDetecting && _selectedLostCount > 0;

  bool get _isDarkTheme => context.isDarkTheme;
  Color get _pageBackground => _isDarkTheme
      ? context.omniPalette.pageBackground
      : const Color(0xFFF6F8FA);
  Color get _cardColor =>
      _isDarkTheme ? context.omniPalette.surfacePrimary : Colors.white;
  Color get _cardBorderColor =>
      _isDarkTheme ? context.omniPalette.borderSubtle : Colors.transparent;
  Color get _primaryTextColor =>
      _isDarkTheme ? context.omniPalette.textPrimary : AppColors.text;
  Color get _secondaryTextColor => _isDarkTheme
      ? context.omniPalette.textSecondary
      : const Color(0xFF64748B);
  Color get _tertiaryTextColor =>
      _isDarkTheme ? context.omniPalette.textTertiary : const Color(0xFF475569);
  Color get _mutedSurfaceColor => _isDarkTheme
      ? context.omniPalette.surfaceSecondary
      : const Color(0xFFF8FAFC);
  List<BoxShadow>? get _cardShadow => _isDarkTheme
      ? [
          BoxShadow(
            color: context.omniPalette.shadowColor.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ]
      : [AppColors.boxShadow];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshInventory(selectMissingByDefault: true));
    unawaited(_refreshAutoStartTasks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInventory());
      unawaited(_refreshAutoStartTasks());
    }
  }

  Future<void> _refreshInventory({bool selectMissingByDefault = false}) async {
    if (mounted) {
      setState(() {
        _isDetecting = true;
        _detectError = null;
      });
    }
    try {
      final inventory = await getEmbeddedTerminalSetupInventory();
      final nextSelected = <String>{};
      final shouldSelectMissing =
          selectMissingByDefault || !_hasInitializedSelection;
      for (final definition in _environmentDefinitions) {
        final item = inventory.packages[definition.id];
        final ready = item?.ready == true;
        if (ready) {
          continue;
        }
        if (_selectedPackageIds.contains(definition.id) ||
            shouldSelectMissing) {
          nextSelected.add(definition.id);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _inventory = inventory.packages;
        _selectedPackageIds = nextSelected;
        _hasInitializedSelection = true;
        _isDetecting = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inventory = const <String, EmbeddedTerminalSetupInventoryItem>{};
        _selectedPackageIds = _environmentDefinitions
            .map((definition) => definition.id)
            .toSet();
        _hasInitializedSelection = true;
        _isDetecting = false;
        _detectError = e.message ?? '检测 Alpine 环境失败';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inventory = const <String, EmbeddedTerminalSetupInventoryItem>{};
        _selectedPackageIds = _environmentDefinitions
            .map((definition) => definition.id)
            .toSet();
        _hasInitializedSelection = true;
        _isDetecting = false;
        _detectError = '检测 Alpine 环境失败';
      });
    }
  }

  Future<void> _refreshAutoStartTasks() async {
    if (mounted) {
      setState(() {
        _isAutoStartLoading = true;
        _autoStartError = null;
      });
    }
    try {
      final tasks = await getEmbeddedTerminalAutoStartTasks();
      if (!mounted) {
        return;
      }
      setState(() {
        _autoStartTasks = tasks.tasks;
        _isAutoStartLoading = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _autoStartTasks = const <EmbeddedTerminalAutoStartTask>[];
        _isAutoStartLoading = false;
        _autoStartError = e.message ?? '读取自启动任务失败';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _autoStartTasks = const <EmbeddedTerminalAutoStartTask>[];
        _isAutoStartLoading = false;
        _autoStartError = '读取自启动任务失败';
      });
    }
  }

  Future<void> _handleOpenSetupPage() async {
    if (_isOpeningSetup || !_canStartSetup) {
      return;
    }
    setState(() {
      _isOpeningSetup = true;
    });
    try {
      await openNativeTerminal(
        openSetup: true,
        setupPackageIds: _selectedPackageIds.toList(growable: false),
      );
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

  Future<void> _openAutoStartTaskDialog({
    EmbeddedTerminalAutoStartTask? task,
  }) async {
    final formResult = await showDialog<_AutoStartTaskFormResult>(
      context: context,
      builder: (dialogContext) => _AutoStartTaskDialog(task: task),
    );
    if (formResult == null || _isAutoStartBusy) {
      return;
    }
    setState(() {
      _isAutoStartBusy = true;
    });
    try {
      await saveEmbeddedTerminalAutoStartTask(
        id: task?.id,
        name: formResult.name,
        command: formResult.command,
        workingDirectory: formResult.workingDirectory,
        enabled: formResult.enabled,
      );
      await _refreshAutoStartTasks();
      if (!mounted) return;
      showToast(task == null ? '已新增自启动任务' : '已更新自启动任务');
    } on PlatformException catch (e) {
      showToast(e.message ?? '保存自启动任务失败', type: ToastType.error);
    } catch (_) {
      showToast('保存自启动任务失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isAutoStartBusy = false;
        });
      }
    }
  }

  Future<void> _toggleAutoStartTask(
    EmbeddedTerminalAutoStartTask task,
    bool enabled,
  ) async {
    if (_isAutoStartBusy) {
      return;
    }
    setState(() {
      _isAutoStartBusy = true;
    });
    try {
      await saveEmbeddedTerminalAutoStartTask(
        id: task.id,
        name: task.name,
        command: task.command,
        workingDirectory: task.workingDirectory,
        enabled: enabled,
      );
      await _refreshAutoStartTasks();
      if (!mounted) return;
      showToast(enabled ? '已开启应用启动时自启动' : '已关闭自动启动');
    } on PlatformException catch (e) {
      showToast(e.message ?? '更新任务失败', type: ToastType.error);
    } catch (_) {
      showToast('更新任务失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isAutoStartBusy = false;
        });
      }
    }
  }

  Future<void> _deleteAutoStartTask(EmbeddedTerminalAutoStartTask task) async {
    if (_isAutoStartBusy) {
      return;
    }
    final confirmed = await AppDialog.confirm(
      context,
      title: '删除自启动任务',
      content: '确认删除“${task.name}”吗？',
      cancelText: '取消',
      confirmText: '删除',
    );
    if (confirmed != true || _isAutoStartBusy) {
      return;
    }
    setState(() {
      _isAutoStartBusy = true;
    });
    try {
      await deleteEmbeddedTerminalAutoStartTask(task.id);
      await _refreshAutoStartTasks();
      if (!mounted) return;
      showToast('已删除自启动任务');
    } on PlatformException catch (e) {
      showToast(e.message ?? '删除任务失败', type: ToastType.error);
    } catch (_) {
      showToast('删除任务失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isAutoStartBusy = false;
        });
      }
    }
  }

  Future<void> _runAutoStartTask(EmbeddedTerminalAutoStartTask task) async {
    if (_isAutoStartBusy) {
      return;
    }
    setState(() {
      _isAutoStartBusy = true;
    });
    try {
      final result = await runEmbeddedTerminalAutoStartTask(task.id);
      await _refreshAutoStartTasks();
      if (!mounted) return;
      showToast(result.message.isNotEmpty ? result.message : '启动命令已发送');
    } on PlatformException catch (e) {
      showToast(e.message ?? '启动任务失败', type: ToastType.error);
    } catch (_) {
      showToast('启动任务失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isAutoStartBusy = false;
        });
      }
    }
  }

  void _togglePackage(String packageId, bool? value) {
    setState(() {
      if (value == true) {
        _selectedPackageIds = <String>{..._selectedPackageIds, packageId};
      } else {
        _selectedPackageIds = _selectedPackageIds
            .where((id) => id != packageId)
            .toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupedItems = <String, List<_EnvironmentViewModel>>{};
    for (final item in _items) {
      groupedItems.putIfAbsent(
        item.definition.group,
        () => <_EnvironmentViewModel>[],
      );
      groupedItems[item.definition.group]!.add(item);
    }

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: const CommonAppBar(title: 'Alpine 环境', primary: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _refreshInventory();
            await _refreshAutoStartTasks();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildIntroCard(),
              const SizedBox(height: 14),
              if (_detectError != null) ...[
                _buildErrorCard(_detectError!),
                const SizedBox(height: 14),
              ],
              for (final entry in groupedItems.entries) ...[
                _buildSectionCard(
                  title: entry.key,
                  child: Column(
                    children: [
                      for (
                        int index = 0;
                        index < entry.value.length;
                        index++
                      ) ...[
                        _buildEnvironmentTile(entry.value[index]),
                        if (index != entry.value.length - 1)
                          const Divider(height: 20, thickness: 0.6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canStartSetup && !_isOpeningSetup
                      ? _handleOpenSetupPage
                      : null,
                  icon: _isOpeningSetup
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.terminal_rounded),
                  label: Text(
                    _isDetecting
                        ? '正在检测环境'
                        : _selectedLostCount > 0
                        ? '开始配置（$_selectedLostCount 项）'
                        : '全部已就绪',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildAutoStartSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    final readyCount = _items.where((item) => item.ready).length;
    return _buildSectionCard(
      title: '环境配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isDetecting
                ? '正在后台检测 Alpine 内常见开发环境的版本信息。'
                : '已就绪 $readyCount/${_items.length} 项，可直接勾选缺失项并进入 ReTerminal 自动配置。',
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildAutoStartSection() {
    return _buildSectionCard(
      title: '自启动任务',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '打开 Omnibot 时会在后台检查已启用的任务，并在对应 ReTerminal 会话内启动命令，适合常驻服务。',
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isAutoStartBusy
                      ? null
                      : () => _openAutoStartTaskDialog(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增任务'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isAutoStartBusy
                      ? null
                      : () => openNativeTerminal(),
                  icon: const Icon(Icons.terminal_rounded),
                  label: const Text('打开 终端'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_autoStartError != null) ...[
            _buildErrorCard(_autoStartError!),
          ] else if (_isAutoStartLoading) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ] else if (_autoStartTasks.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _mutedSurfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDarkTheme
                      ? context.omniPalette.borderSubtle
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                '暂无任务。你可以添加例如 `python app.py`、`node server.js`、`./start.sh` 之类的常驻命令。',
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          ] else ...[
            for (int index = 0; index < _autoStartTasks.length; index++) ...[
              _buildAutoStartTaskTile(_autoStartTasks[index]),
              if (index != _autoStartTasks.length - 1)
                const Divider(height: 20, thickness: 0.6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAutoStartTaskTile(EmbeddedTerminalAutoStartTask task) {
    final workingDirectory = task.workingDirectory?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name,
                    style: TextStyle(
                      color: _primaryTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildLegendTag(
                        label: task.enabled ? '开机打开 app 后启动' : '未启用',
                        backgroundColor: task.enabled
                            ? const Color(0xFFEAF2FF)
                            : const Color(0xFFF1F5F9),
                        foregroundColor: task.enabled
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF64748B),
                      ),
                      _buildLegendTag(
                        label: task.running ? 'running' : 'idle',
                        backgroundColor: task.running
                            ? const Color(0xFFE8F7EE)
                            : const Color(0xFFFFF7ED),
                        foregroundColor: task.running
                            ? const Color(0xFF17803D)
                            : const Color(0xFFC2410C),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: task.enabled,
              onChanged: _isAutoStartBusy
                  ? null
                  : (value) => _toggleAutoStartTask(task, value),
              activeTrackColor: const Color(0xFF93C5FD),
              activeThumbColor: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _mutedSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDarkTheme
                  ? context.omniPalette.borderSubtle
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.command,
                style: TextStyle(
                  color: _primaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
              if (workingDirectory != null && workingDirectory.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '工作目录：$workingDirectory',
                  style: TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: _isAutoStartBusy
                  ? null
                  : () => _runAutoStartTask(task),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(task.running ? '已在运行' : '立即启动'),
            ),
            TextButton.icon(
              onPressed: _isAutoStartBusy
                  ? null
                  : () => _openAutoStartTaskDialog(task: task),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑'),
            ),
            TextButton.icon(
              onPressed: _isAutoStartBusy
                  ? null
                  : () => _deleteAutoStartTask(task),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnvironmentTile(_EnvironmentViewModel item) {
    final selected = _selectedPackageIds.contains(item.definition.id);
    final versionText = item.version?.trim().isNotEmpty == true
        ? item.version!.trim()
        : (item.ready ? '已检测到可用版本' : '未检测到');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: item.ready
              ? const Icon(
                  Icons.check_box_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                )
              : Checkbox(
                  value: selected,
                  activeColor: const Color(0xFF2563EB),
                  onChanged: _isDetecting
                      ? null
                      : (value) => _togglePackage(item.definition.id, value),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.definition.title,
                style: TextStyle(
                  color: _primaryTextColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.definition.description,
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_isDetecting && !_inventory.containsKey(item.definition.id))
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _buildLegendTag(
                  label: item.ready ? 'ready' : 'lost',
                  backgroundColor: item.ready
                      ? const Color(0xFFE8F7EE)
                      : const Color(0xFFEAF2FF),
                  foregroundColor: item.ready
                      ? const Color(0xFF17803D)
                      : const Color(0xFF2563EB),
                ),
              const SizedBox(height: 6),
              Text(
                versionText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _tertiaryTextColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendTag({
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorderColor),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _primaryTextColor,
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

class _AutoStartTaskFormResult {
  const _AutoStartTaskFormResult({
    required this.name,
    required this.command,
    required this.workingDirectory,
    required this.enabled,
  });

  final String name;
  final String command;
  final String? workingDirectory;
  final bool enabled;
}

class _AutoStartTaskDialog extends StatefulWidget {
  const _AutoStartTaskDialog({this.task});

  final EmbeddedTerminalAutoStartTask? task;

  @override
  State<_AutoStartTaskDialog> createState() => _AutoStartTaskDialogState();
}

class _AutoStartTaskDialogState extends State<_AutoStartTaskDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _commandController;
  late final TextEditingController _workingDirectoryController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task?.name ?? '');
    _commandController = TextEditingController(
      text: widget.task?.command ?? '',
    );
    _workingDirectoryController = TextEditingController(
      text: widget.task?.workingDirectory ?? '/workspace',
    );
    _enabled = widget.task?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _workingDirectoryController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    final workingDirectory = _workingDirectoryController.text.trim();
    if (name.isEmpty) {
      showToast('请输入任务名称', type: ToastType.error);
      return;
    }
    if (command.isEmpty) {
      showToast('请输入启动命令', type: ToastType.error);
      return;
    }
    Navigator.of(context).pop(
      _AutoStartTaskFormResult(
        name: name,
        command: command,
        workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.task != null;
    return AlertDialog(
      title: Text(editing ? '编辑自启动任务' : '新增自启动任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '任务名称',
                hintText: '例如：本地 API 服务',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commandController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '启动命令',
                hintText: '例如：python app.py 或 pnpm start',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _workingDirectoryController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '工作目录',
                hintText: '/workspace',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
              title: const Text('打开 Omnibot 时自动启动'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(editing ? '保存' : '创建')),
      ],
    );
  }
}
