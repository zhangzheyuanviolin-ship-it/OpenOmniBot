import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/core/mixins/page_lifecycle_mixin.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/omniflow_asset_card.dart';

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
    // Convert to OmniFlowAssetCardData
    final cardData = OmniFlowAssetCardData.fromUtgFunctionSummary(func);

    return OmniFlowAssetCard(
      data: cardData,
      expanded: isExpanded,
      onTap: () {
        setState(() {
          _expandedFunctionId = isExpanded ? null : func.functionId;
        });
      },
      onEdit: () => _editFunction(func),
      onEnrich: () => _enrichFunction(func),
      onUpload: () => _uploadFunction(func),
      onDelete: () => _deleteFunction(func),
      expandedContentBuilder: (context, isDark) =>
          _buildExpandedContent(func, palette),
    );
  }

  Widget _buildExpandedContent(UtgFunctionSummary func, dynamic palette) {
    final lastRun = func.lastRun;
    final hasLastRun = lastRun.isNotEmpty && lastRun['run_id'] != null;
    final lastRunSuccess = lastRun['success'] == true;
    final lastRunGoal = (lastRun['goal'] ?? '').toString();
    final lastRunTime = (lastRun['finished_at'] ?? lastRun['started_at'] ?? '').toString();
    final isDark = context.isDarkTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? palette.borderSubtle : OmniFlowAssetColors.border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          // Function ID（始终显示）
          _buildDetailRow(
            context.l10n.omniflowAssetId,
            func.functionId,
            palette,
            mono: true,
            selectable: true,
          ),
          // 包名
          if (func.packageName.isNotEmpty)
            _buildDetailRow(
              context.l10n.omniflowAssetPackage,
              func.packageName,
              palette,
            ),
          // 起始页面
          if (func.startNodeDescription.isNotEmpty)
            _buildDetailRow(
              context.l10n.omniflowAssetStartPage,
              func.startNodeDescription,
              palette,
            ),
          // 结束页面
          if (func.endNodeDescription.isNotEmpty)
            _buildDetailRow(
              context.l10n.omniflowAssetEndPage,
              func.endNodeDescription,
              palette,
            ),
          // 参数
          if (func.parameterNames.isNotEmpty)
            _buildDetailRow(
              context.l10n.functionLibraryParams,
              func.parameterNames.join(', '),
              palette,
            ),
          // 创建时间
          if (func.createdAt.isNotEmpty)
            _buildDetailRow(
              context.l10n.omniflowAssetCreatedAt,
              _formatDateFull(func.createdAt),
              palette,
            ),
          // 来源执行记录
          if (func.sourceRunIds.isNotEmpty)
            _buildDetailRow(
              context.l10n.omniflowAssetSourceRuns,
              func.sourceRunIds.take(3).map((id) => _truncateId(id)).join(', '),
              palette,
              mono: true,
            ),
          // 最近执行信息
          if (hasLastRun) ...[
            const SizedBox(height: 4),
            _buildLastRunSection(
              palette,
              success: lastRunSuccess,
              goal: lastRunGoal,
              time: lastRunTime,
            ),
          ],
          // 同步状态
          if (func.syncStatus.isNotEmpty && func.syncStatus != 'local_only')
            _buildDetailRow(
              context.l10n.functionLibrarySyncStatus,
              _getSyncStatusText(func.syncStatus),
              palette,
            ),
          const SizedBox(height: 12),
          // 操作按钮行 - 使用统一颜色
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 复制 ID
              _buildActionButton(
                icon: Icons.copy_outlined,
                label: context.l10n.omniflowAssetCopyId,
                color: OmniFlowAssetColors.detailPillText,
                onTap: () => _copyFunctionId(func),
              ),
              const SizedBox(width: 12),
              // 编辑按钮
              _buildActionButton(
                icon: Icons.edit_outlined,
                label: context.l10n.functionLibraryEdit,
                color: OmniFlowAssetColors.compileMiss,
                onTap: () => _editFunction(func),
              ),
              const SizedBox(width: 12),
              // 升级按钮
              _buildActionButton(
                icon: Icons.auto_awesome_outlined,
                label: context.l10n.functionLibraryEnrich,
                color: OmniFlowAssetColors.functionType,
                onTap: () => _enrichFunction(func),
              ),
              const SizedBox(width: 12),
              // 上传按钮
              _buildActionButton(
                icon: Icons.cloud_upload_outlined,
                label: context.l10n.functionLibraryUpload,
                color: OmniFlowAssetColors.detailPillText,
                onTap: () => _uploadFunction(func),
              ),
              const SizedBox(width: 12),
              // 删除按钮
              _buildActionButton(
                icon: Icons.delete_outline,
                label: context.l10n.functionLibraryDelete,
                color: OmniFlowAssetColors.failed,
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

  Future<void> _enrichFunction(UtgFunctionSummary func) async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: OmniFlowAssetColors.functionTypeBg,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.auto_awesome,
            color: OmniFlowAssetColors.functionType,
            size: 24,
          ),
        ),
        title: Text(context.l10n.functionLibraryEnrichTitle),
        content: Text(
          context.l10n.functionLibraryEnrichConfirm,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            height: 1.5,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.omniflowAssetCancel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(context.l10n.functionLibraryEnrich),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 显示加载中
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(context.l10n.functionLibraryEnrichProgress)),
          ],
        ),
      ),
    );

    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      final result = await AssistsMessageService.enrichUtgFunction(
        functionId: func.functionId,
        baseUrl: config.resolvedOmniflowBaseUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框

      if (result.success) {
        showToast(context.l10n.functionLibraryEnrichSuccess, type: ToastType.success);
        _loadData(silent: true);
      } else {
        showToast(
          result.errorMessage != null
              ? context.l10n.functionLibraryEnrichFailedWithMessage(result.errorMessage!)
              : context.l10n.functionLibraryEnrichFailed,
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载对话框
      showToast(
        context.l10n.functionLibraryEnrichFailedWithMessage(e.toString()),
        type: ToastType.error,
      );
    }
  }

  Widget _buildLastRunSection(dynamic palette, {
    required bool success,
    required String goal,
    required String time,
  }) {
    final isDark = context.isDarkTheme;
    final successColor = OmniFlowAssetColors.success;
    final failedColor = OmniFlowAssetColors.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.functionLibraryLastRun,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : OmniFlowAssetColors.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: success
                    ? OmniFlowAssetColors.successBg
                    : OmniFlowAssetColors.failedBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                success
                    ? context.l10n.functionLibraryLastRunSuccess
                    : context.l10n.functionLibraryLastRunFailed,
                style: TextStyle(
                  fontSize: 11,
                  color: success ? successColor : failedColor,
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
                  color: isDark ? Colors.white54 : OmniFlowAssetColors.textTertiary,
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
              color: isDark ? Colors.white70 : OmniFlowAssetColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, dynamic palette,
      {bool mono = false, bool selectable = false}) {
    if (value.isEmpty) return const SizedBox.shrink();
    final isDark = context.isDarkTheme;

    final textWidget = selectable
        ? SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : OmniFlowAssetColors.textSecondary,
              fontFamily: mono ? 'monospace' : null,
              height: 1.5,
            ),
          )
        : Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : OmniFlowAssetColors.textSecondary,
              fontFamily: mono ? 'monospace' : null,
              height: 1.5,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : OmniFlowAssetColors.textTertiary,
              ),
            ),
          ),
          Expanded(child: textWidget),
        ],
      ),
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

  String _formatDateFull(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      if (dateStr.length >= 16) {
        return dateStr.substring(0, 16).replaceAll('T', ' ');
      }
      return dateStr;
    }
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  Future<void> _copyFunctionId(UtgFunctionSummary func) async {
    await Clipboard.setData(ClipboardData(text: func.functionId));
    if (mounted) {
      showToast(context.l10n.omniflowAssetIdCopied, type: ToastType.success);
    }
  }
}
