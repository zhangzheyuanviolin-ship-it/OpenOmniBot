import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ui/core/mixins/page_lifecycle_mixin.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/memory/pages/memory_center/widgets/tag_section.dart';
import 'package:ui/features/my/pages/my/widgets/memory_section.dart';
import 'package:ui/features/task/pages/execution_history/task_execution_detail_page.dart';
import 'package:ui/features/task/pages/scheduled_tasks/widgets/schedule_task_sheet.dart';
import 'package:ui/models/task_execution_info.dart';
import 'package:ui/models/title_count.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/scheduled_task_scheduler_service.dart';
import 'package:ui/services/scheduled_task_storage_service.dart';
import 'package:ui/utils/cache_util.dart';
import 'package:ui/utils/image_util.dart';
import 'package:ui/features/task/pages/execution_history/widgets/execution_record_list_item.dart';
import 'package:intl/intl.dart';

import 'package:ui/models/execution_record.dart';
import 'package:ui/widgets/context_menu.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/features/memory/pages/memory_center/widgets/batch_delete_confirm_sheet.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/features/task/pages/execution_history/widgets/execution_record_list.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/image/cached_image.dart';
import 'package:ui/widgets/selection_bottom_bar.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/features/memory/pages/memory_center/widgets/conversation_heatmap.dart';

/// 执行总结的前三条记录ID存储key
const String kExecutionSummaryTopThreeIdsKey =
    'execution_summary_top_three_ids';

/// 执行总结的存储key
const String kExecutionSummaryKey = 'execution_summary';

class TaskExecutionHistoryRecordPage extends StatefulWidget {
  const TaskExecutionHistoryRecordPage({super.key});

  @override
  State<TaskExecutionHistoryRecordPage> createState() =>
      _TaskExecutionHistoryRecordPageState();
}

class _TaskExecutionHistoryRecordPageState
    extends State<TaskExecutionHistoryRecordPage>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        PageLifecycleMixin<TaskExecutionHistoryRecordPage> {
  List<AppTag> executionTags = [];

  List<TaskExecutionInfo> taskExecutionInfos = [];

  List<ExecutionRecordListItemData> executionRecordViewModels = [];

  MemorySummary? memorySummary;

  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  Set<String> selectedTagIds = {'all'};

  // 选择模式状态
  bool _isSelectionMode = false;
  Set<String> _selectedRecordKeys = {}; // 使用 title+packageName 作为唯一标识

  // Suggestion 缓存，key 为 nodeId|suggestionId（用于执行任务）
  Map<String, Map<String, dynamic>> _suggestionMap = {};
  Set<String> _scheduledTaskKeys = {};

  // LLM 生成的执行总结
  bool _isSummaryLoading = false;
  late AnimationController _shimmerController;
  // 用于跟踪上次生成总结时的前三条执行记录ID
  List<String> _lastTopThreeExecutionIds = [];

  @override
  void initState() {
    super.initState();

    // 初始化shimmer动画控制器
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _loadData();
    _loadMemorySummary();
    _loadScheduledTaskKeys();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  // ✅ 应用从后台回到前台时刷新
  @override
  void onPageResumed() {
    if (_hasLoadedOnce) {
      print('✅ ExecutionRecordPage resumed - reloading data silently');
      _loadData(silent: true);
      _loadMemorySummary();
      _loadScheduledTaskKeys();
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

  // 从数据库加载数据
  /// [silent] 是否静默刷新（不显示loading）
  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      await Future.wait([_loadSuggestionMap(), _loadTaskExecutionInfos()]);
      await _loadExecutionTags();

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

  /// 加载 Suggestion 数据并缓存到 _suggestionMap
  Future<void> _loadSuggestionMap() async {
    // 开源版仅保留 VLM 回放能力。
    _suggestionMap = {};
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

  /// 生成 Suggestion key（与执行记录匹配）
  String _getSuggestionKey(String nodeId, String suggestionId) {
    return '$nodeId|$suggestionId';
  }

  Future<void> _loadMemorySummary() async {
    try {
      final executionCount = await CacheUtil.getExecutionRecordCountByTitle();
      if (executionCount.isEmpty) {
        if (mounted) {
          setState(() {
            memorySummary = null;
          });
        }
        return;
      }
      // 将数据降序排列
      executionCount.sort((a, b) => b.count.compareTo(a.count));

      // 构建 tips 字符串,取前三多的title
      String tips = executionCount
          .take(3)
          .map((item) => '· ${item.title} ${item.count} 次')
          .join('\n');

      final totalCount = executionCount.fold<int>(
        0,
        (sum, item) => sum + item.count,
      );
      final title = '本月共执行 $totalCount 件事，你可以在这查看';

      setState(() {
        memorySummary = MemorySummary(title: title, tips: tips, sum: '');
      });

      // 先加载持久化的总结
      String? savedSummary;
      try {
        savedSummary = StorageService.getString(kExecutionSummaryKey);
        print('加载持久化的执行总结: $savedSummary');
      } catch (e) {
        print('加载执行总结失败: $e');
      }

      // 检查前三条记录是否变化，只在变化时生成总结
      final currentTopThreeIds = executionCount
          .take(3)
          .map((item) => '${item.title}_${item.count}')
          .toList();

      // 加载持久化的前三条记录ID
      await _loadLastTopThreeExecutionIds();

      final hasChanged = _hasTopThreeExecutionChanged(currentTopThreeIds);

      if (hasChanged) {
        _lastTopThreeExecutionIds = currentTopThreeIds;
        // 保存到持久化存储
        _saveLastTopThreeExecutionIds(currentTopThreeIds);
        // 异步生成执行总结
        _generateExecutionSummary(executionCount, title, tips);
      } else {
        // 如果没有持久化数据，使用默认总结
        if (savedSummary == null) {
          setState(() {
            memorySummary = MemorySummary(
              title: title,
              tips: tips,
              sum: '本月你是一个惜时如金的天命人~',
            );
          });
        } else {
          setState(() {
            memorySummary = MemorySummary(
              title: title,
              tips: tips,
              sum: savedSummary!,
            );
          });
        }
      }
    } catch (e) {
      print('Error loading memory summary: $e');
    }
  }

  /// 从持久化存储加载上次的前三条执行记录ID
  Future<void> _loadLastTopThreeExecutionIds() async {
    try {
      final savedIds = StorageService.getJson<List<dynamic>>(
        kExecutionSummaryTopThreeIdsKey,
      );
      if (savedIds != null && savedIds.isNotEmpty) {
        _lastTopThreeExecutionIds = savedIds.map((id) => id as String).toList();
        print('加载持久化的前三条执行记录ID: $_lastTopThreeExecutionIds');
      }
    } catch (e) {
      print('加载前三条执行记录ID失败: $e');
    }
  }

  /// 保存前三条执行记录ID到持久化存储
  Future<void> _saveLastTopThreeExecutionIds(List<String> ids) async {
    try {
      await StorageService.setJson(kExecutionSummaryTopThreeIdsKey, ids);
      print('保存前三条执行记录ID到持久化存储: $ids');
    } catch (e) {
      print('保存前三条执行记录ID失败: $e');
    }
  }

  /// 检查前三条执行记录是否变化
  bool _hasTopThreeExecutionChanged(List<String> currentTopThreeIds) {
    // 如果是第一次加载（_lastTopThreeExecutionIds为空），返回true
    if (_lastTopThreeExecutionIds.isEmpty) {
      return true;
    }

    // 如果数量不同，说明有变化
    if (currentTopThreeIds.length != _lastTopThreeExecutionIds.length) {
      return true;
    }

    // 逐个比较ID，如果有任何不同则返回true
    for (int i = 0; i < currentTopThreeIds.length; i++) {
      if (currentTopThreeIds[i] != _lastTopThreeExecutionIds[i]) {
        return true;
      }
    }

    // 完全相同，无需更新
    return false;
  }

  /// 使用 LLM 生成执行总结
  Future<void> _generateExecutionSummary(
    List<TitleCount> executionCount,
    String title,
    String tips,
  ) async {
    // 显示加载状态
    setState(() {
      _isSummaryLoading = true;
    });
    // 如果没有执行记录，不生成总结
    if (executionCount.isEmpty) {
      return;
    }

    try {
      // 取前三条执行记录
      final topRecords = executionCount
          .take(3)
          .map((item) => {'title': item.title, 'count': item.count})
          .toList();

      const prompt = '''你是小万，一个温暖的AI助手。根据用户本月的任务执行记录，生成一句简短、温馨的总结语。

要求：
1. 总结语要简短（不超过30个字）
2. 结合用户执行任务的特点，体现个性化
3. 语气温暖友好、鼓励积极
4. 可以适当幽默风趣
5. 只输出总结语本身，不要加引号或其他说明

用户的执行记录：
''';

      final recordsJson = topRecords
          .map((r) => '任务: ${r['title']}, 执行次数: ${r['count']}')
          .join('\n');

      final response = await AssistsMessageService.postLLMChat(
        text: prompt + recordsJson,
        model: 'scene.compactor.context',
      );

      if (response != null && response.isNotEmpty && mounted) {
        final summaryText = response.trim();
        setState(() {
          memorySummary = MemorySummary(
            title: title,
            tips: tips,
            sum: summaryText,
          );
          _isSummaryLoading = false;
        });
        // 保存到持久化存储
        StorageService.setString(kExecutionSummaryKey, summaryText);
      } else {
        setState(() {
          _isSummaryLoading = false;
        });
      }
    } catch (e) {
      print('生成执行总结失败: $e');
      setState(() {
        _isSummaryLoading = false;
      });
    }
  }

  // 加载执行记录信息
  Future<void> _loadTaskExecutionInfos() async {
    try {
      final records = await CacheUtil.getTaskExecutionInfos();

      setState(() {
        taskExecutionInfos = records;
      });
    } catch (e) {
      print('Error loading execution records: $e');
    }
  }

  // 加载执行记录标签数据 TODO 优化抽取函数
  Future<void> _loadExecutionTags() async {
    try {
      // 1) 先构建 tagList 数据源
      final tagList = <AppTag>[];
      final totalCount = taskExecutionInfos.length;
      tagList.add(
        AppTag(
          id: 'all',
          label: '全部',
          count: totalCount,
          svgPath: 'assets/common/all_icon.svg',
          iconBgColor: Colors.black,
          iconColor: Colors.white,
        ),
      );

      // 收集需要获取图标的 packageName
      final packageNames = <String>{};
      //将taskexecutioninfos按packagename分组，统计数量，并加入到packagenames中
      for (final info in taskExecutionInfos) {
        final appName = info.appName;
        final packageName = info.packageName;

        if (packageName.isNotEmpty && !packageNames.contains(packageName)) {
          packageNames.add(packageName);
          tagList.add(
            AppTag(
              id: packageName,
              label: appName,
              count: taskExecutionInfos
                  .where((e) => e.packageName == packageName)
                  .length,
              icon: Icons.apps,
              iconBgColor: const Color(0xFFE6F0FE),
              appIconProvider: null,
            ),
          );
        }
      }

      // 2) 批量获取图标
      Map<String, ImageProvider?> iconProv = {};
      if (mounted) {
        iconProv = await ImageUtil.batchLoadAppIcons(packageNames, context);
      } else {
        iconProv = {};
      }

      // 3) 将图标数据填回 tagList 的 appIconProvider（避免再次 setState）
      final tagListWithIcons = tagList.map((t) {
        if (t.appIconProvider == null && iconProv.containsKey(t.id)) {
          return AppTag(
            id: t.id,
            label: t.label,
            count: t.count,
            icon: t.icon,
            iconBgColor: t.iconBgColor,
            iconColor: t.iconColor,
            appIconProvider: iconProv[t.id],
          );
        }
        return t;
      }).toList();

      // 4) 将图标数据填回 executionRecordViewModels 的 icons（避免再次 setState）
      final defaultIcon = Builder(
        builder: (context) {
          final palette = context.omniPalette;
          return Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: context.isDarkTheme
                  ? palette.surfaceElevated
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
              border: context.isDarkTheme
                  ? Border.all(color: palette.borderSubtle)
                  : null,
            ),
            child: Icon(
              Icons.apps,
              size: 16,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : Colors.grey[600],
            ),
          );
        },
      );

      final modelsWithIcons = taskExecutionInfos.map((info) {
        final section = _getSection(info.lastExecutionTime);
        final iconsList = <Widget>[];

        // 1. 添加 App 图标
        if (iconProv.containsKey(info.packageName)) {
          iconsList.add(
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image(
                image: iconProv[info.packageName]!,
                width: 20,
                height: 20,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  final palette = context.omniPalette;
                  return Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: context.isDarkTheme
                          ? palette.surfaceElevated
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                      border: context.isDarkTheme
                          ? Border.all(color: palette.borderSubtle)
                          : null,
                    ),
                    child: Icon(
                      Icons.apps,
                      size: 16,
                      color: context.isDarkTheme
                          ? palette.textSecondary
                          : Colors.grey[600],
                    ),
                  );
                },
              ),
            ),
          );
        } else {
          iconsList.add(defaultIcon);
        }

        // 2. 添加技能类型图标（suggestion iconUrl 或默认类型图标）
        print(
          'Adding type icon for ${info.title} with iconUrl: ${info.iconUrl}',
        );
        print('ExecutionRecordType: ${info.type}');
        iconsList.add(_buildTypeIcon(info.type, info.iconUrl));

        // 3. 判断是否可执行（参照 SkillGridItem 的判断逻辑）
        final suggestionKey = _getSuggestionKey(info.nodeId, info.suggestionId);
        final suggestionData =
            _suggestionMap[suggestionKey] ?? _buildVlmSuggestionData(info);
        final isExecutable = suggestionData != null
            ? _isExecutable(suggestionData, info.type)
            : false;
        final isSchedulable = suggestionData != null
            ? _isSchedulable(suggestionData, info.type, isExecutable)
            : false;

        return ExecutionRecordListItemData(
          id: info.id,
          title: info.title,
          packageName: info.packageName,
          nodeId: info.nodeId,
          suggestionId: info.suggestionId,
          times: info.count,
          section: section,
          lastExecutionTimeLabel: _getTimeLabel(
            section,
            info.lastExecutionTime,
          ),
          icons: iconsList,
          isExecutable: isExecutable,
          isSchedulable: isSchedulable,
          suggestionData: suggestionData,
          onExecute: isExecutable
              ? () => _executeTask(info, suggestionData)
              : null,
        );
      }).toList();

      setState(() {
        executionTags = tagListWithIcons;
        executionRecordViewModels = modelsWithIcons;
      });
    } catch (e) {
      print('Error loading execution tags: $e');
    }
  }

  bool _isExecutable(
    Map<String, dynamic> suggestionData,
    ExecutionRecordType type,
  ) {
    final isAppInstalled = suggestionData['isInstalled'] as bool? ?? false;
    final isHomeTask = suggestionData['isHomeTask'] as bool? ?? false;
    final requireChatbotTrigger =
        suggestionData['triggerType'] == 'require_chatbot_trigger';

    // 检测 tasks 中的 slots 是否为空，判断是否需要额外信息
    bool needsExtraInfo = false;
    final tasks = suggestionData['tasks'];
    if (tasks != null && tasks is List && tasks.isNotEmpty) {
      for (final task in tasks) {
        final slots = task['slots'];
        if (slots != null && slots is List && slots.isNotEmpty) {
          needsExtraInfo = true;
          break;
        }
      }
    }

    // 任务可执行的条件（与 SkillGridItem 一致）：
    // 1. 不是学习任务
    // 2. 应用已安装
    // 3. 是首页任务
    // 4. 不需要 chatbot 触发
    // 5. 不需要额外信息
    return isAppInstalled &&
        isHomeTask &&
        !requireChatbotTrigger &&
        !needsExtraInfo;
  }

  Map<String, dynamic>? _buildVlmSuggestionData(TaskExecutionInfo info) {
    if (info.type != ExecutionRecordType.vlm) {
      return null;
    }
    final goal = info.suggestionId.trim().isNotEmpty
        ? info.suggestionId.trim()
        : info.title.trim();
    if (goal.isEmpty) {
      return null;
    }
    return {
      'goal': goal,
      'packageName': info.packageName,
      'nodeId': info.nodeId,
      'suggestionId': info.suggestionId,
    };
  }

  bool _isSchedulable(
    Map<String, dynamic> suggestionData,
    ExecutionRecordType type,
    bool isExecutable,
  ) {
    if (type == ExecutionRecordType.vlm) {
      final goal = (suggestionData['goal'] as String?)?.trim() ?? '';
      return goal.isNotEmpty;
    }
    return isExecutable;
  }

  /// 执行任务
  Future<void> _executeTask(
    TaskExecutionInfo info,
    Map<String, dynamic> suggestionData,
  ) async {
    final goal = (suggestionData['goal'] as String?)?.trim() ?? '';
    if (goal.isEmpty) {
      showToast('当前记录不支持执行', type: ToastType.error);
      return;
    }

    final success = await AssistsMessageService.createVLMOperationTask(
      goal,
      packageName: info.packageName,
    );
    if (!mounted) return;
    if (success) {
      showToast('任务开始执行', type: ToastType.success);
    } else {
      showToast('任务执行失败', type: ToastType.error);
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

  /// 构建类型图标（优先使用 icon URL，否则使用类型默认图标）
  Widget _buildTypeIcon(ExecutionRecordType type, String? iconUrl) {
    const double iconSize = 20.0;

    // 如果有 icon URL，优先显示网络图标
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return CachedImage(
        imageUrl: iconUrl,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.cover,
        errorWidget: _buildDefaultTypeIcon(type, iconSize),
      );
    }

    // 没有 icon URL 时使用默认类型图标
    return _buildDefaultTypeIcon(type, iconSize);
  }

  /// 构建默认类型图标（SVG）
  Widget _buildDefaultTypeIcon(ExecutionRecordType type, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(type.defaultIconColor),
        borderRadius: BorderRadius.circular(2),
      ),
      padding: const EdgeInsets.all(2),
      child: type.defaultIconPath.isEmpty
          ? SizedBox.shrink()
          : SvgPicture.asset(
              type.defaultIconPath,
              width: size - 4,
              height: size - 4,
            ),
    );
  }

  void _showContextMenu(
    ExecutionRecordListItemData vm,
    BuildContext context,
    Offset position,
  ) async {
    final action = await showRecordContextMenu(
      context: context,
      position: position,
    );
    switch (action) {
      // case RecordMenuAction.edit:
      //   _editRecord(vm.title, vm.id);
      //   break;
      case RecordMenuAction.delete:
        _deleteExecutionRecord(vm.id);
        break;
      default:
        break;
    }
  }

  /// 点击执行记录，跳转到详情页
  void _navigateToDetail(ExecutionRecordListItemData vm) {
    // 查找对应的 TaskExecutionInfo
    final info = taskExecutionInfos.firstWhere(
      (e) => e.nodeId == vm.nodeId && e.suggestionId == vm.suggestionId,
      orElse: () => TaskExecutionInfo(
        id: vm.id,
        appName: '',
        packageName: vm.packageName,
        title: vm.title,
        nodeId: vm.nodeId,
        suggestionId: vm.suggestionId,
        count: vm.times,
        lastExecutionTime: 0,
      ),
    );

    final params = TaskExecutionDetailParams(
      title: vm.title,
      packageName: vm.packageName,
      appName: info.appName,
      nodeId: vm.nodeId,
      suggestionId: vm.suggestionId,
      totalCount: vm.times,
      lastExecutionTime: info.lastExecutionTime,
      type: info.type,
      iconUrl: info.iconUrl,
      content: info.content,
    );

    GoRouterManager.push('/task/execution_detail', extra: params.toMap());
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

  /// 批量删除选中的记录
  Future<void> _batchDeleteSelectedRecords() async {
    final count = _selectedRecordKeys.length;
    if (count == 0) return;

    // 显示底部确认弹窗
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          BatchDeleteConfirmSheet(count: count, unit: ' 任务记录'),
    );

    if (result == true) {
      // 执行批量删除
      int successCount = 0;
      for (final key in _selectedRecordKeys.toList()) {
        final parts = key.split('|');
        if (parts.length == 2) {
          final nodeId = parts[0];
          final suggestionId = parts[1];
          final success = await _performBatchDeleteByNodeAndSuggestionId(
            nodeId,
            suggestionId,
          );
          if (success) {
            successCount++;
          }
        }
      }

      // 退出选择模式
      _exitSelectionMode();

      // 重新加载标签统计
      await _loadExecutionTags();
      _loadMemorySummary();

      // 显示删除结果
      if (successCount > 0) {
        showToast('已删除', type: ToastType.success);
      }
    }
  }

  /// 执行单条批量删除（不显示弹窗，使用 nodeId+suggestionId）
  Future<bool> _performBatchDeleteByNodeAndSuggestionId(
    String nodeId,
    String suggestionId,
  ) async {
    try {
      bool success = await CacheUtil.deleteExecutionRecordByNodeAndSuggestionId(
        nodeId,
        suggestionId,
      );
      if (success) {
        // 从本地列表中删除匹配的记录
        setState(() {
          taskExecutionInfos.removeWhere(
            (record) =>
                record.nodeId == nodeId && record.suggestionId == suggestionId,
          );
        });
      }
      return success;
    } catch (e) {
      print('Error deleting task records: $e');
      return false;
    }
  }

  // 删除执行记录（单条）
  void _deleteExecutionRecord(int recordId) {
    AppDialog.confirm(
      context,
      title: '确定删除吗？',
      content: '删除后该内容将不可找回',
      cancelText: '取消',
      confirmText: '删除',
      confirmButtonColor: AppColors.alertRed,
    ).then((result) async {
      if (result == true) {
        await _performExecutionDelete(recordId);
      }
    });
  }

  // 执行删除操作（单条）
  Future<void> _performExecutionDelete(int recordId) async {
    try {
      bool success = await CacheUtil.deleteExecutionRecordById(recordId);
      if (!success) {
        showToast('删除失败', type: ToastType.error);
        return;
      }

      // 从本地列表中删除
      setState(() {
        taskExecutionInfos.removeWhere((record) => record.id == recordId);
      });

      showToast('删除成功', type: ToastType.success);

      // 重新加载标签统计
      await _loadExecutionTags();
      _loadMemorySummary();
    } catch (e) {
      print('Error deleting card: $e');
      showToast('删除失败', type: ToastType.error);
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
          : const CommonAppBar(title: '轨迹', showAiBadge: true, primary: true),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? _buildLoadingIndicator()
                  : allRecords.isEmpty
                  ? _buildEmptyState()
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
                                const ConversationHeatmap(),
                                SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: MemorySection(
                                    memorySummary: memorySummary,
                                    isSummaryLoading: _isSummaryLoading,
                                    animationController: _shimmerController,
                                  ),
                                ),
                                SizedBox(height: 12),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TagSection(
                              items: executionTags,
                              selectedIds: selectedTagIds,
                              onSelectionChanged: _onTagSelectionChanged,
                              maxCollapsedRows: 1,
                            ),
                          ),
                          SizedBox(height: 8),
                          ExecutionRecordList(
                            records: filterRecords,
                            onDelete: _deleteExecutionRecord,
                            onMore: _showContextMenu,
                            onLongPress: (vm) => _enterSelectionMode(vm),
                            onTap: (vm) => _navigateToDetail(vm),
                            isSelectionMode: _isSelectionMode,
                            selectedKeys: _selectedRecordKeys,
                            onToggleSelection: _toggleRecordSelection,
                            getRecordKey: _getRecordKey,
                            onSchedulePressed: _onSchedulePressed,
                            scheduledTaskKeys: _scheduledTaskKeys,
                          ),
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
      title: '已选择${_selectedRecordKeys.length}项',
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
          '取消',
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
              isAllSelected ? '全不选' : '全选',
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

  Widget _buildEmptyState() {
    final palette = context.omniPalette;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
            '暂无执行记录',
            style: TextStyle(
              fontSize: AppTextStyles.fontSizeH3,
              fontWeight: AppTextStyles.fontWeightMedium,
              color: context.isDarkTheme
                  ? palette.textPrimary
                  : AppColors.primaryBlue,
              height: AppTextStyles.lineHeightH1,
              letterSpacing: AppTextStyles.letterSpacingWide,
            ),
          ),
          const SizedBox(height: 9),
          Container(
            alignment: Alignment.center,
            width: 192,
            child: Text(
              '小万为你执行的任务，后续都会在此展示',
              textAlign: TextAlign.center,
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
          ),
        ],
      ),
    );
  }

  String _getSection(int timestamp) {
    String section = '未知日期';
    final today = DateTime.now();
    final recordDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (recordDate.year == today.year &&
        recordDate.month == today.month &&
        recordDate.day == today.day) {
      section = '今天';
    } else if (recordDate.year == today.year &&
        recordDate.month == today.month &&
        recordDate.day == today.day - 1) {
      section = '昨天';
    } else {
      section = '三天前';
    }
    return section;
  }

  String _getTimeLabel(String section, int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

    if (section == '今天') {
      return '今天 ' + DateFormat('HH:mm').format(date);
    } else if (section == '昨天') {
      return '昨天 ' + DateFormat('HH:mm').format(date);
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
