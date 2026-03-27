import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/theme/app_colors.dart';
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
  bool _hasInitializedSelection = false;
  String? _detectError;
  Map<String, EmbeddedTerminalSetupInventoryItem> _inventory =
      const <String, EmbeddedTerminalSetupInventoryItem>{};
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshInventory(selectMissingByDefault: true));
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
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: const CommonAppBar(title: 'Alpine 环境', primary: true),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _refreshInventory(),
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
              const SizedBox(height: 10),
              const Text(
                '点击开始配置后会进入 ReTerminal，并自动安装当前勾选的缺失环境。退出 ReTerminal 后会回到这里。',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
                ),
              ),
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
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildLegendTag(
                label: 'ready',
                backgroundColor: const Color(0xFFE8F7EE),
                foregroundColor: const Color(0xFF17803D),
              ),
              const SizedBox(width: 8),
              _buildLegendTag(
                label: 'lost',
                backgroundColor: const Color(0xFFEAF2FF),
                foregroundColor: const Color(0xFF2563EB),
              ),
            ],
          ),
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
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.definition.description,
                style: const TextStyle(
                  color: Color(0xFF64748B),
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
                style: const TextStyle(
                  color: Color(0xFF475569),
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
