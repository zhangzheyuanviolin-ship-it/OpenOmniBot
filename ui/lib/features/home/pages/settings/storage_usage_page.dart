import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/storage_usage_service.dart';
import 'package:ui/theme/theme_context.dart';
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

  static const List<Color> _segmentPaletteLight = [
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

  static const List<Color> _segmentPaletteDark = [
    Color(0xFF6FA9FF),
    Color(0xFF66D4A4),
    Color(0xFFFFC766),
    Color(0xFFFF8E8E),
    Color(0xFFB9A1FF),
    Color(0xFF58D6CB),
    Color(0xFFFF96CD),
    Color(0xFF8F9BFF),
    Color(0xFFB6DD6F),
    Color(0xFF9AA4B2),
  ];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  String _t(BuildContext context, String zh, String en) {
    if (LegacyTextLocalizer.isEnglish) {
      return en;
    }
    return context.trLegacy(zh);
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
        _error = _t(
          context,
          '存储分析失败，请重试',
          'Storage analysis failed, please try again',
        );
      });
    }
  }

  Future<void> _onClearCategory(StorageUsageCategory category) async {
    final olderThanDays = await _showClearOptionsDialog(category);
    if (!mounted) return;
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
        if (!mounted) return;
      }

      if (result.success) {
        showToast(
          _t(
            context,
            '已清理 ${category.name}，释放 ${_formatBytes(result.releasedBytes)}',
            'Cleaned ${category.name}, freed ${_formatBytes(result.releasedBytes)}',
          ),
          type: ToastType.success,
        );
      } else {
        final hint = (result.manualActionHint ?? '').trim();
        showToast(
          hint.isNotEmpty
              ? _t(context, '部分清理失败：$hint', 'Some cleanup failed: $hint')
              : _t(
                  context,
                  '部分文件清理失败，请稍后重试',
                  'Some files failed to clean up, please try again later',
                ),
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showToast(
        _t(context, '清理失败，请稍后重试', 'Cleanup failed, please try again later'),
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
      builder: (dialogContext) {
        final palette = dialogContext.omniPalette;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: palette.surfacePrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                _t(
                  dialogContext,
                  '清理 ${category.name}',
                  'Clean ${category.name}',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.cleanupHint ??
                        _t(
                          dialogContext,
                          '确认清理该分类数据吗？',
                          'Confirm cleanup for this category?',
                        ),
                    style: TextStyle(color: palette.textSecondary),
                  ),
                  if (canRetention) ...[
                    const SizedBox(height: 12),
                    Text(
                      _t(dialogContext, '清理范围', 'Cleanup scope'),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(_t(dialogContext, '全部', 'All')),
                          selected: selected == 0,
                          onSelected: (_) => setDialogState(() => selected = 0),
                        ),
                        ChoiceChip(
                          label: Text(_t(dialogContext, '7天前', '7 days ago')),
                          selected: selected == 7,
                          onSelected: (_) => setDialogState(() => selected = 7),
                        ),
                        ChoiceChip(
                          label: Text(_t(dialogContext, '30天前', '30 days ago')),
                          selected: selected == 30,
                          onSelected: (_) =>
                              setDialogState(() => selected = 30),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: Text(_t(dialogContext, '取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: Text(_t(dialogContext, '确认清理', 'Confirm cleanup')),
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
      builder: (dialogContext) {
        final palette = dialogContext.omniPalette;
        return AlertDialog(
          backgroundColor: palette.surfacePrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            _t(
              dialogContext,
              '执行策略：${preset.name}',
              'Run strategy: ${preset.name}',
            ),
          ),
          content: Text(
            preset.description,
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t(dialogContext, '取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t(dialogContext, '开始执行', 'Run')),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
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
        if (!mounted) return;
      }

      final failedCount = result.actionResults
          .where((item) => !item.success)
          .length;
      if (failedCount == 0) {
        showToast(
          _t(
            context,
            '策略执行完成，释放 ${_formatBytes(result.releasedBytes)}',
            'Cleanup strategy completed, freed ${_formatBytes(result.releasedBytes)}',
          ),
          type: ToastType.success,
        );
      } else {
        showToast(
          _t(
            context,
            '策略执行完成，释放 ${_formatBytes(result.releasedBytes)}，$failedCount 项未完全成功',
            'Cleanup strategy finished, freed ${_formatBytes(result.releasedBytes)}, $failedCount actions were incomplete',
          ),
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showToast(
        _t(
          context,
          '策略执行失败，请稍后重试',
          'Cleanup strategy failed, please try again later',
        ),
        type: ToastType.error,
      );
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
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: CommonAppBar(
        title: _t(context, '存储占用', 'Storage Usage'),
        primary: true,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  palette.accentPrimary,
                ),
              ),
            )
          : summary == null
          ? _buildErrorView()
          : RefreshIndicator(
              color: palette.accentPrimary,
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
    final palette = context.omniPalette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error ?? _t(context, '加载失败', 'Load failed'),
            style: TextStyle(color: palette.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadSummary,
            child: Text(_t(context, '重新分析', 'Analyze again')),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(StorageUsageSummary summary) {
    final palette = context.omniPalette;
    final sourceText = _metricsSourceText(summary.metricsSource);
    final hasBothTotals =
        summary.systemTotalBytes > 0 && summary.scanTotalBytes > 0;
    final diffBytes = summary.systemTotalBytes - summary.scanTotalBytes;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, '总占用', 'Total usage'),
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            _formatBytes(summary.totalBytes),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCell(
                  _t(context, '应用大小', 'App size'),
                  _formatBytes(summary.appBinaryBytes),
                ),
              ),
              Expanded(
                child: _buildMetricCell(
                  _t(context, '用户数据', 'User data'),
                  _formatBytes(summary.userDataBytes),
                ),
              ),
              Expanded(
                child: _buildMetricCell(
                  _t(context, '可清理', 'Cleanable'),
                  _formatBytes(summary.cleanableBytes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t(context, '统计口径：$sourceText', 'Metrics source: $sourceText'),
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
          if (summary.packageName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _t(
                context,
                '当前包名：${summary.packageName}',
                'Package: ${summary.packageName}',
              ),
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
          ],
          if (hasBothTotals && diffBytes != 0) ...[
            const SizedBox(height: 2),
            Text(
              _t(
                context,
                '系统口径与扫描口径差异：${_signedBytes(diffBytes)}',
                'Delta between system and scan totals: ${_signedBytes(diffBytes)}',
              ),
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendCard(StorageUsageSummary summary) {
    final palette = context.omniPalette;
    final trend = summary.trend;
    final totalDeltaText = _signedBytes(trend.deltaTotalBytes);
    final cleanableDeltaText = _signedBytes(trend.deltaCleanableBytes);
    return _buildCard(
      child: Row(
        children: [
          Icon(Icons.trending_up, color: palette.accentPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: trend.hasPrevious
                ? Text(
                    _t(
                      context,
                      '较上次分析：总占用 $totalDeltaText，可清理 $cleanableDeltaText',
                      'Since last analysis: total $totalDeltaText, cleanable $cleanableDeltaText',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  )
                : Text(
                    _t(
                      context,
                      '这是首次分析，后续将展示占用变化趋势',
                      'This is the first analysis. Trend data will appear next time.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyCard(StorageUsageSummary summary) {
    final palette = context.omniPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final presets = summary.strategyPresets;
    if (presets.isEmpty) {
      return const SizedBox.shrink();
    }
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, '智能清理策略', 'Cleanup strategies'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
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
                          preset.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preset.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: palette.accentPrimary,
                      disabledBackgroundColor: palette.borderStrong,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    onPressed: applying ? null : () => _applyStrategy(preset),
                    child: applying
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : Text(_t(context, '执行', 'Run')),
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
    final palette = context.omniPalette;
    final categories = summary.categories
        .where((item) => item.bytes > 0)
        .toList();
    final colorMap = _buildCategoryColorMap(summary.categories);
    final segments = _buildChartSegments(categories, colorMap);
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, '占用分析', 'Usage breakdown'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              context,
              '最后分析：${_formatDateTime(summary.generatedAt)}',
              'Analyzed at: ${_formatDateTime(summary.generatedAt)}',
            ),
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 12),
          Center(
            child: _StorageUsagePieChart(
              totalBytes: summary.totalBytes,
              segments: segments,
              trackColor: palette.segmentTrack,
              centerTextColor: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadSummary,
            child: Text(_t(context, '重新分析', 'Analyze again')),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryListCard(StorageUsageSummary summary) {
    final palette = context.omniPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final categories = summary.categories.toList();
    final colorMap = _buildCategoryColorMap(summary.categories);
    if (categories.isEmpty) {
      return _buildCard(
        child: Text(
          _t(context, '暂无可展示数据', 'No storage data available'),
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
      );
    }
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
                    color: colorMap[category.id] ?? palette.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  category.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${category.description}\n${_t(context, '占比', 'Share')} ${percent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: palette.textSecondary,
                  ),
                ),
                trailing: category.cleanable
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          backgroundColor: palette.accentPrimary,
                          disabledBackgroundColor: palette.borderStrong,
                          foregroundColor: colorScheme.onPrimary,
                        ),
                        onPressed: isClearing
                            ? null
                            : () => _onClearCategory(category),
                        child: isClearing
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : Text(_t(context, '清理', 'Clean')),
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 50, right: 16, bottom: 10),
                child: Row(
                  children: [
                    Text(
                      _formatBytes(category.bytes),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildRiskTag(category.riskLevel),
                  ],
                ),
              ),
              if (category.breakdown.isNotEmpty)
                _buildCategoryBreakdown(category.breakdown),
              if (category != categories.last)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: palette.borderSubtle.withValues(
                    alpha: context.isDarkTheme ? 0.56 : 0.8,
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCard({required Widget child, EdgeInsetsGeometry? padding}) {
    final palette = context.omniPalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.borderSubtle.withValues(
            alpha: context.isDarkTheme ? 0.6 : 0.86,
          ),
        ),
        boxShadow: context.isDarkTheme
            ? null
            : [
                BoxShadow(
                  color: palette.shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildMetricCell(String title, String value) {
    final palette = context.omniPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 12, color: palette.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown(List<StorageUsageBreakdownEntry> entries) {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.only(left: 50, right: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'Native 库 Top 明细', 'Top native libs'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ...entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${entry.label} · ${_formatBytes(entry.bytes)}',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: palette.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRiskTag(String riskLevel) {
    final isDark = context.isDarkTheme;
    late final String text;
    late final Color bgColor;
    late final Color fgColor;
    switch (riskLevel) {
      case 'safe':
        text = _t(context, '低风险', 'Low risk');
        bgColor = isDark ? const Color(0xFF1D4C38) : const Color(0xFFE6F8F0);
        fgColor = isDark ? const Color(0xFF7CE2B4) : const Color(0xFF0E9F6E);
        break;
      case 'caution':
        text = _t(context, '谨慎', 'Caution');
        bgColor = isDark ? const Color(0xFF4E3C1E) : const Color(0xFFFFF4E5);
        fgColor = isDark ? const Color(0xFFFFD37A) : const Color(0xFFB76E00);
        break;
      case 'dangerous':
        text = _t(context, '高风险', 'High risk');
        bgColor = isDark ? const Color(0xFF4C2225) : const Color(0xFFFFECEC);
        fgColor = isDark ? const Color(0xFFFF9A9A) : const Color(0xFFCC3C3C);
        break;
      default:
        text = _t(context, '只读', 'Read-only');
        bgColor = isDark ? const Color(0xFF2B3138) : const Color(0xFFF1F5F9);
        fgColor = isDark ? const Color(0xFFB0BCCB) : const Color(0xFF475569);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fgColor.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: fgColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Map<String, Color> _buildCategoryColorMap(
    List<StorageUsageCategory> categories,
  ) {
    final palette = context.isDarkTheme
        ? _segmentPaletteDark
        : _segmentPaletteLight;
    final colorMap = <String, Color>{};
    for (int index = 0; index < categories.length; index++) {
      colorMap[categories[index].id] = palette[index % palette.length];
    }
    return colorMap;
  }

  List<_PieChartSegment> _buildChartSegments(
    List<StorageUsageCategory> categories,
    Map<String, Color> colorMap,
  ) {
    final fallbackColor = context.isDarkTheme
        ? const Color(0xFF9AA4B2)
        : const Color(0xFF94A3B8);
    final sorted = [...categories]..sort((a, b) => b.bytes.compareTo(a.bytes));
    if (sorted.length <= 7) {
      return sorted.map((item) {
        return _PieChartSegment(
          item.name,
          item.bytes,
          colorMap[item.id] ?? fallbackColor,
        );
      }).toList();
    }
    final head = sorted.take(6).toList();
    final tailBytes = sorted
        .skip(6)
        .fold<int>(0, (sum, item) => sum + item.bytes);
    return [
      ...head.map(
        (item) => _PieChartSegment(
          item.name,
          item.bytes,
          colorMap[item.id] ?? fallbackColor,
        ),
      ),
      _PieChartSegment(_t(context, '其他', 'Others'), tailBytes, fallbackColor),
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
        return _t(
          context,
          '系统统计（与系统设置更接近）',
          'System stats (closer to Settings)',
        );
      case 'filesystem_estimate':
      default:
        return _t(context, '目录扫描估算', 'Directory scan estimate');
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
    final fixed = size >= 100
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
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
  const _StorageUsagePieChart({
    required this.totalBytes,
    required this.segments,
    required this.trackColor,
    required this.centerTextColor,
  });

  final int totalBytes;
  final List<_PieChartSegment> segments;
  final Color trackColor;
  final Color centerTextColor;

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
            painter: _StorageUsagePiePainter(
              segments: segments,
              trackColor: trackColor,
            ),
          ),
          Text(
            _formatBytes(totalBytes),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: centerTextColor,
            ),
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
    final fixed = size >= 100
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(1);
    return '$fixed ${units[unitIndex]}';
  }
}

class _StorageUsagePiePainter extends CustomPainter {
  _StorageUsagePiePainter({required this.segments, required this.trackColor});

  final List<_PieChartSegment> segments;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.butt;

    paint.color = trackColor;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, paint);

    final total = segments.fold<int>(0, (sum, item) => sum + item.bytes);
    if (total <= 0) {
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
    if (trackColor != oldDelegate.trackColor) return true;
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
