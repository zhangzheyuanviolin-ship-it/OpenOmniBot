import 'package:flutter/material.dart';
import '../../../../../models/chat_message_model.dart';
import '../../../../../services/assists_core_service.dart';
import '../../command_overlay/constants/messages.dart';
import 'package:ui/utils/data_parser.dart';

/// 聊天消息处理 Mixin
/// 负责处理AI消息流、VLM用户输入等功能
mixin ChatMessageHandler<T extends StatefulWidget> on State<T> {
  // ===================== 抽象属性/方法（需要在主类中实现）=====================

  List<ChatMessageModel> get messages;
  bool get isAiResponding;
  set isAiResponding(bool value);
  Map<String, String> get currentAiMessages;
  TextEditingController get vlmAnswerController;
  String? get vlmInfoQuestion;
  set vlmInfoQuestion(String? value);
  bool get isSubmittingVlmReply;
  set isSubmittingVlmReply(bool value);

  Future<void> saveConversation();

  // ===================== Loading 消息管理 =====================

  /// 添加 loading 消息
  void addLoadingMessage() {
    final loadingId = '${DateTime.now().millisecondsSinceEpoch}-loading';
    setState(() {
      messages.insert(
        0,
        ChatMessageModel(
          id: loadingId,
          type: 1,
          user: 2,
          content: {'text': '', 'id': loadingId},
          isLoading: true,
        ),
      );
    });
  }

  /// 移除最新的 loading 消息（如果存在）
  void removeLatestLoadingIfExists() {
    if (messages.isNotEmpty && messages[0].isLoading) {
      setState(() {
        messages.removeAt(0);
      });
    }
  }

  // ===================== AI 消息处理 =====================

  /// 处理 AI 消息流
  void handleAiMessage(String taskId, String content, String? type) async {
    final isErrorMessage = type == 'error';
    final isRateLimited = type == 'rate_limited';
    final isSummaryStart = type == 'summary_start';
    final isOpenClawAttachment = type == 'openclaw_attachment';
    final payload = safeDecodeMap(content);
    final payloadAttachments = _parseAttachments(payload['attachments']);
    String messageText;
    bool isError;
    bool isSummarizing;

    final isFirstChunk = !currentAiMessages.containsKey(taskId);
    if (isFirstChunk) {
      removeLatestLoadingIfExists();
    }

    if (isRateLimited) {
      messageText = kRateLimitErrorMessage;
      isError = true;
      isSummarizing = false;
      currentAiMessages.remove(taskId);
    } else if (isErrorMessage) {
      messageText = kNetworkErrorMessage;
      isError = true;
      isSummarizing = false;
      currentAiMessages.remove(taskId);
    } else if (isSummaryStart) {
      // 总结开始，显示"总结中"状态
      messageText = '';
      isError = false;
      isSummarizing = true;
      currentAiMessages[taskId] = '';
    } else if (isOpenClawAttachment) {
      messageText = currentAiMessages[taskId] ?? '';
      isError = false;
      isSummarizing = false;
    } else {
      final text = extractChatTaskText(content, fallbackToRawText: false);
      currentAiMessages[taskId] = (currentAiMessages[taskId] ?? '') + text;
      messageText = currentAiMessages[taskId] ?? '';
      isError = false;
      isSummarizing = false;
    }

    updateOrAddAiMessage(
      taskId,
      messageText,
      isError,
      isSummarizing: isSummarizing,
      attachments: payloadAttachments,
    );
  }

  /// 更新或添加 AI 消息
  void updateOrAddAiMessage(
    String taskId,
    String text,
    bool isError, {
    bool isSummarizing = false,
    List<Map<String, dynamic>> attachments = const [],
  }) {
    final index = messages.indexWhere((msg) => msg.id == taskId);

    setState(() {
      if (index == -1) {
        final content = <String, dynamic>{'text': text, 'id': taskId};
        if (attachments.isNotEmpty) {
          content['attachments'] = attachments;
        }
        messages.insert(
          0,
          ChatMessageModel(
            id: taskId,
            type: 1,
            user: 2,
            content: content,
            isLoading: false,
            isError: isError,
            isSummarizing: isSummarizing,
          ),
        );
      } else {
        final existing = messages[index];
        final content = Map<String, dynamic>.from(existing.content ?? {});
        final existingText = content['text'] as String? ?? '';
        content['text'] = text.isNotEmpty ? text : existingText;
        final mergedAttachments = _mergeAttachments(
          _parseAttachments(content['attachments']),
          attachments,
        );
        if (mergedAttachments.isNotEmpty) {
          content['attachments'] = mergedAttachments;
        }
        messages[index] = existing.copyWith(
          content: content,
          isLoading: false,
          isError: isError,
          isSummarizing: isSummarizing,
        );
      }
    });
  }

  /// 处理 AI 消息结束
  void handleAiMessageEnd(String taskId) async {
    setState(() => isAiResponding = false);

    final index = messages.indexWhere((msg) => msg.id == taskId);
    final isErrorMessage = index != -1 && messages[index].isError;
    final messageText = isErrorMessage
        ? (messages[index].content?['text'] as String? ?? '')
        : (currentAiMessages[taskId] ?? '');

    if (messageText.isNotEmpty && index != -1) {
      setState(() {
        final existing = messages[index];
        messages[index] = existing.copyWith(content: existing.content);
      });
    }
    currentAiMessages.remove(taskId);
    saveConversation();
  }

  // ===================== VLM 用户输入处理 =====================

  /// 提交 VLM 用户输入
  Future<void> onSubmitVlmInfo() async {
    if (isSubmittingVlmReply || vlmInfoQuestion == null) return;
    final reply = vlmAnswerController.text.trim().isEmpty
        ? '已完成操作，继续执行'
        : vlmAnswerController.text.trim();
    setState(() {
      isSubmittingVlmReply = true;
    });
    final success = await AssistsMessageService.provideUserInputToVLMTask(
      reply,
    );
    if (!mounted) return;
    setState(() {
      isSubmittingVlmReply = false;
      if (success) {
        vlmInfoQuestion = null;
        vlmAnswerController.clear();
      }
    });
  }

  /// 关闭 VLM 输入提示
  void dismissVlmInfo() {
    setState(() {
      vlmInfoQuestion = null;
      vlmAnswerController.clear();
    });
  }

  List<Map<String, dynamic>> _parseAttachments(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  List<Map<String, dynamic>> _mergeAttachments(
    List<Map<String, dynamic>> previous,
    List<Map<String, dynamic>> latest,
  ) {
    if (previous.isEmpty) return latest;
    if (latest.isEmpty) return previous;
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    void add(List<Map<String, dynamic>> source) {
      for (final item in source) {
        final key = _attachmentIdentity(item);
        if (seen.contains(key)) continue;
        seen.add(key);
        merged.add(item);
      }
    }

    add(previous);
    add(latest);
    return merged;
  }

  String _attachmentIdentity(Map<String, dynamic> item) {
    final id = (item['id'] as String? ?? '').trim();
    if (id.isNotEmpty) return id;
    final path = (item['path'] as String? ?? '').trim();
    if (path.isNotEmpty) return path;
    final url = (item['url'] as String? ?? '').trim();
    if (url.isNotEmpty) return url;
    final name = (item['name'] as String? ?? '').trim();
    final fileName = (item['fileName'] as String? ?? '').trim();
    return '$name|$fileName|${item['size']}';
  }
}
