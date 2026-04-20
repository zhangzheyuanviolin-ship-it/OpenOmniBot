import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/core/mixins/page_lifecycle_mixin.dart';
import 'package:ui/features/memory/pages/memory_center/widgets/tag_section.dart';
import 'package:ui/features/task/pages/scheduled_tasks/widgets/schedule_task_sheet.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/scheduled_task_scheduler_service.dart';
import 'package:ui/services/scheduled_task_storage_service.dart';
import 'package:ui/features/task/pages/execution_history/widgets/execution_record_list_item.dart';
import 'package:intl/intl.dart';

import 'package:ui/theme/app_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/features/memory/pages/memory_center/widgets/batch_delete_confirm_sheet.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/features/task/pages/execution_history/widgets/execution_record_list.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/selection_bottom_bar.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/features/task/pages/execution_history/widgets/activity_dashboard_card.dart';

class TrajectoryPage extends StatefulWidget {
  const TrajectoryPage({super.key});

  @override
  State<TrajectoryPage> createState() =>
      _TrajectoryPageState();
}

class _TrajectoryPageState
    extends State<TrajectoryPage>
    with
        WidgetsBindingObserver,
        PageLifecycleMixin<TrajectoryPage> {
  List<AppTag> executionTags = [];

  List<ExecutionRecordListItemData> executionRecordViewModels = [];

  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  Set<String> selectedTagIds = {'all'};

  // 选择模式状态
  bool _isSelectionMode = false;
  Set<String> _selectedRecordKeys = {}; // 使用 goal 作为唯一标识

  Set<String> _scheduledTaskKeys = {};

  // OmniFlow run logs 状态
  UtgRunLogsSnapshot? _runLogsSnapshot;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadScheduledTaskKeys();
  }

  // ✅ 应用从后台回到前台时刷新
  @override
  void onPageResumed() {
    if (_hasLoadedOnce) {
      print('✅ ExecutionRecordPage resumed - reloading data silently');
      _loadData(silent: true);
      _loadScheduledTaskKeys();
    }
  }

  /// 加载 Provider run logs
  Future<void> _loadProviderRunLogs({bool silent = false}) async {
    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      if (!mounted) return;
      final snapshot = await AssistsMessageService.getUtgRunLogs(
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      _runLogsSnapshot = snapshot;
    } catch (e) {
      if (!mounted) return;
      print('Error loading provider run logs: $e');
      _runLogsSnapshot = null;
    }
  }

  /// 通过 OmniFlow 重放 run log
  Future<void> _replayRunLog(UtgRunLogSummary run) async {
    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      final result = await AssistsMessageService.replayUtgRunLog(
        runId: run.runId,
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      if (result.success) {
        showToast(context.trLegacy('开始重放'), type: ToastType.success);
      } else {
        showToast(result.errorMessage ?? context.trLegacy('重放失败'), type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      showToast('${context.trLegacy('重放失败')}：$e', type: ToastType.error);
    }
  }

  void _onTagSelectionChanged(Set<String> next, String triggerId) {
    setState(() {
      if (next.contains('all')) {
        if (triggerId != 'all' && next.length > 1) {
          next.remove('all');
        } else if (triggerId == 'all') {
          next = {'all'};
        }
      } else if (next.isEmpty) {
        next = {'all'};
      }
      selectedTagIds = next;
    });
  }

  /// 加载数据（仅 OmniFlow run logs）
  /// [silent] 是否静默刷新（不显示loading）
  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 只加载 OmniFlow run logs
      await _loadProviderRunLogs(silent: true);
      // 构建显示数据
      _buildExecutionRecords();

      setState(() {
        if (!silent) {
          _isLoading = false;
        }
      });
      _hasLoadedOnce = true;
    } catch (e) {
      print('Error loading data: $e');
      if (!silent) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadScheduledTaskKeys() async {
    try {
      final tasks = await ScheduledTaskStorageService.loadScheduledTasks();
      if (!mounted) return;
      setState(() {
        _scheduledTaskKeys = tasks
            .map((task) => '${task.nodeId}|${task.suggestionId}')
            .toSet();
      });
    } catch (e) {
      print('Error loading scheduled task keys: $e');
    }
  }

  /// 构建执行记录列表（仅 OmniFlow run logs）
  void _buildExecutionRecords() {
    final records = _convertOmniflowRunLogs();

    // 按时间排序（最新在前）
    records.sort((a, b) {
      final aTime = a.sortTimestamp ?? DateTime(1970);
      final bTime = b.sortTimestamp ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    // 构建标签（按 packageName 聚合）
    final tagList = <AppTag>[];
    tagList.add(
      AppTag(
        id: 'all',
        label: context.l10n.trajectoryAll,
        count: records.length,
        svgPath: 'assets/common/all_icon.svg',
        iconBgColor: Colors.black,
        iconColor: Colors.white,
      ),
    );

    // 按 packageName 分组统计
    final packageCounts = <String, int>{};
    for (final record in records) {
      if (record.packageName.isNotEmpty) {
        packageCounts[record.packageName] =
            (packageCounts[record.packageName] ?? 0) + 1;
      }
    }

    for (final entry in packageCounts.entries) {
      tagList.add(
        AppTag(
          id: entry.key,
          label: entry.key.split('.').last, // 简化显示
          count: entry.value,
          icon: Icons.apps,
          iconBgColor: const Color(0xFFE6F0FE),
        ),
      );
    }

    setState(() {
      executionTags = tagList;
      executionRecordViewModels = records;
    });
  }

  /// 将 OmniFlow run logs 按 goal 聚合为列表项
  List<ExecutionRecordListItemData> _convertOmniflowRunLogs() {
    final runLogs = _runLogsSnapshot?.runs ?? const <UtgRunLogSummary>[];
    if (runLogs.isEmpty) return [];

    // 按 goal 聚合
    final Map<String, List<UtgRunLogSummary>> groupedByGoal = {};
    for (final run in runLogs) {
      final key = run.goal.trim().isEmpty ? run.runId : run.goal.trim();
      groupedByGoal.putIfAbsent(key, () => []).add(run);
    }

    return groupedByGoal.entries.map((entry) {
      final goal = entry.key;
      final runs = entry.value;
      // 按时间排序，取最新的一条作为代表
      runs.sort((a, b) {
        final aTime = DateTime.tryParse(a.startedAt) ?? DateTime(1970);
        final bTime = DateTime.tryParse(b.startedAt) ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      final latestRun = runs.first;
      final executionCount = runs.length;

      // 解析时间
      DateTime? timestamp;
      if (latestRun.startedAt.isNotEmpty) {
        timestamp = DateTime.tryParse(latestRun.startedAt);
      }

      final timestampMs = timestamp?.millisecondsSinceEpoch;
      final section = timestampMs != null ? _getSection(timestampMs) : null;
      final timeLabel = timestampMs != null && section != null
          ? _getTimeLabel(section, timestampMs)
          : latestRun.startedAt;

      // OmniFlow 图标
      final iconsList = <Widget>[
        Builder(builder: (context) {
          return Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 14,
              color: Colors.white,
            ),
          );
        }),
      ];

      // 用于定时任务的唯一标识
      final nodeId = 'omniflow';
      final suggestionId = 'goal:$goal';

      return ExecutionRecordListItemData(
        id: goal.hashCode,
        title: goal,
        packageName: latestRun.finalPackageName,
        nodeId: nodeId,
        suggestionId: suggestionId,
        times: executionCount,
        section: section,
        lastExecutionTimeLabel: timeLabel,
        icons: iconsList,
        isExecutable: true,
        isSchedulable: true,
        isReplayable: latestRun.runId.isNotEmpty,
        runId: latestRun.runId,
        suggestionData: {
          'goal': goal,
          'runId': latestRun.runId,
          'packageName': latestRun.finalPackageName,
        },
        onExecute: () => _executeGoal(goal, latestRun.finalPackageName),
        onReplay: latestRun.runId.isNotEmpty
            ? () => _replayRunLog(latestRun)
            : null,
        sortTimestamp: timestamp,
      );
    }).toList();
  }

  /// 执行 goal（通过 VLM 任务）
  Future<void> _executeGoal(String goal, String packageName) async {
    if (goal.trim().isEmpty) {
      showToast(context.trLegacy('目标不能为空'), type: ToastType.error);
      return;
    }
    final success = await AssistsMessageService.createVLMOperationTask(
      goal,
      packageName: packageName.isNotEmpty ? packageName : null,
    );
    if (!mounted) return;
    if (success) {
      showToast(context.trLegacy('任务已启动'), type: ToastType.success);
    } else {
      showToast(context.trLegacy('启动失败'), type: ToastType.error);
    }
  }

  Future<void> _onSchedulePressed(ExecutionRecordListItemData record) async {
    if (record.suggestionData == null) {
      showToast('当前记录不支持定时', type: ToastType.error);
      return;
    }

    final existingTask =
        await ScheduledTaskStorageService.getScheduledTaskBySuggestionId(
          record.nodeId,
          record.suggestionId,
        );
    if (!mounted) {
      return;
    }

    final result = await ScheduleTaskSheet.show(
      context: context,
      taskTitle: record.title,
      packageName: record.packageName,
      nodeId: record.nodeId,
      suggestionId: record.suggestionId,
      suggestionData: record.suggestionData,
      existingTask: existingTask,
    );

    if (result == null) {
      return;
    }

    await ScheduledTaskStorageService.addScheduledTask(result);
    ScheduledTaskSchedulerService.scheduleTask(result);
    await _loadScheduledTaskKeys();
    if (mounted) {
      showToast('定时任务已设置', type: ToastType.success);
    }
  }

  /// 点击执行记录，展示详情
  void _onRecordTap(ExecutionRecordListItemData vm) {
    _showRunLogDetail(vm);
  }

  /// 展示 run log 详情弹窗
  void _showRunLogDetail(ExecutionRecordListItemData vm) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: isDark ? palette.surfacePrimary : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部拖动条
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? palette.borderSubtle : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        vm.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: palette.textSecondary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? palette.borderSubtle : Colors.grey[200],
              ),
              // 详情内容
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('执行次数', '${vm.times} 次'),
                      _buildDetailRow('最近执行', vm.lastExecutionTimeLabel),
                      if (vm.packageName.isNotEmpty)
                        _buildDetailRow('应用包名', vm.packageName),
                      if (vm.runId != null && vm.runId!.isNotEmpty)
                        _buildDetailRow('Run ID', vm.runId!),
                      const SizedBox(height: 24),
                      // 操作按钮
                      Row(
                        children: [
                          if (vm.isExecutable)
                            Expanded(
                              child: _buildActionButton(
                                icon: Icons.play_arrow_rounded,
                                label: '执行',
                                onTap: () {
                                  Navigator.pop(context);
                                  vm.onExecute?.call();
                                },
                              ),
                            ),
                          if (vm.isExecutable && vm.isReplayable)
                            const SizedBox(width: 12),
                          if (vm.isReplayable)
                            Expanded(
                              child: _buildActionButton(
                                icon: Icons.replay_rounded,
                                label: '重放',
                                onTap: () {
                                  Navigator.pop(context);
                                  vm.onReplay?.call();
                                },
                              ),
                            ),
                        ],
                      ),
                      if (vm.isSchedulable) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _buildActionButton(
                            icon: Icons.schedule_rounded,
                            label: '设置定时任务',
                            onTap: () {
                              Navigator.pop(context);
                              _onSchedulePressed(vm);
                            },
                          ),
                        ),
                      ],
                      // 记忆按钮（保存为可复用技能）
                      if (vm.runId != null && vm.runId!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _buildActionButton(
                            icon: Icons.save_alt_rounded,
                            label: '保存为技能',
                            onTap: () {
                              Navigator.pop(context);
                              _saveAsSkill(vm);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? palette.textSecondary : Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 保存为技能（调用 import_run_log API）
  Future<void> _saveAsSkill(ExecutionRecordListItemData vm) async {
    if (vm.runId == null || vm.runId!.isEmpty) {
      showToast('缺少 Run ID，无法保存', type: ToastType.error);
      return;
    }

    try {
      // TODO: 调用 Provider 的 /run_logs/import_run_log API
      // final config = await AssistsMessageService.getUtgBridgeConfig();
      // final result = await AssistsMessageService.importRunLogAsFunction(
      //   runId: vm.runId!,
      //   baseUrl: config.resolvedOmniflowBaseUrl,
      // );

      showToast('保存技能功能开发中...', type: ToastType.info);
    } catch (e) {
      if (!mounted) return;
      showToast('保存失败：$e', type: ToastType.error);
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;
    return Material(
      color: isDark ? palette.surfaceSecondary : Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: palette.accentPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: palette.accentPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按进入选择模式
  void _enterSelectionMode(ExecutionRecordListItemData vm) {
    final key = _getRecordKey(vm);
    setState(() {
      _isSelectionMode = true;
      _selectedRecordKeys.add(key);
    });
  }

  /// 生成记录唯一标识（使用 nodeId+suggestionId）
  String _getRecordKey(ExecutionRecordListItemData vm) {
    return '${vm.nodeId}|${vm.suggestionId}';
  }

  /// 切换记录选中状态
  void _toggleRecordSelection(ExecutionRecordListItemData vm) {
    final key = _getRecordKey(vm);
    setState(() {
      if (_selectedRecordKeys.contains(key)) {
        _selectedRecordKeys.remove(key);
      } else {
        _selectedRecordKeys.add(key);
      }
    });
  }

  /// 退出选择模式
  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedRecordKeys.clear();
    });
  }

  /// 全选/全不选
  void _toggleSelectAll(List<ExecutionRecordListItemData> records) {
    setState(() {
      if (_selectedRecordKeys.length == records.length) {
        // 已全选，取消全选
        _selectedRecordKeys.clear();
      } else {
        // 未全选，全选
        _selectedRecordKeys = records.map((r) => _getRecordKey(r)).toSet();
      }
    });
  }

  /// 批量删除选中的记录（从视图中移除）
  Future<void> _batchDeleteSelectedRecords() async {
    final count = _selectedRecordKeys.length;
    if (count == 0) return;

    // 显示底部确认弹窗
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          BatchDeleteConfirmSheet(count: count, unit: ' ${context.l10n.trajectoryTaskRecords}'),
    );

    if (result == true) {
      // 从视图中移除选中的记录
      setState(() {
        executionRecordViewModels.removeWhere(
          (record) => _selectedRecordKeys.contains(_getRecordKey(record)),
        );
      });

      // 退出选择模式
      _exitSelectionMode();

      // 重建标签
      _buildExecutionRecords();

      showToast(context.l10n.skillDeleted, type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final allRecords = executionRecordViewModels;

    final filterRecords =
        (selectedTagIds.contains('all')) || selectedTagIds.isEmpty
        ? allRecords
        : allRecords.where((record) {
            return selectedTagIds.contains(record.packageName);
          }).toList();

    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : AppColors.background,
      appBar: _isSelectionMode
          ? _buildSelectionAppBar(filterRecords)
          : CommonAppBar(title: context.l10n.trajectoryTitle, showAiBadge: false, primary: true),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? _buildLoadingIndicator()
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          // 选择模式下模糊顶部区域
                          ImageFiltered(
                            imageFilter: _isSelectionMode
                                ? ImageFilter.blur(sigmaX: 10, sigmaY: 10)
                                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                            child: Column(
                              children: [
                                SizedBox(height: 14),
                                const ActivityDashboardCard(),
                                SizedBox(height: 12),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '任务记录',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: context.omniPalette.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TagSection(
                              items: executionTags,
                              selectedIds: selectedTagIds,
                              onSelectionChanged: _onTagSelectionChanged,
                              maxCollapsedRows: 1,
                            ),
                          ),
                          if (allRecords.isNotEmpty) ...[
                            SizedBox(height: 8),
                            ExecutionRecordList(
                              records: filterRecords,
                              onLongPress: (vm) => _enterSelectionMode(vm),
                              onTap: (vm) => _onRecordTap(vm),
                              isSelectionMode: _isSelectionMode,
                              selectedKeys: _selectedRecordKeys,
                              onToggleSelection: _toggleRecordSelection,
                              getRecordKey: _getRecordKey,
                              onSchedulePressed: _onSchedulePressed,
                              scheduledTaskKeys: _scheduledTaskKeys,
                              onReplayPressed: (vm) => vm.onReplay?.call(),
                            ),
                          ] else
                            _buildEmptyRecordsHint(),
                        ],
                      ),
                    ),
            ),
            // 选择模式下的底部删除按钮栏
            SelectionBottomBar(
              isActive: _isSelectionMode,
              onDeletePressed: _selectedRecordKeys.isNotEmpty
                  ? _batchDeleteSelectedRecords
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // 选择模式下的 AppBar
  PreferredSizeWidget _buildSelectionAppBar(
    List<ExecutionRecordListItemData> filterRecords,
  ) {
    final palette = context.omniPalette;
    final isAllSelected =
        _selectedRecordKeys.length == filterRecords.length &&
        filterRecords.isNotEmpty;
    return CommonAppBar(
      primary: true,
      title: context.l10n.trajectorySelectedCount(_selectedRecordKeys.length),
      titleStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        fontFamily: 'SF Pro',
      ),
      leadingWidth: 64,
      leading: TextButton(
        onPressed: _exitSelectionMode,
        child: Text(
          context.trLegacy('取消'),
          style: TextStyle(
            color: palette.accentPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: 72,
          child: TextButton(
            onPressed: () => _toggleSelectAll(filterRecords),
            child: Text(
              isAllSelected ? context.l10n.memoryDeselectAll : context.trLegacy('全选'),
              style: TextStyle(
                color: palette.accentPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyRecordsHint() {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          SvgPicture.asset(
            'assets/common/empty_record.svg',
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => Icon(
              Icons.favorite_border,
              size: 72,
              color: context.isDarkTheme
                  ? palette.borderStrong
                  : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 12),
          
          Text(
            context.l10n.trajectoryNoRecordsDesc,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTextStyles.fontSizeMain,
              fontWeight: AppTextStyles.fontWeightRegular,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : AppColors.text20,
              height: AppTextStyles.lineHeightH2,
              letterSpacing: AppTextStyles.letterSpacingWide,
            ),
          ),
        ],
      ),
    );
  }

  String _getSection(int timestamp) {
    String section = context.l10n.trajectoryUnknownDate;
    final today = DateTime.now();
    final recordDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (recordDate.year == today.year &&
        recordDate.month == today.month &&
        recordDate.day == today.day) {
      section = context.trLegacy('今天');
    } else if (recordDate.year == today.year &&
        recordDate.month == today.month &&
        recordDate.day == today.day - 1) {
      section = context.trLegacy('昨天');
    } else {
      section = context.l10n.trajectoryThreeDaysAgo;
    }
    return section;
  }

  String _getTimeLabel(String section, int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final today = DateTime.now();

    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return '${context.trLegacy('今天')} ' + DateFormat('HH:mm').format(date);
    } else if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day - 1) {
      return '${context.trLegacy('昨天')} ' + DateFormat('HH:mm').format(date);
    } else {
      return DateFormat('yyyy/MM/dd HH:mm').format(date);
    }
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

}
