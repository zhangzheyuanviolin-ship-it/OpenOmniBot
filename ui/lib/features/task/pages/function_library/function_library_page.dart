import 'package:flutter/material.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/core/mixins/page_lifecycle_mixin.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class FunctionLibraryPage extends StatefulWidget {
  const FunctionLibraryPage({super.key});

  @override
  State<FunctionLibraryPage> createState() => _FunctionLibraryPageState();
}

class _FunctionLibraryPageState extends State<FunctionLibraryPage>
    with WidgetsBindingObserver, PageLifecycleMixin<FunctionLibraryPage> {
  List<UtgFunctionSummary> _functions = [];
  List<UtgFunctionSummary> _filteredFunctions = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  String _searchQuery = '';
  String _selectedApp = ''; // 空字符串表示全部
  Set<String> _availableApps = {};
  String? _expandedFunctionId;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void onPageResumed() {
    if (_hasLoadedOnce) {
      _loadData(silent: true);
    }
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      if (!mounted) return;

      final snapshot = await AssistsMessageService.getUtgFunctions(
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;

      setState(() {
        _functions = snapshot.functions;
        _availableApps = _functions
            .map((f) => f.appName.isNotEmpty ? f.appName : f.groupName)
            .where((name) => name.isNotEmpty)
            .toSet();
        _applyFilters();
        _isLoading = false;
      });
      _hasLoadedOnce = true;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (!silent) {
        showToast('${context.l10n.omniflowFunctionsLoadFailed}: $e',
            type: ToastType.error);
      }
    }
  }

  void _applyFilters() {
    _filteredFunctions = _functions.where((f) {
      // 搜索过滤
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesSearch = f.description.toLowerCase().contains(query) ||
            f.functionId.toLowerCase().contains(query) ||
            f.appName.toLowerCase().contains(query);
        if (!matchesSearch) return false;
      }

      // 应用过滤
      if (_selectedApp.isNotEmpty) {
        final appName = f.appName.isNotEmpty ? f.appName : f.groupName;
        if (appName != _selectedApp) return false;
      }

      return true;
    }).toList();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _onAppFilterChanged(String? app) {
    setState(() {
      _selectedApp = app ?? '';
      _applyFilters();
    });
  }

  Future<void> _deleteFunction(UtgFunctionSummary func) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.functionLibraryDeleteTitle),
        content: Text(context.l10n.functionLibraryDeleteConfirm(func.description)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.omniflowCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.functionLibraryDelete,
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      await AssistsMessageService.deleteUtgFunction(
        functionId: func.functionId,
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      showToast(context.l10n.functionLibraryDeleted, type: ToastType.success);
      _loadData(silent: true);
    } catch (e) {
      if (!mounted) return;
      showToast('${context.l10n.functionLibraryDeleteFailed}: $e', type: ToastType.error);
    }
  }

  Future<void> _uploadFunction(UtgFunctionSummary func) async {
    final cloudUrl = await _showCloudUrlDialog(
      title: context.l10n.functionLibraryUploadTitle,
      hint: func.cloudBaseUrl,
    );
    if (cloudUrl == null || cloudUrl.isEmpty) return;

    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      final result = await AssistsMessageService.uploadCloudUtgFunction(
        functionId: func.functionId,
        cloudBaseUrl: cloudUrl,
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      if (result.success) {
        showToast(context.l10n.functionLibraryUploadSuccess, type: ToastType.success);
        _loadData(silent: true);
      } else {
        showToast(result.errorMessage ?? context.l10n.functionLibraryUploadFailed,
            type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      showToast('${context.l10n.functionLibraryUploadFailed}: $e', type: ToastType.error);
    }
  }

  Future<void> _showDownloadDialog() async {
    final cloudUrl = await _showCloudUrlDialog(
      title: context.l10n.functionLibraryDownloadTitle,
    );
    if (cloudUrl == null || cloudUrl.isEmpty) return;

    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      final result = await AssistsMessageService.downloadCloudUtgFunction(
        cloudBaseUrl: cloudUrl,
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      if (result.success) {
        showToast(context.l10n.functionLibraryDownloadSuccess, type: ToastType.success);
        _loadData(silent: true);
      } else {
        showToast(result.errorMessage ?? context.l10n.functionLibraryDownloadFailed,
            type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      showToast('${context.l10n.functionLibraryDownloadFailed}: $e', type: ToastType.error);
    }
  }

  Future<String?> _showCloudUrlDialog({
    required String title,
    String? hint,
  }) async {
    final controller = TextEditingController(text: hint ?? '');
    final palette = context.omniPalette;

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.functionLibraryCloudUrlHint,
              style: TextStyle(fontSize: 13, color: palette.textTertiary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'https://example.com/omniflow',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.omniflowCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.l10n.functionLibraryConfirm),
          ),
        ],
      ),
    );
  }

  String _getSyncStatusText(String status) {
    switch (status) {
      case 'synced':
        return context.l10n.functionLibrarySynced;
      case 'local_only':
        return context.l10n.functionLibraryLocalOnly;
      case 'cloud_only':
        return context.l10n.functionLibraryCloudOnly;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;

    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: CommonAppBar(
        title: context.l10n.functionLibraryTitle,
        primary: true,
        actions: [
          // 从云端下载
          IconButton(
            icon: Icon(Icons.cloud_download_outlined, color: palette.textSecondary),
            onPressed: _showDownloadDialog,
            tooltip: context.l10n.functionLibraryDownload,
          ),
          // 刷新
          IconButton(
            icon: Icon(Icons.refresh, color: palette.textSecondary),
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索和筛选栏
          _buildSearchBar(palette),
          // 功能列表
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: palette.accentPrimary,
                    ),
                  )
                : _filteredFunctions.isEmpty
                    ? _buildEmptyState(palette)
                    : _buildFunctionList(palette),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(dynamic palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // 搜索框
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: context.l10n.functionLibrarySearchHint,
              hintStyle: TextStyle(color: palette.textTertiary),
              prefixIcon: Icon(Icons.search, color: palette.textTertiary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: palette.textTertiary),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: palette.surfaceSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          // 应用筛选
          if (_availableApps.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(
                    label: context.l10n.trajectoryAll,
                    selected: _selectedApp.isEmpty,
                    onTap: () => _onAppFilterChanged(''),
                    palette: palette,
                  ),
                  ..._availableApps.map((app) => _buildFilterChip(
                        label: app,
                        selected: _selectedApp == app,
                        onTap: () => _onAppFilterChanged(app),
                        palette: palette,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required dynamic palette,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? palette.accentPrimary : palette.surfaceSecondary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : palette.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(dynamic palette) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: palette.textTertiary),
          const SizedBox(height: 16),
          Text(
            context.l10n.functionLibraryEmpty,
            style: TextStyle(fontSize: 16, color: palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.functionLibraryEmptyDesc,
            style: TextStyle(fontSize: 14, color: palette.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionList(dynamic palette) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _filteredFunctions.length,
      itemBuilder: (context, index) {
        final func = _filteredFunctions[index];
        final isExpanded = _expandedFunctionId == func.functionId;
        return _buildFunctionCard(func, isExpanded, palette);
      },
    );
  }

  Widget _buildFunctionCard(
      UtgFunctionSummary func, bool isExpanded, dynamic palette) {
    final hasParams = func.parameterNames.isNotEmpty;
    final successRate = func.runCount > 0
        ? ((func.successCount / func.runCount) * 100).toInt()
        : null;
    final appName = func.appName.isNotEmpty ? func.appName : func.groupName;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: palette.surfacePrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.borderSubtle, width: 1),
      ),
      child: Column(
        children: [
          // 主卡片内容
          InkWell(
            onTap: () {
              setState(() {
                _expandedFunctionId =
                    isExpanded ? null : func.functionId;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      // 功能图标
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: palette.accentPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.bolt,
                          color: palette.accentPrimary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 标题和应用名
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              func.description.isNotEmpty
                                  ? func.description
                                  : func.functionId,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: palette.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              appName.isNotEmpty ? appName : '-',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 展开箭头
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: palette.textTertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 统计标签
                  Row(
                    children: [
                      _buildStatChip(
                        '${func.stepCount} ${context.l10n.functionLibrarySteps}',
                        palette,
                      ),
                      if (hasParams)
                        _buildStatChip(
                          context.l10n.functionLibraryHasParams,
                          palette,
                          color: palette.accentPrimary,
                        ),
                      if (successRate != null)
                        _buildStatChip(
                          '$successRate%',
                          palette,
                          color: successRate >= 80
                              ? Colors.green
                              : successRate >= 50
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                      if (func.createdAt.isNotEmpty)
                        _buildStatChip(
                          _formatDateShort(func.createdAt),
                          palette,
                        ),
                      const Spacer(),
                      if (func.runCount > 0)
                        Text(
                          '${context.l10n.functionLibraryRunCount}: ${func.runCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 展开详情
          if (isExpanded) _buildExpandedContent(func, palette),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, dynamic palette, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? palette.textTertiary).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color ?? palette.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildExpandedContent(UtgFunctionSummary func, dynamic palette) {
    final lastRun = func.lastRun;
    final hasLastRun = lastRun.isNotEmpty && lastRun['run_id'] != null;
    final lastRunSuccess = lastRun['success'] == true;
    final lastRunGoal = (lastRun['goal'] ?? '').toString();
    final lastRunTime = (lastRun['finished_at'] ?? lastRun['started_at'] ?? '').toString();

    // 生成自然语言总结
    final summary = _buildFunctionSummary(func);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          // 自然语言总结
          if (summary.isNotEmpty) ...[
            Text(
              summary,
              style: TextStyle(
                fontSize: 14,
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 参数
          if (func.parameterNames.isNotEmpty) ...[
            _buildDetailRow(
              context.l10n.functionLibraryParams,
              func.parameterNames.join(', '),
              palette,
            ),
            const SizedBox(height: 8),
          ],
          // 最近执行信息
          if (hasLastRun) ...[
            _buildLastRunSection(
              palette,
              success: lastRunSuccess,
              goal: lastRunGoal,
              time: lastRunTime,
            ),
            const SizedBox(height: 8),
          ],
          // 同步状态
          if (func.syncStatus.isNotEmpty && func.syncStatus != 'local_only') ...[
            _buildDetailRow(
              context.l10n.functionLibrarySyncStatus,
              _getSyncStatusText(func.syncStatus),
              palette,
            ),
            const SizedBox(height: 8),
          ],
          // 操作按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 编辑按钮
              _buildActionButton(
                icon: Icons.edit_outlined,
                label: context.l10n.functionLibraryEdit,
                color: palette.accentPrimary,
                onTap: () => _editFunction(func),
              ),
              const SizedBox(width: 16),
              // 上传按钮
              _buildActionButton(
                icon: Icons.cloud_upload_outlined,
                label: context.l10n.functionLibraryUpload,
                color: palette.textSecondary,
                onTap: () => _uploadFunction(func),
              ),
              const SizedBox(width: 16),
              // 删除按钮
              _buildActionButton(
                icon: Icons.delete_outline,
                label: context.l10n.functionLibraryDelete,
                color: Colors.red,
                onTap: () => _deleteFunction(func),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }

  String _buildFunctionSummary(UtgFunctionSummary func) {
    final parts = <String>[];

    // 起始 -> 结束
    if (func.startNodeDescription.isNotEmpty && func.endNodeDescription.isNotEmpty) {
      if (func.startNodeDescription == func.endNodeDescription) {
        parts.add('在「${func.startNodeDescription}」页面');
      } else {
        parts.add('从「${func.startNodeDescription}」到「${func.endNodeDescription}」');
      }
    } else if (func.startNodeDescription.isNotEmpty) {
      parts.add('从「${func.startNodeDescription}」开始');
    } else if (func.endNodeDescription.isNotEmpty) {
      parts.add('到达「${func.endNodeDescription}」');
    }

    // 步数
    if (func.stepCount > 0) {
      parts.add('共 ${func.stepCount} 步操作');
    }

    // 参数
    if (func.parameterNames.isNotEmpty) {
      parts.add('需要输入 ${func.parameterNames.length} 个参数');
    }

    return parts.join('，');
  }

  Future<void> _editFunction(UtgFunctionSummary func) async {
    final controller = TextEditingController(text: func.description);
    final palette = context.omniPalette;

    final newDescription = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.functionLibraryEditTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.functionLibraryEditHint,
              style: TextStyle(fontSize: 13, color: palette.textTertiary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: context.l10n.functionLibraryEditPlaceholder,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              autofocus: true,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.omniflowCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.l10n.functionLibraryConfirm),
          ),
        ],
      ),
    );

    if (newDescription == null || newDescription == func.description) return;

    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      final result = await AssistsMessageService.updateUtgFunction(
        functionId: func.functionId,
        description: newDescription,
        baseUrl: config.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      if (result.success) {
        showToast(context.l10n.functionLibraryEditSuccess, type: ToastType.success);
        _loadData(silent: true);
      } else {
        showToast(result.errorMessage ?? context.l10n.functionLibraryEditFailed,
            type: ToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      showToast('${context.l10n.functionLibraryEditFailed}: $e', type: ToastType.error);
    }
  }

  Widget _buildLastRunSection(dynamic palette, {
    required bool success,
    required String goal,
    required String time,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.functionLibraryLastRun,
              style: TextStyle(
                fontSize: 13,
                color: palette.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (success ? Colors.green : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                success
                    ? context.l10n.functionLibraryLastRunSuccess
                    : context.l10n.functionLibraryLastRunFailed,
                style: TextStyle(
                  fontSize: 11,
                  color: success ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (time.isNotEmpty) ...[
              const Spacer(),
              Text(
                _formatDateShort(time),
                style: TextStyle(
                  fontSize: 12,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ],
        ),
        if (goal.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            goal,
            style: TextStyle(
              fontSize: 13,
              color: palette.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, dynamic palette,
      {bool mono = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: palette.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: palette.textSecondary,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateShort(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      // 如果是今年，只显示月/日
      if (date.year == now.year) {
        return '${date.month}/${date.day}';
      }
      // 否则显示年/月/日
      return '${date.year % 100}/${date.month}/${date.day}';
    } catch (_) {
      // 尝试截取前10个字符（日期部分）
      if (dateStr.length >= 10) {
        return dateStr.substring(5, 10).replaceAll('-', '/');
      }
      return dateStr;
    }
  }
}
