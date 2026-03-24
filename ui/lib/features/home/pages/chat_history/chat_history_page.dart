import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/pages/chat_history/widgets/chat_history_conversation_item.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/conversation_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/cache_util.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class ChatHistoryPage extends StatefulWidget {
  const ChatHistoryPage({super.key});

  @override
  State<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage> {
  List<ConversationModel> _conversations = const [];
  final Set<String> _deletingKeys = <String>{};
  bool _isLoading = true;

  Future<void> _triggerDeleteHaptic() async {
    try {
      final enabled = await CacheUtil.getBool(
        'app_vibrate',
        defaultValue: true,
      );
      if (!enabled) {
        return;
      }
      await HapticFeedback.mediumImpact();
    } catch (error) {
      debugPrint('[ChatHistoryPage] failed to trigger delete haptic: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final loadedConversations =
          await ConversationService.getAllConversations();
      if (!mounted) {
        return;
      }
      setState(() {
        _conversations = loadedConversations;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('[ChatHistoryPage] failed to load conversations: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteConversation(ConversationModel conversation) async {
    if (_deletingKeys.contains(conversation.threadKey)) {
      return;
    }

    final originalIndex = _conversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _deletingKeys.add(conversation.threadKey);
      _conversations = List<ConversationModel>.from(_conversations)
        ..removeAt(originalIndex);
    });

    final deleted = await ConversationService.deleteConversation(
      conversation.id,
      mode: conversation.mode,
    );
    if (!mounted) {
      return;
    }
    if (deleted) {
      unawaited(_triggerDeleteHaptic());
    }

    setState(() {
      _deletingKeys.remove(conversation.threadKey);
      if (!deleted) {
        final restoredIndex = originalIndex <= _conversations.length
            ? originalIndex
            : _conversations.length;
        _conversations = List<ConversationModel>.from(_conversations)
          ..insert(restoredIndex, conversation);
      }
    });

    showToast(
      deleted ? '\u5df2\u5220\u9664' : '\u5220\u9664\u5931\u8d25',
      type: deleted ? ToastType.success : ToastType.error,
    );
  }

  void _openConversation(ConversationModel conversation) {
    if (_deletingKeys.contains(conversation.threadKey)) {
      return;
    }
    GoRouterManager.push(
      '/home/chat',
      extra: ConversationThreadTarget.existing(
        conversationId: conversation.id,
        mode: conversation.mode,
      ),
    );
  }

  void _createConversation() {
    GoRouterManager.push(
      '/home/chat',
      extra: ConversationThreadTarget.newConversation(
        requestKey: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CommonAppBar(
        title: '\u804a\u5929\u8bb0\u5f55',
        primary: true,
        trailing: IconButton(
          icon: Icon(Icons.add, color: Colors.grey[600], size: 24),
          onPressed: _createConversation,
          tooltip: '\u65b0\u5efa\u5bf9\u8bdd',
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1930D9)),
        ),
      );
    }

    if (_conversations.isEmpty) {
      return _buildEmptyState();
    }

    return SlidableAutoCloseBehavior(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          return ChatHistoryConversationItem(
            conversation: conversation,
            isDeleting: _deletingKeys.contains(conversation.threadKey),
            onTap: () => _openConversation(conversation),
            onDelete: () => _deleteConversation(conversation),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '\u6682\u65e0\u804a\u5929\u8bb0\u5f55',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _createConversation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1930D9), Color(0xFF2CA5F0)],
                ),
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              child: const Text(
                '\u5f00\u59cb\u5bf9\u8bdd',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
