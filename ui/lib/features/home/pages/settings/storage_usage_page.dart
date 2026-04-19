import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/services/storage_usage_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class StorageUsagePage extends StatefulWidget {
  const StorageUsagePage({super.key});

  @override
  State<StorageUsagePage> createState() => _StorageUsagePageState();
}

class _StorageUsagePageState extends State<StorageUsagePage> {
  bool _loading = true;
  String? _error;
  String? _clearingCategoryId;
  String? _applyingStrategyId;
  StorageUsageSummary? _summary;

  String _catName(String id, String fallback) {
    final l = context.l10n;
    switch (id) {
      case 'app_binary': return l.storageCatAppBinary;
      case 'cache': return l.storageCatCache;
      case 'conversation_history': return l.storageCatConversation;
      case 'database_other': return l.storageCatDatabaseOther;
      case 'workspace_browser': return l.storageCatWorkspaceBrowser;
      case 'workspace_offloads': return l.storageCatWorkspaceOffloads;
      case 'workspace_attachments': return l.storageCatWorkspaceAttachments;
      case 'workspace_shared': return l.storageCatWorkspaceShared;
      case 'workspace_memory': return l.storageCatWorkspaceMemory;
      case 'workspace_user_files': return l.storageCatWorkspaceUserFiles;
      case 'local_models_files': return l.storageCatLocalModelsFiles;
      case 'local_models_cache': return l.storageCatLocalModelsCache;
      case 'terminal_runtime_local': return l.storageCatTerminalLocal;
      case 'terminal_runtime_bootstrap': return l.storageCatTerminalBootstrap;
      case 'shared_drafts': return l.storageCatSharedDrafts;
      case 'mcp_inbox': return l.storageCatMcpInbox;
      case 'legacy_workspace': return l.storageCatLegacyWorkspace;
      case 'other_user_data': return l.storageCatOtherUserData;
      default: return fallback;
    }
  }

  String _catDesc(String id, String fallback) {
    final l = context.l10n;
    switch (id) {
      case 'app_binary': return l.storageCatAppBinaryDesc;
      case 'cache': return l.storageCatCacheDesc;
      case 'conversation_history': return l.storageCatConversationDesc;
      case 'database_other': return l.storageCatDatabaseOtherDesc;
      case 'workspace_browser': return l.storageCatWorkspaceBrowserDesc;
      case 'workspace_offloads': return l.storageCatWorkspaceOffloadsDesc;
      case 'workspace_attachments': return l.storageCatWorkspaceAttachmentsDesc;
      case 'workspace_shared': return l.storageCatWorkspaceSharedDesc;
      case 'workspace_memory': return l.storageCatWorkspaceMemoryDesc;
      case 'workspace_user_files': return l.storageCatWorkspaceUserFilesDesc;
      case 'local_models_files': return l.storageCatLocalModelsFilesDesc;
      case 'local_models_cache': return l.storageCatLocalModelsCacheDesc;
      case 'terminal_runtime_local': return l.storageCatTerminalLocalDesc;
      case 'terminal_runtime_bootstrap': return l.storageCatTerminalBootstrapDesc;
      case 'shared_drafts': return l.storageCatSharedDraftsDesc;
      case 'mcp_inbox': return l.storageCatMcpInboxDesc;
      case 'legacy_workspace': return l.storageCatLegacyWorkspaceDesc;
      case 'other_user_data': return l.storageCatOtherUserDataDesc;
      default: return fallback;
    }
  }

  String? _catHint(String id) {
    final l = context.l10n;
    switch (id) {
      case 'cache': return l.storageCatCacheHint;
      case 'conversation_history': return l.storageCatConversationHint;
      case 'workspace_browser': return l.storageCatWorkspaceBrowserHint;
      case 'workspace_offloads': return l.storageCatWorkspaceOffloadsHint;
      case 'workspace_attachments': return l.storageCatWorkspaceAttachmentsHint;
      case 'workspace_shared': return l.storageCatWorkspaceSharedHint;
      case 'local_models_files': return l.storageCatLocalModelsFilesHint;
      case 'local_models_cache': return l.storageCatLocalModelsCacheHint;
      case 'terminal_runtime_local': return l.storageCatTerminalLocalHint;
      case 'terminal_runtime_bootstrap': return l.storageCatTerminalBootstrapHint;
      case 'shared_drafts': return l.storageCatSharedDraftsHint;
      case 'mcp_inbox': return l.storageCatMcpInboxHint;
      case 'legacy_workspace': return l.storageCatLegacyWorkspaceHint;
      default: return null;
    }
  }

  String _stratName(String id, String fallback) {
    final l = context.l10n;
    switch (id) {
      case 'safe_quick': return l.storageStrategySafeQuick;
      case 'balance_deep': return l.storageStrategyBalanceDeep;
      case 'free_1gb_priority': return l.storageStrategyFree1gb;
      default: return fallback;
    }
  }

  String _stratDesc(String id, String fallback) {
    final l = context.l10n;
    switch (id) {
      case 'safe_quick': return l.storageStrategySafeQuickDesc;
      case 'balance_deep': return l.storageStrategyBalanceDeepDesc;
      case 'free_1gb_priority': return l.storageStrategyFree1gbDesc;
      default: return fallback;
    }
  }

  static const List<Color> _palette = [
    Color(0xFF2C7FEB),
    Color(0xFF00A870),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFEC4899),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFF64748B),
  ];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final summary = await StorageUsageService.getStorageUsageSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.storageAnalyzeFailed;
      });
    }
  }

  Future<void> _onClearCategory(StorageUsageCategory category) async {
    final olderThanDays = await _showClearOptionsDialog(category);
    if (olderThanDays == null) return;

    setState(() {
      _clearingCategoryId = category.id;
    });
    try {
      final result = await StorageUsageService.clearCategory(
        category.id,
        olderThanDays: olderThanDays > 0 ? olderThanDays : null,
      );
      if (!mounted) return;
      if (result.summary != null) {
        setState(() {
          _summary = result.summary;
        });
      } else {
        await _loadSummary(silent: true);
      }

      if (result.success) {
        showToast(
          context.l10n.storageCategoryCleaned(_catName(category.id, category.name), _formatBytes(result.releasedBytes)),
          type: ToastType.success,
        );
      } else {
        final rawHint = (result.manualActionHint ?? '').trim();
        final hint = _translateHint(rawHint);
        showToast(
          hint.isNotEmpty
              ? context.l10n.storageCleanPartialFailed(hint)
              : context.l10n.storageCleanPartialFailedGeneric,
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showToast(
        context.l10n.storageCleanFailed,
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearingCategoryId = null;
        });
      }
    }
  }

  Future<int?> _showClearOptionsDialog(StorageUsageCategory category) async {
    int selected = 0;
    final canRetention = category.riskLevel != 'dangerous';
    return showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                context.l10n.storageCleanCategory(_catName(category.id, category.name)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_catHint(category.id) ??
                      context.l10n.storageCleanConfirmMsg),
                  if (canRetention) ...[
                    const SizedBox(height: 12),
                    Text(context.l10n.storageCleanScope),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(context.l10n.storageCleanAll),
                          selected: selected == 0,
                          onSelected: (_) => setDialogState(() => selected = 0),
                        ),
                        ChoiceChip(
                          label: Text(context.l10n.storageClean7Days),
                          selected: selected == 7,
                          onSelected: (_) => setDialogState(() => selected = 7),
                        ),
                        ChoiceChip(
                          label: Text(context.l10n.storageClean30Days),
                          selected: selected == 30,
                          onSelected: (_) => setDialogState(() => selected = 30),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(context.trLegacy('取消')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: Text(context.l10n.storageClean),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _applyStrategy(StorageCleanupStrategyPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.storageStrategyName(_stratName(preset.id, preset.name))),
          content: Text(_stratDesc(preset.id, preset.description)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.trLegacy('取消')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.storageExecute),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _applyingStrategyId = preset.id;
    });
    try {
      final result = await StorageUsageService.applyCleanupStrategy(preset.id);
      if (!mounted) return;
      if (result.summary != null) {
        setState(() {
          _summary = result.summary;
        });
      } else {
        await _loadSummary(silent: true);
      }

      final failedCount = result.actionResults.where((item) => !item.success).length;
      if (failedCount == 0) {
        showToast(
          context.l10n.storageStrategyDone(_formatBytes(result.releasedBytes)),
          type: ToastType.success,
        );
      } else {
        showToast(
          context.l10n.storageStrategyPartialDone(failedCount, _formatBytes(result.releasedBytes)),
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showToast(context.l10n.storageStrategyFailed, type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _applyingStrategyId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CommonAppBar(title: context.l10n.storageUsageTitle, primary: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : summary == null
          ? _buildErrorView()
          : RefreshIndicator(
              onRefresh: _loadSummary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildOverviewCard(summary),
                  const SizedBox(height: 12),
                  _buildTrendCard(summary),
                  const SizedBox(height: 12),
                  _buildStrategyCard(summary),
                  const SizedBox(height: 12),
                  _buildPieCard(summary),
                  const SizedBox(height: 12),
                  _buildCategoryListCard(summary),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? context.l10n.storageLoadFailed, style: const TextStyle(color: AppColors.text70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loadSummary, child: Text(context.l10n.storageReanalyze)),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(StorageUsageSummary summary) {
    final sourceText = _metricsSourceText(summary.metricsSource);
    final hasBothTotals =
        summary.systemTotalBytes > 0 && summary.scanTotalBytes > 0;
    final diffBytes = summary.systemTotalBytes - summary.scanTotalBytes;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.storageTotalUsage, style: const TextStyle(fontSize: 12, color: AppColors.text70)),
          const SizedBox(height: 4),
          Text(
            _formatBytes(summary.totalBytes),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildMetricCell(context.l10n.storageAppSize, _formatBytes(summary.appBinaryBytes))),
              Expanded(child: _buildMetricCell(context.l10n.storageUserData, _formatBytes(summary.userDataBytes))),
              Expanded(child: _buildMetricCell(context.l10n.storageCleanable, _formatBytes(summary.cleanableBytes))),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.storageStatsSource(sourceText),
            style: const TextStyle(fontSize: 11, color: AppColors.text70),
          ),
          if (summary.packageName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              context.l10n.storagePackageName(summary.packageName),
              style: const TextStyle(fontSize: 11, color: AppColors.text70),
            ),
          ],
          if (hasBothTotals && diffBytes != 0) ...[
            const SizedBox(height: 2),
            Text(
              'System vs scan difference: ${_signedBytes(diffBytes)}',
              style: const TextStyle(fontSize: 11, color: AppColors.text70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendCard(StorageUsageSummary summary) {
    final trend = summary.trend;
    final totalDeltaText = _signedBytes(trend.deltaTotalBytes);
    final cleanableDeltaText = _signedBytes(trend.deltaCleanableBytes);
    final hasPrev = trend.hasPrevious;
    return _buildCard(
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Color(0xFF2C7FEB)),
          const SizedBox(width: 10),
          Expanded(
            child: hasPrev
                ? Text(
                    context.l10n.storageTrendVsLast(totalDeltaText, cleanableDeltaText),
                    style: const TextStyle(fontSize: 12, color: AppColors.text70),
                  )
                : Text(
                    context.l10n.storageTrendFirst,
                    style: const TextStyle(fontSize: 12, color: AppColors.text70),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyCard(StorageUsageSummary summary) {
    final presets = summary.strategyPresets;
    if (presets.isEmpty) {
      return const SizedBox.shrink();
    }
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.storageSmartCleanup,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...presets.map((preset) {
            final applying = _applyingStrategyId == preset.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stratName(preset.id, preset.name),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _stratDesc(preset.id, preset.description),
                          style: const TextStyle(fontSize: 12, color: AppColors.text70),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: applying ? null : () => _applyStrategy(preset),
                    child: applying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.l10n.storageExecute),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPieCard(StorageUsageSummary summary) {
    final categories = summary.categories.where((item) => item.bytes > 0).toList();
    final colorMap = _buildCategoryColorMap(summary.categories);
    final segments = _buildChartSegments(categories, colorMap);
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.storageUsageAnalysis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            context.l10n.storageLastAnalyzed(_formatDateTime(summary.generatedAt)),
            style: const TextStyle(fontSize: 12, color: AppColors.text70),
          ),
          const SizedBox(height: 12),
          Center(
            child: _StorageUsagePieChart(totalBytes: summary.totalBytes, segments: segments),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _loadSummary, child: Text(context.l10n.storageReanalyze)),
        ],
      ),
    );
  }

  Widget _buildCategoryListCard(StorageUsageSummary summary) {
    final categories = summary.categories.where((item) => item.bytes > 0).toList();
    final colorMap = _buildCategoryColorMap(summary.categories);
    return _buildCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: categories.map((category) {
          final percent = summary.totalBytes > 0
              ? category.bytes / summary.totalBytes * 100
              : 0.0;
          final isClearing = _clearingCategoryId == category.id;
          return Column(
            children: [
              ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colorMap[category.id] ?? const Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(_catName(category.id, category.name), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('${_catDesc(category.id, category.description)}\n${percent.toStringAsFixed(1)}%'),
                trailing: category.cleanable
                    ? TextButton(
                        onPressed: isClearing ? null : () => _onClearCategory(category),
                        child: isClearing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(context.l10n.storageClean),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 50, right: 16, bottom: 10),
                child: Row(
                  children: [
                    Text(
                      _formatBytes(category.bytes),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    _buildRiskTag(category.riskLevel),
                  ],
                ),
              ),
              if (category != categories.last)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  String _translateHint(String raw) {
    final l = context.l10n;
    if (raw.contains('历史未释放') || raw.contains('conversation_history')) return l.storageHintConversation;
    if (raw.contains('模型被清理后') || raw.contains('local_models')) return l.storageHintLocalModels;
    if (raw.contains('终端运行时被清理') || raw.contains('terminal')) return l.storageHintTerminal;
    if (raw.contains('当前不可清理')) return l.storageHintNotCleanable;
    if (raw.contains('已跳过') || raw.contains('skipped')) return l.storageHintSkipped;
    return l.storageHintGeneral;
  }

  Widget _buildCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildMetricCell(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: AppColors.text70)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildRiskTag(String riskLevel) {
    late final String text;
    late final Color bgColor;
    late final Color fgColor;
    switch (riskLevel) {
      case 'safe':
        text = context.l10n.storageRiskLow;
        bgColor = const Color(0xFFE6F8F0);
        fgColor = const Color(0xFF0E9F6E);
        break;
      case 'caution':
        text = context.l10n.storageRiskCaution;
        bgColor = const Color(0xFFFFF4E5);
        fgColor = const Color(0xFFB76E00);
        break;
      case 'dangerous':
        text = context.l10n.storageRiskHigh;
        bgColor = const Color(0xFFFFECEC);
        fgColor = const Color(0xFFCC3C3C);
        break;
      default:
        text = context.l10n.storageReadOnly;
        bgColor = const Color(0xFFF1F5F9);
        fgColor = const Color(0xFF475569);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, color: fgColor)),
    );
  }

  Map<String, Color> _buildCategoryColorMap(List<StorageUsageCategory> categories) {
    final colorMap = <String, Color>{};
    for (int index = 0; index < categories.length; index++) {
      colorMap[categories[index].id] = _palette[index % _palette.length];
    }
    return colorMap;
  }

  List<_PieChartSegment> _buildChartSegments(
    List<StorageUsageCategory> categories,
    Map<String, Color> colorMap,
  ) {
    final sorted = [...categories]..sort((a, b) => b.bytes.compareTo(a.bytes));
    if (sorted.length <= 7) {
      return sorted
          .map((item) => _PieChartSegment(_catName(item.id, item.name), item.bytes, colorMap[item.id] ?? const Color(0xFF94A3B8)))
          .toList();
    }
    final head = sorted.take(6).toList();
    final tailBytes = sorted.skip(6).fold<int>(0, (sum, item) => sum + item.bytes);
    return [
      ...head.map((item) => _PieChartSegment(_catName(item.id, item.name), item.bytes, colorMap[item.id] ?? const Color(0xFF94A3B8))),
      _PieChartSegment(context.l10n.storageCatOtherUserData, tailBytes, const Color(0xFF94A3B8)),
    ];
  }

  String _signedBytes(int bytes) {
    if (bytes == 0) return '0 B';
    final sign = bytes > 0 ? '+' : '-';
    return '$sign${_formatBytes(bytes.abs())}';
  }

  String _metricsSourceText(String source) {
    switch (source) {
      case 'system_storage_stats':
        return context.l10n.storageSystemStats;
      case 'filesystem_estimate':
      default:
        return context.l10n.storageDirectoryScan;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final fixed = size >= 100 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return '$fixed ${units[unitIndex]}';
  }

  String _formatDateTime(int timestampMs) {
    if (timestampMs <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _PieChartSegment {
  const _PieChartSegment(this.label, this.bytes, this.color);
  final String label;
  final int bytes;
  final Color color;
}

class _StorageUsagePieChart extends StatelessWidget {
  const _StorageUsagePieChart({required this.totalBytes, required this.segments});

  final int totalBytes;
  final List<_PieChartSegment> segments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(210, 210),
            painter: _StorageUsagePiePainter(segments: segments),
          ),
          Text(
            _formatBytes(totalBytes),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final fixed = size >= 100 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return '$fixed ${units[unitIndex]}';
  }
}

class _StorageUsagePiePainter extends CustomPainter {
  _StorageUsagePiePainter({required this.segments});
  final List<_PieChartSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;

    final total = segments.fold<int>(0, (sum, item) => sum + item.bytes);
    if (total <= 0) {
      paint.color = const Color(0xFFE2E8F0);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, paint);
      return;
    }
    double start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.bytes <= 0) continue;
      final sweep = segment.bytes / total * math.pi * 2;
      paint.color = segment.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StorageUsagePiePainter oldDelegate) {
    if (segments.length != oldDelegate.segments.length) return true;
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].bytes != oldDelegate.segments[i].bytes ||
          segments[i].color != oldDelegate.segments[i].color) {
        return true;
      }
    }
    return false;
  }
}
