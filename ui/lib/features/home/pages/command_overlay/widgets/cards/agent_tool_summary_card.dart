import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ui/features/home/pages/chat/tool_activity_utils.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';

const Color _interruptedStatusColor = Color(0xFFFFAA2C);

class AgentToolSummaryCard extends StatelessWidget {
  const AgentToolSummaryCard({
    super.key,
    required this.cardData,
    this.parentScrollController,
  });

  final Map<String, dynamic> cardData;
  final ScrollController? parentScrollController;

  @override
  Widget build(BuildContext context) {
    final status = (cardData['status'] ?? 'running').toString();
    final title = resolveAgentToolTitle(cardData);
    final toolName = (cardData['toolName'] ?? '').toString().trim();
    var taskId = (cardData['toolTaskId'] ?? '').toString().trim();
    if (taskId.isEmpty) {
      final previewJson = (cardData['resultPreviewJson'] ?? '')
          .toString()
          .trim();
      if (previewJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(previewJson);
          if (decoded is Map) {
            taskId = (decoded['taskId'] ?? decoded['task_id'] ?? '')
                .toString()
                .trim();
          }
        } catch (_) {}
      }
    }
    if (taskId.isEmpty) {
      final rawResultJson = (cardData['rawResultJson'] ?? '').toString().trim();
      if (rawResultJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawResultJson);
          if (decoded is Map) {
            taskId = (decoded['taskId'] ?? decoded['task_id'] ?? '')
                .toString()
                .trim();
          }
        } catch (_) {}
      }
    }
    final canViewRunLog =
        toolName == 'vlm_task' && status != 'running' && taskId.isNotEmpty;
    final statusLabel = resolveAgentToolStatusLabel(cardData);
    final preview = resolveAgentToolPreview(cardData);
    final typeLabel = resolveAgentToolTypeLabel(cardData);
    final statusColor = _resolvedStatusColor(status);
    final compileStatus = (cardData['compileStatus'] ?? '').toString();
    final executionRoute = (cardData['executionRoute'] ?? '').toString();
    final routeLabel = _resolvedRouteLabel(
      executionRoute: executionRoute,
      compileStatus: compileStatus,
    );
    final backgroundColor = _resolvedCardBackground(
      executionRoute: executionRoute,
      compileStatus: compileStatus,
      fallback: statusColor.withValues(alpha: 0.08),
    );

    final tooltipLines = <String>[title];
    if (preview.isNotEmpty && preview != title) {
      tooltipLines.add(preview);
    }
    if (routeLabel != null) {
      tooltipLines.add(routeLabel);
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
            minHeight: 34,
          ),
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 2),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusIcon(status: status, toolType: cardData['toolType']),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ),
                if (routeLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _resolvedRouteColor(
                        executionRoute: executionRoute,
                        compileStatus: compileStatus,
                      ).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      routeLabel,
                      style: TextStyle(
                        color: _resolvedRouteColor(
                          executionRoute: executionRoute,
                          compileStatus: compileStatus,
                        ),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status == 'running' ? typeLabel : statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
                if (canViewRunLog) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _showVlmTaskRunLog(
                      context,
                      taskId: taskId,
                      title: title,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        '查看',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showVlmTaskRunLog(
    BuildContext context, {
    required String taskId,
    required String title,
  }) async {
    final payload = await AssistsMessageService.getVlmTaskRunLog(
      taskId: taskId,
    );
    if (!context.mounted) {
      return;
    }
    final runId = (payload['run_id'] ?? '').toString().trim();
    var raw = <String, dynamic>{};
    if (runId.isNotEmpty) {
      try {
        final detail = await AssistsMessageService.getUtgRunLogDetail(
          runId: runId,
        );
        raw = detail.runLog;
      } catch (_) {
        final runLog = payload['run_log'];
        raw = runLog is Map<String, dynamic>
            ? runLog
            : runLog is Map
            ? Map<String, dynamic>.from(runLog)
            : <String, dynamic>{};
      }
    } else {
      final runLog = payload['run_log'];
      raw = runLog is Map<String, dynamic>
          ? runLog
          : runLog is Map
          ? Map<String, dynamic>.from(runLog)
          : <String, dynamic>{};
    }
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildRunLogPopupCard(
                context,
                title: title,
                runId: runId,
                raw: raw,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRunLogPopupCard(
    BuildContext context, {
    required String title,
    required String runId,
    required Map<String, dynamic> raw,
  }) {
    final extra =
        (raw['extra'] as Map<dynamic, dynamic>?) ?? const <dynamic, dynamic>{};
    final finalObservation =
        (raw['final_observation'] as Map<dynamic, dynamic>?) ??
        const <dynamic, dynamic>{};
    final steps = (raw['steps'] as List<dynamic>?) ?? const <dynamic>[];
    final success = raw['success'] == true;
    final compileKind = (extra['compile_kind'] ?? '').toString().trim();
    final compileLabel = compileKind.isEmpty
        ? 'compile unknown'
        : 'compile $compileKind';
    final toolName = steps.isEmpty
        ? '无 tool'
        : (((steps.first as Map)['plan'] as Map?)?['tool_name'] ?? '')
              .toString()
              .trim()
              .isEmpty
        ? '无 tool'
        : (((steps.first as Map)['plan'] as Map?)?['tool_name'] ?? '')
              .toString()
              .trim();
    final prettyJson = const JsonEncoder.withIndent('  ').convert(raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        if (runId.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(
            runId,
            style: const TextStyle(fontSize: 12, color: AppColors.text70),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildRunStatusPill(success),
            _buildRunDetailPill('${steps.length} steps'),
            _buildRunDetailPill(compileLabel),
            _buildRunDetailPill(toolName.isEmpty ? '无 tool' : toolName),
          ],
        ),
        _buildInfoRow('started_at', (raw['started_at'] ?? '').toString()),
        _buildInfoRow('done_reason', (raw['done_reason'] ?? '').toString()),
        if ((finalObservation['package_name'] ?? '')
            .toString()
            .trim()
            .isNotEmpty)
          _buildInfoRow(
            'final_package',
            (finalObservation['package_name'] ?? '').toString(),
          ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Run Log 详情',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: raw.isEmpty
                        ? null
                        : () => _copyText(context, 'run log json', prettyJson),
                    child: const Text('复制 JSON'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if ((extra['source'] ?? '').toString().trim().isNotEmpty)
                Text(
                  'source: ${(extra['source'] ?? '').toString()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text70,
                    height: 1.5,
                  ),
                ),
              if (extra['stabilization_wait_ms'] != null)
                Text(
                  'stabilization_wait_ms: ${extra['stabilization_wait_ms']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text70,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 12),
              if (steps.isEmpty)
                const Text(
                  '这个 run_log 没有记录到 step。常见原因是任务在首轮观察前失败或被中断。',
                  style: TextStyle(color: AppColors.text70, height: 1.6),
                )
              else
                ...steps.asMap().entries.map((entry) {
                  final step = entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : const <String, dynamic>{};
                  final plan =
                      (step['plan'] as Map<dynamic, dynamic>?) ??
                      const <dynamic, dynamic>{};
                  final actResult =
                      (step['act_result'] as Map<dynamic, dynamic>?) ??
                      const <dynamic, dynamic>{};
                  final resultSummary =
                      (actResult['result_summary'] as Map<dynamic, dynamic>?) ??
                      const <dynamic, dynamic>{};
                  final executedActions =
                      (step['executed_actions'] as List<dynamic>?)
                          ?.whereType<Map>()
                          .map(
                            (item) => _buildActionPreviewText(
                              Map<String, dynamic>.from(item),
                            ).trim(),
                          )
                          .where((item) => item.isNotEmpty)
                          .toList() ??
                      const <String>[];
                  final operationDescription =
                      ((step['operation_description'] ??
                                  plan['description'] ??
                                  plan['tool_name'] ??
                                  '')
                              .toString())
                          .trim();
                  final selectorLabel =
                      ((step['selector_label'] ?? '').toString()).trim();
                  final selectorReason =
                      ((step['selector_reason'] ?? '').toString()).trim();
                  final stepSuccess = actResult['success'] != false;
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E8EE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Step ${entry.key + 1} · ${operationDescription.isEmpty ? '未记录动作' : operationDescription}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildRunStatusPill(stepSuccess),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (selectorLabel.isNotEmpty)
                          Text(
                            'selected_by: $selectorLabel',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        if (selectorReason.isNotEmpty)
                          Text(
                            'why: $selectorReason',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        ...executedActions.asMap().entries.map(
                          (actionEntry) => Text(
                            'action ${actionEntry.key + 1}: ${actionEntry.value}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        ),
                        if (((resultSummary['message'] ?? '').toString())
                            .trim()
                            .isNotEmpty)
                          Text(
                            'result: ${(resultSummary['message'] ?? '').toString()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        if (((resultSummary['thought'] ?? '').toString())
                            .trim()
                            .isNotEmpty)
                          Text(
                            'thought: ${(resultSummary['thought'] ?? '').toString()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        if (((resultSummary['summary'] ?? '').toString())
                            .trim()
                            .isNotEmpty)
                          Text(
                            'summary: ${(resultSummary['summary'] ?? '').toString()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Text(
                'final package: ${(finalObservation['package_name'] ?? '').toString().trim().isEmpty ? 'unknown' : (finalObservation['package_name'] ?? '').toString()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text70,
                  height: 1.5,
                ),
              ),
              if ((finalObservation['xml'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE4E8EE)),
                  ),
                  child: SelectableText(
                    (finalObservation['xml'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text70,
                      height: 1.5,
                    ),
                    maxLines: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (runId.isNotEmpty)
                OutlinedButton(
                  onPressed: () => _copyText(context, 'run_id', runId),
                  child: const Text('复制 run_id'),
                ),
              FilledButton.icon(
                onPressed: runId.isEmpty
                    ? null
                    : () => _importRunLogToOmniFlow(context, runId: runId),
                icon: const Icon(Icons.psychology_alt_outlined),
                label: const Text('记忆'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importRunLogToOmniFlow(
    BuildContext context, {
    required String runId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('记忆到 OmniFlow'),
          content: const Text(
            '是否确定将这次执行记录记忆到 OmniFlow 临时区？\n\n后续可在 OmniFlow 轨迹执行页继续沉淀为可 compile 资产。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    var loadingShown = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('正在整理执行记录并写入 OmniFlow 临时区...')),
            ],
          ),
        );
      },
    );
    loadingShown = true;
    try {
      final result = await AssistsMessageService.importUtgRunLog(runId: runId);
      if (!context.mounted) {
        return;
      }
      if (loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (result.success) {
        final createdPathId = result.createdPathId.trim();
        final zoneLabel = result.assetState.trim().isEmpty
            ? '临时区'
            : result.assetState.trim();
        showToast(
          createdPathId.isEmpty
              ? '已记忆到 OmniFlow $zoneLabel'
              : '已记忆到 OmniFlow $zoneLabel：$createdPathId',
          type: ToastType.success,
        );
      } else {
        showToast(
          result.errorMessage ?? '该 run_log 不能记忆到 OmniFlow',
          type: ToastType.error,
        );
      }
    } catch (_) {
      if (context.mounted && loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (!context.mounted) {
        return;
      }
      showToast('记忆到 OmniFlow 失败', type: ToastType.error);
    }
  }

  Future<void> _copyText(
    BuildContext context,
    String label,
    String value,
  ) async {
    if (value.trim().isEmpty) {
      showToast('$label 为空', type: ToastType.error);
      return;
    }
    final copied = await AssistsMessageService.copyToClipboard(value);
    if (!context.mounted) {
      return;
    }
    showToast(
      copied ? '$label 已复制' : '$label 复制失败',
      type: copied ? ToastType.success : ToastType.error,
    );
  }
}

String? _resolvedRouteLabel({
  required String executionRoute,
  required String compileStatus,
}) {
  if (executionRoute == 'utg' || compileStatus == 'hit') {
    return 'OmniFlow';
  }
  if (executionRoute == 'vlm' && compileStatus == 'miss') {
    return 'VLM';
  }
  return null;
}

Color _resolvedRouteColor({
  required String executionRoute,
  required String compileStatus,
}) {
  if (executionRoute == 'utg' || compileStatus == 'hit') {
    return const Color(0xFF2F8F4E);
  }
  return AppColors.primaryBlue;
}

Color _resolvedCardBackground({
  required String executionRoute,
  required String compileStatus,
  required Color fallback,
}) {
  if (executionRoute == 'utg' || compileStatus == 'hit') {
    return const Color(0xFFEAF7EE);
  }
  if (executionRoute == 'vlm' && compileStatus == 'miss') {
    return const Color(0xFFEAF2FF);
  }
  return fallback;
}

Widget _buildRunStatusPill(bool success) {
  final color = success ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
  final background = success
      ? const Color(0xFFE7F8ED)
      : const Color(0xFFFDECEC);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      success ? 'success' : 'failed',
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

Widget _buildRunDetailPill(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4FA),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.text70,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Widget _buildInfoRow(String label, String value) {
  if (value.trim().isEmpty) {
    return const SizedBox.shrink();
  }
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.text70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

String _actionDisplayName(String actionType) {
  switch (actionType.trim()) {
    case 'open_app':
      return '打开应用';
    case 'click':
      return 'click';
    case 'click_node':
      return 'click_node';
    case 'long_press':
      return '长按';
    case 'input_text':
      return '输入文本';
    case 'swipe':
      return '滑动';
    case 'press_key':
      return '按键';
    case 'wait':
      return '等待';
    case 'finished':
      return '结束';
    default:
      return actionType.trim().isEmpty ? '动作' : actionType.trim();
  }
}

String _buildActionPreviewText(Map<String, dynamic> rawAction) {
  final actionType = (rawAction['type'] ?? '').toString().trim();
  final label = _actionDisplayName(actionType);
  final params = (rawAction['params'] as Map<dynamic, dynamic>?) ?? const {};
  final packageName =
      (rawAction['packageName'] ??
              rawAction['package_name'] ??
              params['packageName'] ??
              params['package_name'] ??
              '')
          .toString()
          .trim();
  final textValue = (rawAction['text'] ?? params['text'] ?? '')
      .toString()
      .trim();
  final keyValue = (rawAction['key'] ?? params['key'] ?? '').toString().trim();
  final directionValue = (rawAction['direction'] ?? params['direction'] ?? '')
      .toString()
      .trim();
  final xValue = rawAction['x'] ?? params['x'];
  final yValue = rawAction['y'] ?? params['y'];
  final targetDescription =
      (rawAction['targetDescription'] ??
              rawAction['target_description'] ??
              params['targetDescription'] ??
              params['target_description'] ??
              '')
          .toString()
          .trim();
  if (actionType == 'click') {
    if (xValue != null && yValue != null) {
      return 'click ($xValue, $yValue)';
    }
    if (targetDescription.isNotEmpty) {
      return 'click $targetDescription';
    }
    return 'click';
  }
  if (packageName.isNotEmpty) {
    return '$label($packageName)';
  }
  if (textValue.isNotEmpty) {
    return '$label($textValue)';
  }
  if (keyValue.isNotEmpty) {
    return '$label($keyValue)';
  }
  if (directionValue.isNotEmpty) {
    return '$label($directionValue)';
  }
  return label;
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.toolType});

  final String status;
  final dynamic toolType;

  @override
  Widget build(BuildContext context) {
    final color = _resolvedStatusColor(status);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: status == 'running'
            ? SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Icon(
                _resolvedStatusIcon(status, (toolType ?? '').toString()),
                size: 10,
                color: color,
              ),
      ),
    );
  }
}

IconData _resolvedStatusIcon(String status, String toolType) {
  if (status == 'interrupted') {
    return Icons.stop_circle_outlined;
  }
  if (status == 'error') {
    return Icons.error_outline_rounded;
  }
  if (toolType == 'terminal') {
    return Icons.terminal_rounded;
  }
  if (toolType == 'browser') {
    return Icons.language_rounded;
  }
  if (toolType == 'calendar') {
    return Icons.calendar_month_rounded;
  }
  if (toolType == 'alarm' || toolType == 'schedule') {
    return Icons.alarm_rounded;
  }
  if (toolType == 'memory') {
    return Icons.psychology_alt_rounded;
  }
  if (toolType == 'workspace') {
    return Icons.folder_outlined;
  }
  if (toolType == 'subagent') {
    return Icons.hub_outlined;
  }
  if (toolType == 'mcp') {
    return Icons.extension_outlined;
  }
  return Icons.check_circle_outline_rounded;
}

Color _resolvedStatusColor(String status) {
  if (status == 'interrupted') {
    return _interruptedStatusColor;
  }
  switch (status) {
    case 'success':
      return const Color(0xFF2F8F4E);
    case 'error':
      return AppColors.alertRed;
    default:
      return AppColors.primaryBlue;
  }
}
