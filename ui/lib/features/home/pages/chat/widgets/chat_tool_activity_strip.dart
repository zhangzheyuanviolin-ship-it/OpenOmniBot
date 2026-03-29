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

const double _kToolActivityRowHeight = 32;
const double _kToolActivitySurfaceRadius = 18;
const double _kToolActivityPreviewWidth = 102;
const double _kToolActivityPreviewHeight = 56;
const double _kToolActivityPreviewOverlap = 31;
const double _kToolActivitySurfaceHorizontalInset = 7;
const double _kToolActivityDrawerMaxHeight = 228;
const double _kToolActivityTypeSlotWidth = 34;
const double _kToolActivityStatusSlotWidth = 42;
const double _kToolActivityTrailingSlotWidth = 18;
const Color _kToolActivitySurfaceColor = Color(0xFFF9FCFF);
const BorderRadius _kToolActivitySurfaceBorderRadius = BorderRadius.only(
  topLeft: Radius.circular(_kToolActivitySurfaceRadius),
  topRight: Radius.circular(_kToolActivitySurfaceRadius),
);
const BorderRadius _kToolActivityPreviewBorderRadius = BorderRadius.all(
  Radius.circular(18),
);

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
    final historyHeight = isExpanded
        ? _resolveHistoryHeight(historyCards)
        : 0.0;
    final dividerHeight = isExpanded ? 1.0 : 0.0;
    final surfaceHeight =
        _kToolActivityRowHeight + historyHeight + dividerHeight;
    final collapsedOccupiedHeight =
        _kToolActivityRowHeight +
        _kToolActivityPreviewHeight -
        _kToolActivityPreviewOverlap;
    final totalHeight =
        surfaceHeight +
        (!isExpanded
            ? _kToolActivityPreviewHeight - _kToolActivityPreviewOverlap
            : 0.0);
    final collapsedLeadingInset = math.max(
      0.0,
      _kToolActivityPreviewWidth - _kToolActivitySurfaceHorizontalInset + 2,
    );
    _reportOccupiedHeight(collapsedOccupiedHeight);

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
              left: _kToolActivitySurfaceHorizontalInset,
              right: _kToolActivitySurfaceHorizontalInset,
              bottom: 0,
              child: _ActivityDrawerSurface(
                activeCard: activeCard,
                historyCards: historyCards,
                historyHeight: historyHeight,
                expanded: isExpanded,
                canExpand: canExpand,
                leadingInset: isExpanded ? 0 : collapsedLeadingInset,
                onToggle: () => setState(() => _expanded = !_expanded),
                onOpenCard: (cardData) =>
                    _openCardDetailDialog(context, cardData: cardData),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
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
                        onTap: () => _openCardDetailDialog(
                          context,
                          cardData: activeCard,
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
    final estimated = visibleCount * _kToolActivityRowHeight;
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

  String _buildCardDetailText(Map<String, dynamic> cardData) {
    final toolType = (cardData['toolType'] ?? '').toString();
    if (toolType == 'terminal') {
      final output = resolveAgentToolTerminalOutput(cardData).trimRight();
      if (output.isNotEmpty) {
        return output;
      }
    }

    final title = resolveAgentToolTitle(cardData);
    final statusLabel = resolveAgentToolStatusLabel(cardData);
    final preview = resolveAgentToolPreview(cardData).trim();
    final summary = (cardData['summary'] ?? '').toString().trim();
    final progress = (cardData['progress'] ?? '').toString().trim();
    final sections = <String>[];

    if (progress.isNotEmpty && progress != title) {
      sections.add(progress);
    }
    if (summary.isNotEmpty &&
        summary != title &&
        summary != progress &&
        !sections.contains(summary)) {
      sections.add(summary);
    }
    if (preview.isNotEmpty &&
        preview != title &&
        preview != progress &&
        preview != summary &&
        preview != statusLabel &&
        !sections.contains(preview)) {
      sections.add(preview);
    }
    if (sections.isEmpty) {
      sections.add('暂无工具调用信息');
    }
    return sections.join('\n\n');
  }

  Future<void> _openCardDetailDialog(
    BuildContext context, {
    required Map<String, dynamic> cardData,
  }) {
    final title = resolveAgentToolTitle(cardData);
    final typeLabel = resolveAgentToolTypeLabel(cardData);
    final statusLabel = resolveAgentToolStatusLabel(cardData);
    final status = (cardData['status'] ?? 'running').toString();
    final displayText = _buildCardDetailText(cardData);
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
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF2F7FF),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _DialogMetaTag(label: typeLabel),
                      const SizedBox(width: 6),
                      _DialogStatusTag(status: status, label: statusLabel),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
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
    required this.leadingInset,
    required this.onToggle,
    required this.onOpenCard,
  });

  final Map<String, dynamic> activeCard;
  final List<Map<String, dynamic>> historyCards;
  final double historyHeight;
  final bool expanded;
  final bool canExpand;
  final double leadingInset;
  final VoidCallback onToggle;
  final ValueChanged<Map<String, dynamic>> onOpenCard;

  @override
  Widget build(BuildContext context) {
    return PhysicalShape(
      key: kChatToolActivityBarKey,
      color: _kToolActivitySurfaceColor,
      shadowColor: const Color(0x18111B2D),
      elevation: expanded ? 8 : 6,
      clipBehavior: Clip.antiAlias,
      clipper: _ActivityDrawerClipper(showPreviewCutout: !expanded),
      child: ColoredBox(
        color: _kToolActivitySurfaceColor,
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
                child: _HistoryDrawer(
                  cards: historyCards,
                  onOpenCard: onOpenCard,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: expanded ? 1 : 0,
              margin: const EdgeInsets.only(left: 18, right: 10),
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
  const _ActivityBarTrailing({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: kChatToolActivityToggleKey,
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: AnimatedRotation(
          turns: expanded ? 0 : 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: const Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 14,
            color: Color(0xFF657891),
          ),
        ),
      ),
    );
  }
}

class _HistoryDrawer extends StatelessWidget {
  const _HistoryDrawer({required this.cards, required this.onOpenCard});

  final List<Map<String, dynamic>> cards;
  final ValueChanged<Map<String, dynamic>> onOpenCard;

  @override
  Widget build(BuildContext context) {
    final scrollable = cards.length > 4;
    return Container(
      key: kChatToolActivityPanelKey,
      padding: EdgeInsets.zero,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: scrollable
            ? const BouncingScrollPhysics(parent: ClampingScrollPhysics())
            : const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final card = cards[index];
          final isLast = index == cards.length - 1;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: const Color(0x140F2034),
                        width: 1,
                      ),
                    ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onOpenCard(card),
                child: ToolActivityRow(card: card),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox.shrink(),
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
    final toolTypeLabel = resolveAgentToolTypeLabel(card);
    final statusLabel = resolveAgentToolStatusLabel(card);

    return SizedBox(
      height: _kToolActivityRowHeight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(10 + leadingInset, 0, 8, 0),
        child: Row(
          children: [
            _StatusDot(status: status),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                resolveAgentToolTitle(card),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: _kToolActivityTypeSlotWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  toolTypeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF7C8DA5),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    height: 1.05,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: _kToolActivityStatusSlotWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: _StatusTag(status: status, label: statusLabel),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: _kToolActivityTrailingSlotWidth,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
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
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: 0.9),
          fontSize: 8.4,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DialogMetaTag extends StatelessWidget {
  const _DialogMetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF152133),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF273752)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF9FB1C8),
          fontSize: 9.2,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DialogStatusTag extends StatelessWidget {
  const _DialogStatusTag({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withValues(alpha: 0.96),
          fontSize: 9.2,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _TerminalThumbnail extends StatelessWidget {
  const _TerminalThumbnail({
    super.key,
    required this.previewText,
    required this.onTap,
  });

  final String previewText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lines = _thumbnailText(previewText)
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final headline = lines.isEmpty ? '\$ idle' : lines.first;
    final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';

    return PhysicalModel(
      color: const Color(0xFF12161E),
      borderRadius: _kToolActivityPreviewBorderRadius,
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: const Color(0x2B0B1220),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
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
              borderRadius: _kToolActivityPreviewBorderRadius,
              border: Border.all(color: const Color(0xFF2C3240)),
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
                    fontSize: 7.8,
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
                        fontSize: 6.8,
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
      ),
    );
  }

  String _thumbnailText(String previewText) {
    final preferred = previewText.trim();
    if (preferred.isNotEmpty) {
      return preferred;
    }
    return '\$ idle';
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

class _ActivityDrawerClipper extends CustomClipper<Path> {
  const _ActivityDrawerClipper({required this.showPreviewCutout});

  final bool showPreviewCutout;

  @override
  Path getClip(Size size) {
    final surfacePath = Path()
      ..addRRect(_kToolActivitySurfaceBorderRadius.toRRect(Offset.zero & size));
    if (!showPreviewCutout) {
      return surfacePath;
    }
    final previewTop =
        -(_kToolActivityPreviewHeight - _kToolActivityPreviewOverlap);
    final previewRect = Rect.fromLTWH(
      -_kToolActivitySurfaceHorizontalInset,
      previewTop,
      _kToolActivityPreviewWidth,
      _kToolActivityPreviewHeight,
    );
    final previewPath = Path()
      ..addRRect(_kToolActivityPreviewBorderRadius.toRRect(previewRect));
    return Path.combine(PathOperation.difference, surfacePath, previewPath);
  }

  @override
  bool shouldReclip(covariant _ActivityDrawerClipper oldClipper) {
    return oldClipper.showPreviewCutout != showPreviewCutout;
  }
}
