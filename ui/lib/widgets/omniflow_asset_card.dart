import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';

/// 资产类型
enum OmniFlowAssetType {
  function,
  runLog,
}

/// 资产状态
enum OmniFlowAssetStatus {
  success,
  failed,
  running,
  unknown,
}

/// 编译状态
enum OmniFlowCompileStatus {
  hit,
  miss,
  none,
}

/// 通用资产卡片颜色配置
class OmniFlowAssetColors {
  // 状态颜色 - Light
  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFE7F8ED);
  static const Color failed = Color(0xFFEF4444);
  static const Color failedBg = Color(0xFFFDECEC);
  static const Color running = Color(0xFF6B7280);
  static const Color runningBg = Color(0xFFF3F4F6);

  // 状态颜色 - Dark
  static const Color successDark = Color(0xFF34D399);
  static const Color successBgDark = Color(0xFF1A3A2A);
  static const Color failedDark = Color(0xFFF87171);
  static const Color failedBgDark = Color(0xFF3A1A1A);
  static const Color runningDark = Color(0xFF9CA3AF);
  static const Color runningBgDark = Color(0xFF2A2A2A);

  // 类型颜色
  static const Color functionType = Color(0xFFF59E0B);
  static const Color functionTypeBg = Color(0xFFFEF3C7);
  static const Color functionTypeBgDark = Color(0xFF3A2A1A);
  static const Color runLogType = Color(0xFF3B82F6);
  static const Color runLogTypeBg = Color(0xFFDBEAFE);
  static const Color runLogTypeBgDark = Color(0xFF1A2A3A);

  // 编译状态颜色 - Light
  static const Color compileHit = Color(0xFF2F8F4E);
  static const Color compileHitBg = Color(0xFFEAF7EE);
  static const Color compileMiss = Color(0xFF3B82F6);
  static const Color compileMissBg = Color(0xFFEAF2FF);

  // 编译状态颜色 - Dark
  static const Color compileHitDark = Color(0xFF4ADE80);
  static const Color compileHitBgDark = Color(0xFF1A3A2A);
  static const Color compileMissDark = Color(0xFF60A5FA);
  static const Color compileMissBgDark = Color(0xFF1A2A3A);

  // 通用颜色 - Light
  static const Color detailPillBg = Color(0xFFF1F4FA);
  static const Color detailPillText = Color(0xFF64748B);
  static const Color cardBg = Color(0xFFF7F9FC);
  static const Color border = Color(0xFFE4E8EE);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textTertiary = Color(0xFF9CA3AF);

  // 通用颜色 - Dark
  static const Color detailPillBgDark = Color(0xFF2A2F3A);
  static const Color detailPillTextDark = Color(0xFF94A3B8);

  // 根据深色模式获取颜色的便捷方法
  static Color getSuccessColor(bool isDark) => isDark ? successDark : success;
  static Color getSuccessBgColor(bool isDark) => isDark ? successBgDark : successBg;
  static Color getFailedColor(bool isDark) => isDark ? failedDark : failed;
  static Color getFailedBgColor(bool isDark) => isDark ? failedBgDark : failedBg;
  static Color getRunningColor(bool isDark) => isDark ? runningDark : running;
  static Color getRunningBgColor(bool isDark) => isDark ? runningBgDark : runningBg;
  static Color getCompileHitColor(bool isDark) => isDark ? compileHitDark : compileHit;
  static Color getCompileHitBgColor(bool isDark) => isDark ? compileHitBgDark : compileHitBg;
  static Color getCompileMissColor(bool isDark) => isDark ? compileMissDark : compileMiss;
  static Color getCompileMissBgColor(bool isDark) => isDark ? compileMissBgDark : compileMissBg;
  static Color getDetailPillBgColor(bool isDark) => isDark ? detailPillBgDark : detailPillBg;
  static Color getDetailPillTextColor(bool isDark) => isDark ? detailPillTextDark : detailPillText;
}

/// 通用资产卡片数据模型
class OmniFlowAssetCardData {
  final String id;
  final OmniFlowAssetType type;
  final String title;
  final String? subtitle;
  final int stepCount;
  final OmniFlowAssetStatus status;
  final OmniFlowCompileStatus compileStatus;
  final String? statusLabel;
  final String? timestamp;
  final String? packageName;
  final List<String> linkedIds;
  final Map<String, dynamic>? extra;

  const OmniFlowAssetCardData({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.stepCount = 0,
    this.status = OmniFlowAssetStatus.unknown,
    this.compileStatus = OmniFlowCompileStatus.none,
    this.statusLabel,
    this.timestamp,
    this.packageName,
    this.linkedIds = const [],
    this.extra,
  });

  /// 从 Function 数据创建
  factory OmniFlowAssetCardData.fromFunction(Map<String, dynamic> map) {
    final runStats = map['run_stats'] as Map? ?? {};
    final successCount = (runStats['success_count'] as num?)?.toInt() ?? 0;
    final failCount = (runStats['fail_count'] as num?)?.toInt() ?? 0;
    final runCount = (runStats['run_count'] as num?)?.toInt() ?? 0;

    OmniFlowAssetStatus status = OmniFlowAssetStatus.unknown;
    if (runCount > 0) {
      status = successCount > failCount
          ? OmniFlowAssetStatus.success
          : OmniFlowAssetStatus.failed;
    }

    return OmniFlowAssetCardData(
      id: (map['function_id'] ?? '').toString(),
      type: OmniFlowAssetType.function,
      title: (map['description'] ?? '').toString(),
      subtitle: (map['app_name'] ?? map['group_name'] ?? '').toString(),
      stepCount: (map['step_count'] as num?)?.toInt() ?? 0,
      status: status,
      compileStatus: OmniFlowCompileStatus.none,
      statusLabel: (map['asset_state'] ?? '').toString(),
      timestamp: (map['created_at'] ?? '').toString(),
      packageName: (map['package_name'] ?? '').toString(),
      linkedIds: (map['source_run_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      extra: map,
    );
  }

  /// 从 UtgFunctionSummary 创建（用于 FunctionLibraryPage）
  factory OmniFlowAssetCardData.fromUtgFunctionSummary(dynamic func) {
    final runCount = (func.runCount as num?)?.toInt() ?? 0;
    final successCount = (func.successCount as num?)?.toInt() ?? 0;
    final failCount = (func.failCount as num?)?.toInt() ?? 0;

    OmniFlowAssetStatus status = OmniFlowAssetStatus.unknown;
    if (runCount > 0) {
      status = successCount > failCount
          ? OmniFlowAssetStatus.success
          : OmniFlowAssetStatus.failed;
    }

    return OmniFlowAssetCardData(
      id: (func.functionId ?? '').toString(),
      type: OmniFlowAssetType.function,
      title: (func.description ?? '').toString(),
      subtitle: ((func.appName ?? '').toString().isNotEmpty
              ? func.appName
              : func.groupName ?? '')
          .toString(),
      stepCount: (func.stepCount as num?)?.toInt() ?? 0,
      status: status,
      compileStatus: OmniFlowCompileStatus.none,
      statusLabel: (func.assetState ?? '').toString(),
      timestamp: (func.createdAt ?? '').toString(),
      packageName: (func.packageName ?? '').toString(),
      linkedIds: (func.sourceRunIds as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      extra: {
        'function_id': func.functionId,
        'description': func.description,
        'action_count': func.actionCount,
        'step_count': func.stepCount,
        'parameter_names': func.parameterNames,
        'parameter_examples': func.parameterExamples,
        'start_node_id': func.startNodeId,
        'end_node_id': func.endNodeId,
        'package_name': func.packageName,
        'app_name': func.appName,
        'group_name': func.groupName,
        'source': func.source,
        'created_at': func.createdAt,
        'updated_at': func.updatedAt,
        'sync_status': func.syncStatus,
        'sync_origin': func.syncOrigin,
        'cloud_base_url': func.cloudBaseUrl,
        'run_count': func.runCount,
        'success_count': func.successCount,
        'fail_count': func.failCount,
        'last_run': func.lastRun,
        'run_stats': func.runStats,
      },
    );
  }

  /// 从 RunLog 数据创建
  factory OmniFlowAssetCardData.fromRunLog(Map<String, dynamic> map) {
    final success = map['success'] == true;
    final compileStatusStr = (map['compile_status'] ?? '').toString();

    OmniFlowCompileStatus compileStatus = OmniFlowCompileStatus.none;
    if (compileStatusStr == 'hit') {
      compileStatus = OmniFlowCompileStatus.hit;
    } else if (compileStatusStr == 'miss') {
      compileStatus = OmniFlowCompileStatus.miss;
    }

    final linkedIds = <String>[];
    final compileFunctionId = (map['compile_function_id'] ?? '').toString();
    if (compileFunctionId.isNotEmpty) {
      linkedIds.add(compileFunctionId);
    }

    return OmniFlowAssetCardData(
      id: (map['run_id'] ?? '').toString(),
      type: OmniFlowAssetType.runLog,
      title: (map['goal'] ?? '').toString(),
      subtitle: (map['tool_name'] ?? '').toString(),
      stepCount: (map['step_count'] as num?)?.toInt() ?? 0,
      status:
          success ? OmniFlowAssetStatus.success : OmniFlowAssetStatus.failed,
      compileStatus: compileStatus,
      statusLabel: compileStatusStr,
      timestamp: (map['started_at'] ?? '').toString(),
      packageName: (map['final_package_name'] ?? '').toString(),
      linkedIds: linkedIds,
      extra: map,
    );
  }

  /// 获取显示标题（如果 title 为空则使用 id）
  String get displayTitle => title.isNotEmpty ? title : id;

  /// 是否有关联资产
  bool get hasLinkedAssets => linkedIds.isNotEmpty;
}

/// 通用资产卡片组件
class OmniFlowAssetCard extends StatelessWidget {
  final OmniFlowAssetCardData data;
  final bool expanded;
  final VoidCallback? onTap;
  final VoidCallback? onMemory;
  final VoidCallback? onReplay;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onViewLinked;
  // Function-specific actions
  final VoidCallback? onUpload;
  final VoidCallback? onEnrich;
  // Custom expanded content builder
  final Widget Function(BuildContext context, bool isDark)? expandedContentBuilder;

  const OmniFlowAssetCard({
    super.key,
    required this.data,
    this.expanded = false,
    this.onTap,
    this.onMemory,
    this.onReplay,
    this.onDelete,
    this.onEdit,
    this.onViewLinked,
    this.onUpload,
    this.onEnrich,
    this.expandedContentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? palette.surfacePrimary : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? palette.borderSubtle : OmniFlowAssetColors.border,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context, palette, isDark),
          if (expanded)
            expandedContentBuilder != null
                ? expandedContentBuilder!(context, isDark)
                : _buildExpandedContent(context, palette, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, dynamic palette, bool isDark) {
    final l10n = context.l10n;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                // 类型图标
                _buildTypeIcon(),
                const SizedBox(width: 12),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.displayTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? palette.textPrimary
                              : OmniFlowAssetColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (data.subtitle?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          data.subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? palette.textTertiary
                                : OmniFlowAssetColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 展开箭头
                if (onTap != null)
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: isDark
                        ? palette.textTertiary
                        : OmniFlowAssetColors.textTertiary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 状态标签行
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 状态标签
                _buildStatusPill(context, isDark),
                // 步数
                if (data.stepCount > 0)
                  _buildDetailPill(
                    l10n.omniflowAssetSteps(data.stepCount),
                    isDark,
                  ),
                // 编译状态
                if (data.compileStatus != OmniFlowCompileStatus.none)
                  _buildCompilePill(context, isDark),
                // 时间
                if (data.timestamp?.isNotEmpty == true)
                  _buildDetailPill(_formatTimestamp(data.timestamp!), isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeIcon() {
    final isFunction = data.type == OmniFlowAssetType.function;
    final color =
        isFunction ? OmniFlowAssetColors.functionType : OmniFlowAssetColors.runLogType;
    final bgColor = isFunction
        ? OmniFlowAssetColors.functionTypeBg
        : OmniFlowAssetColors.runLogTypeBg;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isFunction ? Icons.bolt : Icons.history,
        color: color,
        size: 22,
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context, bool isDark) {
    final l10n = context.l10n;
    Color color;
    Color bgColor;
    String text;

    switch (data.status) {
      case OmniFlowAssetStatus.success:
        color = OmniFlowAssetColors.getSuccessColor(isDark);
        bgColor = OmniFlowAssetColors.getSuccessBgColor(isDark);
        text = l10n.omniflowAssetSuccess;
        break;
      case OmniFlowAssetStatus.failed:
        color = OmniFlowAssetColors.getFailedColor(isDark);
        bgColor = OmniFlowAssetColors.getFailedBgColor(isDark);
        text = l10n.omniflowAssetFailed;
        break;
      case OmniFlowAssetStatus.running:
        color = OmniFlowAssetColors.getRunningColor(isDark);
        bgColor = OmniFlowAssetColors.getRunningBgColor(isDark);
        text = l10n.omniflowAssetRunning;
        break;
      case OmniFlowAssetStatus.unknown:
        color = OmniFlowAssetColors.getDetailPillTextColor(isDark);
        bgColor = OmniFlowAssetColors.getDetailPillBgColor(isDark);
        text = data.statusLabel?.isNotEmpty == true
            ? data.statusLabel!
            : l10n.omniflowAssetUnknown;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCompilePill(BuildContext context, bool isDark) {
    final l10n = context.l10n;
    final isHit = data.compileStatus == OmniFlowCompileStatus.hit;
    final color = isHit
        ? OmniFlowAssetColors.getCompileHitColor(isDark)
        : OmniFlowAssetColors.getCompileMissColor(isDark);
    final bgColor = isHit
        ? OmniFlowAssetColors.getCompileHitBgColor(isDark)
        : OmniFlowAssetColors.getCompileMissBgColor(isDark);
    final text = isHit ? l10n.omniflowAssetCompileHit : l10n.omniflowAssetCompileMiss;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailPill(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: OmniFlowAssetColors.getDetailPillBgColor(isDark),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: OmniFlowAssetColors.getDetailPillTextColor(isDark),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildExpandedContent(
      BuildContext context, dynamic palette, bool isDark) {
    final l10n = context.l10n;

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
          // ID
          _buildInfoRow(
            l10n.omniflowAssetId,
            data.id,
            isDark,
            mono: true,
            selectable: true,
          ),
          // 包名
          if (data.packageName?.isNotEmpty == true)
            _buildInfoRow(
              l10n.omniflowAssetPackage,
              data.packageName!,
              isDark,
            ),
          // 关联资产
          if (data.hasLinkedAssets)
            _buildLinkedSection(context, isDark),
          const SizedBox(height: 12),
          // 操作按钮
          _buildActions(context, isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isDark, {
    bool mono = false,
    bool selectable = false,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();

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

  Widget _buildLinkedSection(BuildContext context, bool isDark) {
    final l10n = context.l10n;
    final isFunction = data.type == OmniFlowAssetType.function;
    final label = isFunction
        ? l10n.omniflowAssetSourceRuns
        : l10n.omniflowAssetLinkedFunction;

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
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: data.linkedIds.take(3).map((id) {
                return InkWell(
                  onTap: onViewLinked,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: OmniFlowAssetColors.detailPillBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _truncateId(id),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: OmniFlowAssetColors.detailPillText,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isDark) {
    final l10n = context.l10n;
    final isFunction = data.type == OmniFlowAssetType.function;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 复制 ID
        _buildActionButton(
          icon: Icons.copy_outlined,
          label: l10n.omniflowAssetCopyId,
          color: OmniFlowAssetColors.detailPillText,
          onTap: () => _copyId(context),
        ),
        const SizedBox(width: 12),
        // 编辑（仅 Function）
        if (isFunction && onEdit != null) ...[
          _buildActionButton(
            icon: Icons.edit_outlined,
            label: l10n.omniflowAssetEdit,
            color: OmniFlowAssetColors.compileMiss,
            onTap: onEdit,
          ),
          const SizedBox(width: 12),
        ],
        // 升级（仅 Function）
        if (isFunction && onEnrich != null) ...[
          _buildActionButton(
            icon: Icons.auto_awesome_outlined,
            label: l10n.omniflowAssetEnrich,
            color: OmniFlowAssetColors.functionType,
            onTap: onEnrich,
          ),
          const SizedBox(width: 12),
        ],
        // 上传（仅 Function）
        if (isFunction && onUpload != null) ...[
          _buildActionButton(
            icon: Icons.cloud_upload_outlined,
            label: l10n.omniflowAssetUpload,
            color: OmniFlowAssetColors.detailPillText,
            onTap: onUpload,
          ),
          const SizedBox(width: 12),
        ],
        // 记忆（仅 RunLog）
        if (!isFunction && onMemory != null) ...[
          _buildActionButton(
            icon: Icons.psychology_alt_outlined,
            label: l10n.omniflowAssetMemory,
            color: OmniFlowAssetColors.functionType,
            onTap: onMemory,
          ),
          const SizedBox(width: 12),
        ],
        // 重放（仅 RunLog）
        if (!isFunction && onReplay != null) ...[
          _buildActionButton(
            icon: Icons.play_arrow_outlined,
            label: l10n.omniflowAssetReplay,
            color: OmniFlowAssetColors.compileHit,
            onTap: onReplay,
          ),
          const SizedBox(width: 12),
        ],
        // 删除
        if (onDelete != null)
          _buildActionButton(
            icon: Icons.delete_outline,
            label: l10n.omniflowAssetDelete,
            color: OmniFlowAssetColors.failed,
            onTap: onDelete,
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
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

  Future<void> _copyId(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: data.id));
    if (context.mounted) {
      showToast(context.l10n.omniflowAssetIdCopied, type: ToastType.success);
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      if (date.year == now.year) {
        return '${date.month}/${date.day}';
      }
      return '${date.year % 100}/${date.month}/${date.day}';
    } catch (_) {
      if (timestamp.length >= 10) {
        return timestamp.substring(5, 10).replaceAll('-', '/');
      }
      return timestamp;
    }
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
}

/// 资产详情弹窗
class OmniFlowAssetDetailDialog extends StatelessWidget {
  final OmniFlowAssetCardData data;
  final Map<String, dynamic>? viewData;
  final VoidCallback? onMemory;
  final VoidCallback? onReplay;
  final VoidCallback? onClose;

  const OmniFlowAssetDetailDialog({
    super.key,
    required this.data,
    this.viewData,
    this.onMemory,
    this.onReplay,
    this.onClose,
  });

  static Future<void> show(
    BuildContext context, {
    required OmniFlowAssetCardData data,
    Map<String, dynamic>? viewData,
    VoidCallback? onMemory,
    VoidCallback? onReplay,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
            child: OmniFlowAssetDetailDialog(
              data: data,
              viewData: viewData,
              onMemory: onMemory,
              onReplay: onReplay,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;
    final isFunction = data.type == OmniFlowAssetType.function;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            data.displayTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? palette.textPrimary : OmniFlowAssetColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // ID
          SelectableText(
            data.id,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: isDark ? palette.textTertiary : OmniFlowAssetColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          // 状态标签
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusPill(context),
              if (data.stepCount > 0)
                _buildPill(context, l10n.omniflowAssetSteps(data.stepCount)),
              if (data.compileStatus != OmniFlowCompileStatus.none)
                _buildCompilePill(context),
              if (data.subtitle?.isNotEmpty == true)
                _buildPill(context, data.subtitle!),
            ],
          ),
          const SizedBox(height: 16),
          // 详情卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? palette.surfaceSecondary : OmniFlowAssetColors.cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 详情头部
                Row(
                  children: [
                    Text(
                      isFunction
                          ? l10n.omniflowAssetFunctionDetail
                          : l10n.omniflowAssetRunLogDetail,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? palette.textPrimary
                            : OmniFlowAssetColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (viewData != null)
                      OutlinedButton(
                        onPressed: () => _copyViewJson(context),
                        child: Text(l10n.omniflowAssetCopyJson),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // 详情内容
                _buildDetailContent(context, isDark, palette),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _copyId(context),
                child: Text(l10n.omniflowAssetCopyId),
              ),
              const SizedBox(width: 8),
              if (!isFunction && onMemory != null) ...[
                FilledButton.icon(
                  onPressed: onMemory,
                  icon: const Icon(Icons.psychology_alt_outlined),
                  label: Text(l10n.omniflowAssetMemory),
                ),
                const SizedBox(width: 8),
              ],
              if (!isFunction && onReplay != null) ...[
                OutlinedButton.icon(
                  onPressed: onReplay,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text(l10n.omniflowAssetReplay),
                ),
                const SizedBox(width: 8),
              ],
              TextButton(
                onPressed: onClose,
                child: Text(l10n.omniflowAssetClose),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context) {
    final l10n = context.l10n;
    final isDark = context.isDarkTheme;
    Color color;
    Color bgColor;
    String text;

    switch (data.status) {
      case OmniFlowAssetStatus.success:
        color = OmniFlowAssetColors.getSuccessColor(isDark);
        bgColor = OmniFlowAssetColors.getSuccessBgColor(isDark);
        text = l10n.omniflowAssetSuccess;
        break;
      case OmniFlowAssetStatus.failed:
        color = OmniFlowAssetColors.getFailedColor(isDark);
        bgColor = OmniFlowAssetColors.getFailedBgColor(isDark);
        text = l10n.omniflowAssetFailed;
        break;
      case OmniFlowAssetStatus.running:
        color = OmniFlowAssetColors.getRunningColor(isDark);
        bgColor = OmniFlowAssetColors.getRunningBgColor(isDark);
        text = l10n.omniflowAssetRunning;
        break;
      case OmniFlowAssetStatus.unknown:
        color = OmniFlowAssetColors.getDetailPillTextColor(isDark);
        bgColor = OmniFlowAssetColors.getDetailPillBgColor(isDark);
        text = l10n.omniflowAssetUnknown;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCompilePill(BuildContext context) {
    final l10n = context.l10n;
    final isDark = context.isDarkTheme;
    final isHit = data.compileStatus == OmniFlowCompileStatus.hit;
    final color = isHit
        ? OmniFlowAssetColors.getCompileHitColor(isDark)
        : OmniFlowAssetColors.getCompileMissColor(isDark);
    final bgColor = isHit
        ? OmniFlowAssetColors.getCompileHitBgColor(isDark)
        : OmniFlowAssetColors.getCompileMissBgColor(isDark);
    final text = isHit ? l10n.omniflowAssetCompileHit : l10n.omniflowAssetCompileMiss;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context, String text) {
    final isDark = context.isDarkTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: OmniFlowAssetColors.getDetailPillBgColor(isDark),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: OmniFlowAssetColors.getDetailPillTextColor(isDark),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDetailContent(BuildContext context, bool isDark, dynamic palette) {
    final extra = data.extra ?? {};
    final l10n = context.l10n;

    if (data.type == OmniFlowAssetType.function) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(l10n.omniflowAssetStartPage,
              (extra['start_node_description'] ?? '').toString(), isDark),
          _buildDetailRow(l10n.omniflowAssetEndPage,
              (extra['end_node_description'] ?? '').toString(), isDark),
          _buildDetailRow(l10n.omniflowAssetPackage,
              (extra['package_name'] ?? '').toString(), isDark),
          _buildDetailRow(l10n.omniflowAssetCreatedAt,
              (extra['created_at'] ?? '').toString(), isDark),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
              l10n.omniflowAssetGoal, (extra['goal'] ?? '').toString(), isDark),
          _buildDetailRow(l10n.omniflowAssetStartedAt,
              (extra['started_at'] ?? '').toString(), isDark),
          _buildDetailRow(l10n.omniflowAssetDoneReason,
              (extra['done_reason'] ?? '').toString(), isDark),
          _buildDetailRow(l10n.omniflowAssetPackage,
              (extra['final_package_name'] ?? '').toString(), isDark),
        ],
      );
    }
  }

  Widget _buildDetailRow(String label, String value, bool isDark) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : OmniFlowAssetColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : OmniFlowAssetColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyId(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: data.id));
    if (context.mounted) {
      showToast(context.l10n.omniflowAssetIdCopied, type: ToastType.success);
    }
  }

  Future<void> _copyViewJson(BuildContext context) async {
    if (viewData == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(viewData);
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      showToast(context.l10n.omniflowAssetJsonCopied, type: ToastType.success);
    }
  }
}
