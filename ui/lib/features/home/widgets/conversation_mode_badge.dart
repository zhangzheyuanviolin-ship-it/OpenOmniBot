import 'package:flutter/material.dart';
import 'package:ui/models/conversation_model.dart';

class ConversationModeBadge extends StatelessWidget {
  const ConversationModeBadge({
    super.key,
    required this.mode,
    this.compact = false,
  });

  final ConversationMode mode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isOpenClaw = mode == ConversationMode.openclaw;
    final backgroundColor = isOpenClaw
        ? const Color(0xFFFBE7D3)
        : const Color(0xFFE6EEF9);
    final textColor = isOpenClaw
        ? const Color(0xFF9A540D)
        : const Color(0xFF2552A6);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        mode.displayLabel,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
