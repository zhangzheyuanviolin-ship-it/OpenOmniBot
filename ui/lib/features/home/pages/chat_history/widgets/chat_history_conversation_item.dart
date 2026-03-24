import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/features/home/widgets/conversation_mode_badge.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/theme/app_colors.dart';

class ChatHistoryConversationItem extends StatelessWidget {
  const ChatHistoryConversationItem({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onDelete,
    this.isDeleting = false,
  });

  final ConversationModel conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isDeleting;

  static const String slidableGroupTag = 'chat-history';
  static const double _actionExtentRatio = 0.24;
  static const double _deleteIconSize = 20;
  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(8));
  static const BorderRadius _deleteActionRadius = BorderRadius.only(
    topRight: Radius.circular(8),
    bottomRight: Radius.circular(8),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: IgnorePointer(
        ignoring: isDeleting,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isDeleting ? 0.72 : 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final initialActionWidth =
                  constraints.maxWidth * _actionExtentRatio;
              final deleteIconRightPadding =
                  ((initialActionWidth - _deleteIconSize) / 2)
                      .clamp(0.0, double.infinity)
                      .toDouble();

              return Slidable(
                key: ValueKey<String>(conversation.threadKey),
                groupTag: slidableGroupTag,
                closeOnScroll: true,
                endActionPane: ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: _actionExtentRatio,
                  dismissible: DismissiblePane(
                    dismissThreshold: 0.4,
                    closeOnCancel: true,
                    motion: const InversedDrawerMotion(),
                    onDismissed: onDelete,
                  ),
                  children: [
                    CustomSlidableAction(
                      onPressed: (_) => onDelete(),
                      backgroundColor: AppColors.alertRed,
                      borderRadius: _deleteActionRadius,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: deleteIconRightPadding),
                        child: SvgPicture.asset(
                          'assets/memory/memory_delete.svg',
                          width: _deleteIconSize,
                          height: _deleteIconSize,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                                if ((conversation.summary ?? '')
                                    .isNotEmpty) ...[
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
            },
          ),
        ),
      ),
    );
  }
}
