import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ui/features/home/pages/chat/tool_activity_utils.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/terminal_output_utils.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/theme/app_colors.dart';

const ValueKey<String> kChatToolActivityBarKey = ValueKey<String>(
  'chat-tool-activity-bar',
);
const ValueKey<String> kChatToolActivityPanelKey = ValueKey<String>(
  'chat-tool-activity-panel',
);
const ValueKey<String> kChatToolActivityPreviewKey = ValueKey<String>(
  'chat-tool-activity-preview',
);
const ValueKey<String> kChatToolActivityToggleKey = ValueKey<String>(
  'chat-tool-activity-toggle',
);

const double _kToolActivityRowHeight = 46;
const double _kToolActivitySurfaceRadius = 18;
const double _kToolActivityPreviewWidth = 112;
const double _kToolActivityPreviewHeight = 62;
const double _kToolActivityPreviewDockDepth = 18;
const double _kToolActivityDrawerMaxHeight = 228;
const Color _kToolActivitySurfaceColor = Color(0xFFF9FCFF);

class ChatToolActivityStrip extends StatefulWidget {
  const ChatToolActivityStrip({
    super.key,
    required this.messages,
    this.anchorRect,
    this.onOccupiedHeightChanged,
  });

  final List<ChatMessageModel> messages;
  final Rect? anchorRect;
  final ValueChanged<double>? onOccupiedHeightChanged;

  @override
  State<ChatToolActivityStrip> createState() => _ChatToolActivityStripState();
}

class _ChatToolActivityStripState extends State<ChatToolActivityStrip> {
  bool _expanded = false;
  double? _lastReportedOccupiedHeight;

  @override
  Widget build(BuildContext context) {
    final cards = extractAgentToolCards(widget.messages);
    final activeCard = resolveActiveAgentToolCard(cards);
    if (activeCard == null) {
      _reportOccupiedHeight(0);
      return const SizedBox.shrink();
    }

    final activeCardId = _cardIdentity(activeCard);
    final historyCards = cards
        .where((card) => _cardIdentity(card) != activeCardId)
        .toList(growable: false);
    final canExpand = historyCards.isNotEmpty;
    final isExpanded = _expanded && canExpand;
    final transcript = buildAgentToolTranscript(cards);
    final title = resolveAgentToolTitle(activeCard);
    final currentIndex = math.max(
      1,
      cards.indexWhere((card) => _cardIdentity(card) == activeCardId) + 1,
    );
    final historyHeight = isExpanded
        ? _resolveHistoryHeight(historyCards)
        : 0.0;
    final dividerHeight = isExpanded ? 1.0 : 0.0;
    final surfaceHeight =
        _kToolActivityRowHeight + historyHeight + dividerHeight;
    final totalHeight =
        surfaceHeight +
        (!isExpanded
            ? _kToolActivityPreviewHeight - _kToolActivityPreviewDockDepth
            : 0.0);
    final collapsedLeadingInset = math.max(
      0.0,
      _kToolActivityPreviewWidth - 10,
    );
    _reportOccupiedHeight(totalHeight);

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutQuart,
      alignment: Alignment.bottomLeft,
      child: SizedBox(
        width: widget.anchorRect?.width ?? double.infinity,
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ActivityDrawerSurface(
                activeCard: activeCard,
                historyCards: historyCards,
                historyHeight: historyHeight,
                expanded: isExpanded,
                canExpand: canExpand,
                currentIndex: currentIndex,
                totalCount: cards.length,
                leadingInset: isExpanded ? 0 : collapsedLeadingInset,
                onToggle: () => setState(() => _expanded = !_expanded),
              ),
            ),
            Positioned(
              left: 0,
              bottom: _kToolActivityRowHeight - _kToolActivityPreviewDockDepth,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(-0.05, 0.12),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: isExpanded
                    ? const SizedBox.shrink(key: ValueKey('hidden-preview'))
                    : _TerminalThumbnail(
                        key: kChatToolActivityPreviewKey,
                        previewText: _buildPreviewText(activeCard),
                        transcript: transcript,
                        onTap: () => _openTranscriptDialog(
                          context,
                          transcript: transcript,
                          title: title,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ChatToolActivityStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.isEmpty && _lastReportedOccupiedHeight != 0) {
      _reportOccupiedHeight(0);
    }
  }

  String _cardIdentity(Map<String, dynamic> cardData) {
    final explicit = (cardData['cardId'] ?? '').toString().trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return [
      (cardData['taskId'] ?? '').toString(),
      (cardData['toolName'] ?? '').toString(),
      (cardData['toolTitle'] ?? '').toString(),
      (cardData['status'] ?? '').toString(),
    ].join('|');
  }

  String _buildPreviewText(Map<String, dynamic> activeCard) {
    final toolType = (activeCard['toolType'] ?? '').toString();
    if (toolType == 'terminal') {
      final output = resolveAgentToolTerminalOutput(activeCard).trim();
      if (output.isNotEmpty) {
        final lines = output
            .split('\n')
            .map((line) => line.trimRight())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
        if (lines.isNotEmpty) {
          final previewLines = lines.length > 4
              ? lines.sublist(lines.length - 4)
              : lines;
          return previewLines.join('\n');
        }
      }
    }

    final title = resolveAgentToolTitle(activeCard);
    final preview = resolveAgentToolPreview(activeCard);
    final meta = resolveAgentToolTypeLabel(activeCard);
    return [
      '\$ $title',
      '> $meta · $preview',
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  double _resolveHistoryHeight(List<Map<String, dynamic>> cards) {
    final visibleCount = cards.length.clamp(1, 5);
    final estimated =
        8 +
        (visibleCount * _kToolActivityRowHeight) +
        math.max(0, visibleCount - 1) +
        6;
    return math.min(_kToolActivityDrawerMaxHeight, estimated.toDouble());
  }

  void _reportOccupiedHeight(double height) {
    if (widget.onOccupiedHeightChanged == null) {
      return;
    }
    final normalized = height.isFinite ? height : 0.0;
    if (_lastReportedOccupiedHeight != null &&
        (_lastReportedOccupiedHeight! - normalized).abs() < 0.5) {
      return;
    }
    _lastReportedOccupiedHeight = normalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onOccupiedHeightChanged?.call(normalized);
    });
  }

  Future<void> _openTranscriptDialog(
    BuildContext context, {
    required String transcript,
    required String title,
  }) {
    final displayText = transcript.trim().isEmpty ? '\$ 暂无工具调用记录' : transcript;
    return showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 30,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.72,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1220),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF1E314F)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x6610182B),
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3FD08B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF2F7FF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF9FB0C8),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: SelectableText.rich(
                      AnsiTextSpanBuilder.build(
                        displayText,
                        const TextStyle(
                          color: Color(0xFFCBE3CF),
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityDrawerSurface extends StatelessWidget {
  const _ActivityDrawerSurface({
    required this.activeCard,
    required this.historyCards,
    required this.historyHeight,
    required this.expanded,
    required this.canExpand,
    required this.currentIndex,
    required this.totalCount,
    required this.leadingInset,
    required this.onToggle,
  });

  final Map<String, dynamic> activeCard;
  final List<Map<String, dynamic>> historyCards;
  final double historyHeight;
  final bool expanded;
  final bool canExpand;
  final int currentIndex;
  final int totalCount;
  final double leadingInset;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        key: kChatToolActivityBarKey,
        decoration: _surfaceDecoration(expanded: expanded),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 240),
              firstCurve: Curves.easeInCubic,
              secondCurve: Curves.easeOutCubic,
              sizeCurve: Curves.easeOutQuart,
              alignment: Alignment.bottomCenter,
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(
                key: ValueKey('collapsed-panel'),
              ),
              secondChild: SizedBox(
                height: historyHeight,
                child: _HistoryDrawer(cards: historyCards),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: expanded ? 1 : 0,
              margin: const EdgeInsets.only(left: 28, right: 14),
              color: const Color(0x140F2034),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canExpand ? onToggle : null,
              child: ToolActivityRow(
                card: activeCard,
                leadingInset: leadingInset,
                trailing: canExpand
                    ? _ActivityBarTrailing(
                        currentIndex: currentIndex,
                        totalCount: totalCount,
                        expanded: expanded,
                        onToggle: onToggle,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityBarTrailing extends StatelessWidget {
  const _ActivityBarTrailing({
    required this.currentIndex,
    required this.totalCount,
    required this.expanded,
    required this.onToggle,
  });

  final int currentIndex;
  final int totalCount;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: kChatToolActivityToggleKey,
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$currentIndex/$totalCount',
              style: const TextStyle(
                color: Color(0xFF66788F),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: expanded ? 0 : 0.5,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: Color(0xFF657891),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDrawer extends StatelessWidget {
  const _HistoryDrawer({required this.cards});

  final List<Map<String, dynamic>> cards;

  @override
  Widget build(BuildContext context) {
    final scrollable = cards.length > 4;
    return Container(
      key: kChatToolActivityPanelKey,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: scrollable
            ? const BouncingScrollPhysics(parent: ClampingScrollPhysics())
            : const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return ToolActivityRow(card: cards[index]);
        },
        separatorBuilder: (_, __) => Container(
          height: 1,
          margin: const EdgeInsets.only(left: 28, right: 14),
          color: const Color(0x140F2034),
        ),
        itemCount: cards.length,
      ),
    );
  }
}

class ToolActivityRow extends StatelessWidget {
  const ToolActivityRow({
    super.key,
    required this.card,
    this.leadingInset = 0,
    this.trailing,
  });

  final Map<String, dynamic> card;
  final double leadingInset;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final status = (card['status'] ?? 'running').toString();
    final meta =
        '${resolveAgentToolTypeLabel(card)} · ${resolveAgentToolStatusLabel(card)}';

    return SizedBox(
      height: _kToolActivityRowHeight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(14 + leadingInset, 0, 12, 0),
        child: Row(
          children: [
            _StatusDot(status: status),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                resolveAgentToolTitle(card),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF7C8DA5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _TerminalThumbnail extends StatelessWidget {
  const _TerminalThumbnail({
    super.key,
    required this.previewText,
    required this.transcript,
    required this.onTap,
  });

  final String previewText;
  final String transcript;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lines = _thumbnailText(previewText, transcript)
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final headline = lines.isEmpty ? '\$ idle' : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: _kToolActivityPreviewWidth,
          height: _kToolActivityPreviewHeight,
          padding: const EdgeInsets.fromLTRB(12, 10, 11, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D212B), Color(0xFF12161E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2C3240)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2B0B1220),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF4F7FB),
                  fontSize: 8.1,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    body,
                    maxLines: 3,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: Color(0xFF88EEA6),
                      fontSize: 7.1,
                      height: 1.16,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ] else
                const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  String _thumbnailText(String previewText, String transcript) {
    final preferred = previewText.trim();
    if (preferred.isNotEmpty) {
      return preferred;
    }
    final fallback = transcript.trim();
    if (fallback.isEmpty) {
      return '\$ idle';
    }
    final lines = fallback
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return '\$ idle';
    }
    final previewLines = lines.length > 4
        ? lines.sublist(lines.length - 4)
        : lines;
    return previewLines.join('\n');
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'success':
      return const Color(0xFF2F8F4E);
    case 'error':
      return AppColors.alertRed;
    case 'interrupted':
      return const Color(0xFFFFAA2C);
    default:
      return const Color(0xFF2C7FEB);
  }
}

BoxDecoration _surfaceDecoration({required bool expanded}) {
  return BoxDecoration(
    color: _kToolActivitySurfaceColor,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(_kToolActivitySurfaceRadius),
      topRight: Radius.circular(_kToolActivitySurfaceRadius),
    ),
    border: Border(
      left: BorderSide(color: const Color(0xFF102039).withValues(alpha: 0.06)),
      top: BorderSide(color: const Color(0xFF102039).withValues(alpha: 0.06)),
      right: BorderSide(color: const Color(0xFF102039).withValues(alpha: 0.06)),
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0x14111B2D).withValues(alpha: expanded ? 0.13 : 0.1),
        blurRadius: expanded ? 24 : 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
