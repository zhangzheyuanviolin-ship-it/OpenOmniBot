import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui/features/home/pages/chat/tool_activity_utils.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/agent_tool_transcript.dart';
import 'package:ui/l10n/generated/app_localizations.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';

const Color _interruptedStatusColor = Color(0xFFFFAA2C);

class AgentToolSummaryCard extends StatelessWidget {
  const AgentToolSummaryCard({
    super.key,
    required this.cardData,
    this.parentScrollController,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
  });

  final Map<String, dynamic> cardData;
  final ScrollController? parentScrollController;
  final AppBackgroundVisualProfile visualProfile;

  @override
  Widget build(BuildContext context) {
    final status = (cardData['status'] ?? 'running').toString();
    final title = resolveAgentToolTitle(cardData);
    final toolName = (cardData['toolName'] ?? '').toString().trim();
    String taskIdFromJson(String rawJson) {
      final text = rawJson.trim();
      if (text.isEmpty) {
        return '';
      }
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return (decoded['taskId'] ?? decoded['task_id'] ?? '')
              .toString()
              .trim();
        }
      } catch (_) {}
      return '';
    }

    final previewTaskId = taskIdFromJson(
      (cardData['resultPreviewJson'] ?? '').toString(),
    );
    final rawResultTaskId = taskIdFromJson(
      (cardData['rawResultJson'] ?? '').toString(),
    );
    final cachedToolTaskId = (cardData['toolTaskId'] ?? '').toString().trim();
    final taskId = toolName == 'vlm_task'
        ? (previewTaskId.isNotEmpty
              ? previewTaskId
              : (rawResultTaskId.isNotEmpty
                    ? rawResultTaskId
                    : cachedToolTaskId))
        : (cachedToolTaskId.isNotEmpty
              ? cachedToolTaskId
              : (previewTaskId.isNotEmpty ? previewTaskId : rawResultTaskId));
    final canViewRunLog =
        toolName == 'vlm_task' && status != 'running' && taskId.isNotEmpty;
    final statusLabel = resolveAgentToolStatusLabel(cardData);
    final preview = resolveAgentToolPreview(cardData);
    final typeLabel = resolveAgentToolTypeLabel(cardData);
    final statusColor = resolveAgentToolStatusColor(status);
    final compileStatus = (cardData['compileStatus'] ?? '').toString();
    final executionRoute = (cardData['executionRoute'] ?? '').toString();
    final routeLabel = _resolvedRouteLabel(
      executionRoute: executionRoute,
      compileStatus: compileStatus,
    );
    final palette = context.omniPalette;
    final utgBackgroundColor = _resolvedCardBackground(
      executionRoute: executionRoute,
      compileStatus: compileStatus,
      fallback: statusColor.withValues(alpha: 0.08),
    );
    final cardBackgroundColor = context.isDarkTheme
        ? Color.alphaBlend(
            statusColor.withValues(alpha: status == 'running' ? 0.11 : 0.09),
            palette.surfaceSecondary,
          )
        : utgBackgroundColor;
    final cardBorderColor = context.isDarkTheme
        ? Color.lerp(
            palette.borderSubtle,
            statusColor,
            0.18,
          )!.withValues(alpha: 0.92)
        : Colors.transparent;
    final statusTagBackgroundColor = context.isDarkTheme
        ? Color.alphaBlend(
            statusColor.withValues(alpha: 0.14),
            palette.surfaceElevated,
          )
        : Colors.white.withValues(alpha: 0.78);
    final statusTagTextColor = context.isDarkTheme
        ? Color.lerp(palette.textSecondary, statusColor, 0.38)!
        : statusColor;
    final titleColor = context.isDarkTheme
        ? palette.textPrimary
        : visualProfile.primaryTextColor;

    final tooltipLines = <String>[title];
    if (preview.isNotEmpty && preview != title) {
      tooltipLines.add(preview);
    }
    if (routeLabel != null) {
      tooltipLines.add(routeLabel);
    }

    final openRunLog = canViewRunLog
        ? () => _showVlmTaskRunLog(context, taskId: taskId, title: title)
        : null;

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
            minHeight: 34,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: openRunLog,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                margin: const EdgeInsets.only(top: 6, bottom: 2),
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                decoration: BoxDecoration(
                  color: cardBackgroundColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cardBorderColor),
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
                        style: TextStyle(
                          color: titleColor,
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
                        color: statusTagBackgroundColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status == 'running' ? typeLabel : statusLabel,
                        style: TextStyle(
                          color: statusTagTextColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                    if (canViewRunLog) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                        child: Text(
                          context.l10n.omniflowAssetView,
                          style: const TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
    late final Map<String, dynamic> payload;
    try {
      payload = await AssistsMessageService.getVlmTaskRunLog(taskId: taskId);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      final message = e.toString().trim();
      showToast(
        message.isEmpty ? context.l10n.omniflowAssetRunLogIndexFailed : message,
        type: ToastType.error,
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    final runId = (payload['run_id'] ?? '').toString().trim();
    if (runId.isEmpty) {
      final message = (payload['error_message'] ?? '').toString().trim();
      showToast(
        message.isEmpty ? context.l10n.omniflowAssetRunLogNotReady : message,
        type: ToastType.error,
      );
      return;
    }
    late final Map<String, dynamic> raw;
    late final Map<String, dynamic> view;
    try {
      final detail = await AssistsMessageService.getUtgRunLogDetail(
        runId: runId,
      );
      raw = detail.runLog;
      final rawView = detail.rawJson['view'];
      view = rawView is Map
          ? Map<String, dynamic>.from(
              rawView.map((key, value) => MapEntry(key.toString(), value)),
            )
          : const <String, dynamic>{};
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      final message = e.toString().trim();
      showToast(
        message.isEmpty ? context.l10n.omniflowAssetLoadFailed : message,
        type: ToastType.error,
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
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
                dialogContext,
                title: title,
                runId: runId,
                raw: raw,
                view: view,
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
    required Map<String, dynamic> view,
  }) {
    final viewSteps = (view['steps'] as List<dynamic>?) ?? const <dynamic>[];
    final success = view['success'] == true;
    final canImport = runId.isNotEmpty;
    final stepCount = view['step_count'] is num
        ? (view['step_count'] as num).toInt()
        : int.tryParse((view['step_count'] ?? '').toString()) ?? 0;
    final compileLabel = (view['compile_label'] ?? '').toString().trim().isEmpty
        ? context.l10n.omniflowAssetUnknown
        : (view['compile_label'] ?? '').toString().trim();
    final toolLabel = (view['tool_label'] ?? '').toString().trim();
    final toolName = toolLabel.isEmpty ? '-' : toolLabel;
    final summary = (view['summary'] ?? '').toString().trim();
    final goal = (view['goal'] ?? raw['goal'] ?? '').toString().trim();
    final finalPackage = (view['final_package'] ?? '').toString().trim().isEmpty
        ? 'unknown'
        : (view['final_package'] ?? '').toString().trim();
    final rawEmptyMessage = (view['empty_message'] ?? '').toString().trim();
    final emptyMessage = rawEmptyMessage.isNotEmpty
        ? rawEmptyMessage
        : context.l10n.omniflowAssetNoSteps;
    final prettyJson = const JsonEncoder.withIndent('  ').convert(view);
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
            _buildRunStatusPill(
              success,
              successLabel: context.l10n.omniflowAssetSuccess,
              failedLabel: context.l10n.omniflowAssetFailed,
            ),
            _buildRunDetailPill(context.l10n.omniflowAssetSteps(stepCount)),
            _buildRunDetailPill(compileLabel),
            _buildRunDetailPill(toolName),
          ],
        ),
        _buildInfoRow(context.l10n.omniflowAssetGoal, goal),
        _buildInfoRow(context.l10n.omniflowAssetStartedAt, (raw['started_at'] ?? '').toString()),
        _buildInfoRow(context.l10n.omniflowAssetDoneReason, (raw['done_reason'] ?? '').toString()),
        _buildInfoRow(context.l10n.omniflowAssetPackage, finalPackage),
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
                  Text(
                    context.l10n.omniflowAssetRunLogDetail,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: view.isEmpty
                        ? null
                        : () => _copyText(
                            context,
                            'JSON',
                            prettyJson,
                          ),
                    child: Text(context.l10n.omniflowAssetCopyJson),
                  ),
                ],
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (viewSteps.isEmpty)
                Text(
                  emptyMessage,
                  style: TextStyle(color: AppColors.text70, height: 1.6),
                )
              else
                ...viewSteps.asMap().entries.map((entry) {
                  final step = entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : const <String, dynamic>{};
                  final actions =
                      (step['actions'] as List<dynamic>?)
                          ?.map((item) => item.toString().trim())
                          .where((item) => item.isNotEmpty)
                          .toList() ??
                      const <String>[];
                  final stepSuccess = step['success'] != false;
                  final operationDescription =
                      (step['title'] ?? '').toString().trim().isEmpty
                      ? 'Step ${entry.key + 1}'
                      : (step['title'] ?? '').toString().trim();
                  final selectorLabel = ((step['selected_by'] ?? '').toString())
                      .trim();
                  final selectorReason = ((step['why'] ?? '').toString())
                      .trim();
                  final resultMessage = ((step['result'] ?? '').toString())
                      .trim();
                  final resultThought = ((step['thought'] ?? '').toString())
                      .trim();
                  final resultSummary = ((step['summary'] ?? '').toString())
                      .trim();
                  final errorText = ((step['error'] ?? '').toString()).trim();
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
                                'Step ${entry.key + 1} · $operationDescription',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildRunStatusPill(
                              stepSuccess,
                              successLabel: context.l10n.omniflowAssetSuccess,
                              failedLabel: context.l10n.omniflowAssetFailed,
                            ),
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
                        ...actions.asMap().entries.map(
                          (actionEntry) => Text(
                            'action ${actionEntry.key + 1}: ${actionEntry.value}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        ),
                        if (resultMessage.isNotEmpty)
                          Text(
                            'result: $resultMessage',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        if (resultThought.isNotEmpty)
                          Text(
                            'thought: $resultThought',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        if (resultSummary.isNotEmpty)
                          Text(
                            'summary: $resultSummary',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text70,
                              height: 1.5,
                            ),
                          ),
                        if (errorText.isNotEmpty)
                          Text(
                            'error: $errorText',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB42318),
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Text(
                'final package: $finalPackage',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text70,
                  height: 1.5,
                ),
              ),
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
                  onPressed: () => _copyText(context, 'ID', runId),
                  child: Text(context.l10n.omniflowAssetCopyId),
                ),
              FilledButton.icon(
                onPressed: !canImport
                    ? null
                    : () => _importRunLogToOmniFlow(context, runId: runId),
                icon: const Icon(Icons.psychology_alt_outlined),
                label: Text(context.l10n.omniflowAssetMemory),
              ),
              OutlinedButton.icon(
                onPressed: !canImport
                    ? null
                    : () => _replayRunLogViaOmniFlow(context, runId: runId),
                icon: const Icon(Icons.play_arrow_outlined),
                label: Text(context.l10n.omniflowAssetReplay),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.omniflowAssetClose),
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
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.memorySaveAsSkillTitle),
          content: Text(context.l10n.memorySaveAsSkillContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.omniflowCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.functionLibraryConfirm),
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
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(context.l10n.memorySavingProgress)),
            ],
          ),
        );
      },
    );
    loadingShown = true;
    try {
      final effectiveRunId = runId.trim();
      if (effectiveRunId.isEmpty) {
        throw Exception(context.l10n.memoryRunIdMissing);
      }
      final result = await AssistsMessageService.importUtgRunLog(
        runId: effectiveRunId,
      );
      if (!context.mounted) {
        return;
      }
      if (loadingShown) {
        Navigator.of(context).pop();
        loadingShown = false;
      }
      if (result.success) {
        final createdFunctionId = result.createdFunctionId.trim();
        // 先关闭当前弹窗
        Navigator.of(context).pop();
        // 显示成功弹窗
        if (context.mounted) {
          await _showSaveSuccessDialog(
            context,
            functionId: createdFunctionId,
          );
        }
      } else {
        showToast(
          result.errorMessage ?? context.l10n.memorySaveCannotImport,
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (context.mounted && loadingShown) {
        Navigator.of(context).pop();
        loadingShown = false;
      }
      if (!context.mounted) {
        return;
      }
      final message = e.toString().trim();
      showToast(
        message.isEmpty
            ? context.l10n.memorySaveFailed
            : context.l10n.memorySaveFailedWithMessage(message),
        type: ToastType.error,
      );
    }
  }

  Future<void> _showSaveSuccessDialog(
    BuildContext context, {
    required String functionId,
  }) async {
    final action = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF10B981),
              size: 32,
            ),
          ),
          title: Text(
            context.l10n.memorySaveSuccessSimple,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (functionId.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4FA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    functionId,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                context.l10n.memorySaveSuccessHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('close'),
              child: Text(context.l10n.omniflowAssetClose),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop('view'),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text(context.l10n.memoryViewInLibrary),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;

    if (action == 'view') {
      context.push('/task/function_library');
    }
  }

  Future<void> _replayRunLogViaOmniFlow(
    BuildContext context, {
    required String runId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.omniflowAssetReplayTitle),
          content: Text(context.l10n.omniflowAssetReplayConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.omniflowAssetCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.l10n.omniflowAssetConfirm),
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
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(context.l10n.omniflowAssetReplayProgress)),
            ],
          ),
        );
      },
    );
    loadingShown = true;
    try {
      final effectiveRunId = runId.trim();
      if (effectiveRunId.isEmpty) {
        throw Exception(context.l10n.omniflowAssetEmpty('run_id'));
      }
      final result = await AssistsMessageService.replayUtgRunLog(
        runId: effectiveRunId,
      );
      if (!context.mounted) {
        return;
      }
      if (loadingShown) {
        Navigator.of(context).pop();
        loadingShown = false;
      }
      final functionId = result.functionId.trim();
      final failureMessage = (result.errorMessage ?? '').trim();
      showToast(
        result.success
            ? (functionId.isEmpty
                  ? context.l10n.omniflowAssetReplaySuccess
                  : context.l10n.omniflowAssetReplaySuccessWithId(functionId))
            : (failureMessage.isNotEmpty
                  ? context.l10n.omniflowAssetReplayFailedWithMessage(failureMessage)
                  : context.l10n.omniflowAssetReplayFailed),
        type: result.success ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      if (context.mounted && loadingShown) {
        Navigator.of(context).pop();
        loadingShown = false;
      }
      if (!context.mounted) {
        return;
      }
      final message = e.toString().trim();
      showToast(
        message.isEmpty
            ? context.l10n.omniflowAssetReplayFailed
            : context.l10n.omniflowAssetReplayFailedWithMessage(message),
        type: ToastType.error,
      );
    }
  }

  Future<void> _copyText(
    BuildContext context,
    String label,
    String value,
  ) async {
    if (value.trim().isEmpty) {
      showToast(context.l10n.omniflowAssetEmpty(label), type: ToastType.error);
      return;
    }
    final copied = await AssistsMessageService.copyToClipboard(value);
    if (!context.mounted) {
      return;
    }
    showToast(
      copied
          ? context.l10n.omniflowAssetCopySuccess(label)
          : context.l10n.omniflowAssetCopyFailed(label),
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

Widget _buildRunStatusPill(bool success, {String? successLabel, String? failedLabel}) {
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
      success ? (successLabel ?? 'success') : (failedLabel ?? 'failed'),
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

String _actionDisplayName(String actionType, AppLocalizations l10n) {
  switch (actionType.trim()) {
    case 'open_app':
      return l10n.actionTypeOpenApp;
    case 'click':
      return l10n.actionTypeClick;
    case 'click_node':
      return l10n.actionTypeClickNode;
    case 'long_press':
      return l10n.actionTypeLongPress;
    case 'input_text':
      return l10n.actionTypeInputText;
    case 'swipe':
      return l10n.actionTypeSwipe;
    case 'press_key':
      return l10n.actionTypePressKey;
    case 'wait':
      return l10n.actionTypeWait;
    case 'finished':
      return l10n.actionTypeFinished;
    case 'call_function':
      return l10n.actionTypeCallFunction;
    default:
      return actionType.trim().isEmpty ? l10n.actionTypeDefault : actionType.trim();
  }
}

String _buildActionPreviewText(Map<String, dynamic> rawAction, AppLocalizations l10n) {
  final actionType = (rawAction['type'] ?? '').toString().trim();
  final label = _actionDisplayName(actionType, l10n);
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
    final color = resolveAgentToolStatusColor(status);
    final backgroundColor = context.isDarkTheme
        ? Color.alphaBlend(
            color.withValues(alpha: 0.14),
            context.omniPalette.surfaceElevated,
          )
        : color.withValues(alpha: 0.12);
    final iconColor = context.isDarkTheme
        ? Color.lerp(context.omniPalette.textSecondary, color, 0.38)!
        : color;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Center(
        child: status == 'running'
            ? SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                ),
              )
            : Icon(
                resolveAgentToolStatusIcon(status, (toolType ?? '').toString()),
                size: 10,
                color: iconColor,
              ),
      ),
    );
  }
}
