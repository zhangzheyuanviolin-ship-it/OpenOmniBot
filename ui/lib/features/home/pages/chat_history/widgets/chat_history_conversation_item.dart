import 'package:flutter/material.dart';
import 'package:ui/features/home/widgets/conversation_slidable.dart';
import 'package:ui/features/home/widgets/conversation_mode_badge.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/theme/app_colors.dart';

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
              color: Colors.white,
              borderRadius: _cardRadius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1930D9), Color(0xFF2CA5F0)],
                      ),
                      borderRadius: BorderRadius.all(
                        Radius.circular(8),
                      ),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
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
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
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
                            color: AppColors.text.withOpacity(0.6),
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
                        color: AppColors.text.withOpacity(0.4),
                      ),
                    ),
                    if (conversation.messageCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${conversation.messageCount} \u6761\u6d88\u606f',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.text.withOpacity(0.4),
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
