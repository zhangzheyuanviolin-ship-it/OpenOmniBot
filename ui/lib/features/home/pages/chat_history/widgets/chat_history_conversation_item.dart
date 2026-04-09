import 'package:flutter/material.dart';
import 'package:ui/features/home/widgets/conversation_slidable.dart';
import 'package:ui/features/home/widgets/conversation_mode_badge.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';

class ChatHistoryConversationItem extends StatelessWidget {
  const ChatHistoryConversationItem({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.actions,
    required this.onDelete,
    this.isBusy = false,
    this.showLeadingIcon = true,
  });

  final ConversationModel conversation;
  final VoidCallback onTap;
  final List<ConversationSlideAction> actions;
  final VoidCallback onDelete;
  final bool isBusy;
  final bool showLeadingIcon;

  static const String slidableGroupTag = 'chat-history';
  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return ConversationSlidable(
      itemKey: conversation.threadKey,
      groupTag: slidableGroupTag,
      isBusy: isBusy,
      actions: actions,
      onDismissed: onDelete,
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: _cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: _cardRadius,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.isDarkTheme
                  ? palette.surfacePrimary
                  : Colors.white,
              borderRadius: _cardRadius,
              border: context.isDarkTheme
                  ? Border.all(color: palette.borderSubtle)
                  : null,
              boxShadow: context.isDarkTheme
                  ? [
                      BoxShadow(
                        color: palette.shadowColor.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                if (showLeadingIcon) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: context.isDarkTheme
                            ? <Color>[
                                Color.lerp(
                                  palette.surfaceElevated,
                                  palette.accentPrimary,
                                  0.18,
                                )!,
                                Color.lerp(
                                  palette.surfaceSecondary,
                                  palette.accentPrimary,
                                  0.3,
                                )!,
                              ]
                            : const <Color>[
                                Color(0xFF1930D9),
                                Color(0xFF2CA5F0),
                              ],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      border: context.isDarkTheme
                          ? Border.all(color: palette.borderSubtle)
                          : null,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      color: context.isDarkTheme
                          ? palette.textPrimary
                          : Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: context.isDarkTheme
                                    ? palette.textPrimary
                                    : AppColors.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConversationModeBadge(
                            mode: conversation.mode,
                            compact: true,
                          ),
                        ],
                      ),
                      if ((conversation.summary ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          conversation.summary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.isDarkTheme
                                ? palette.textSecondary
                                : AppColors.text.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      conversation.timeDisplay,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.isDarkTheme
                            ? palette.textTertiary
                            : AppColors.text.withValues(alpha: 0.4),
                      ),
                    ),
                    if (conversation.messageCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${conversation.messageCount} \u6761\u6d88\u606f',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.isDarkTheme
                              ? palette.textTertiary
                              : AppColors.text.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
