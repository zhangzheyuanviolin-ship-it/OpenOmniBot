import 'package:flutter/material.dart';
import 'package:ui/features/home/pages/chat/tool_activity_utils.dart';
import 'package:ui/theme/app_colors.dart';

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
    final statusLabel = resolveAgentToolStatusLabel(cardData);
    final preview = resolveAgentToolPreview(cardData);
    final typeLabel = resolveAgentToolTypeLabel(cardData);
    final statusColor = _resolvedStatusColor(status);

    final tooltipLines = <String>[title];
    if (preview.isNotEmpty && preview != title) {
      tooltipLines.add(preview);
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
              color: statusColor.withValues(alpha: 0.08),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
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
