import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/features/home/pages/authorize/authorize_page_args.dart';
import 'package:ui/features/home/pages/chat/utils/stream_text_merge.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/voice_playback_coordinator.dart';

enum ThinkingStage {
  thinking(1),
  toolCall(2),
  executing(3),
  complete(4);

  final int value;
  const ThinkingStage(this.value);

  static ThinkingStage fromValue(int value) {
    return ThinkingStage.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ThinkingStage.thinking,
    );
  }
}

mixin AgentStreamHandler<T extends StatefulWidget> on State<T> {
  static const int _maxTerminalOutputChars = 64 * 1024;
  static const int _maxTerminalOutputLines = 600;
  static const Map<String, String> _executionPermissionNameToId =
      <String, String>{
        '无障碍权限': kAccessibilityPermissionId,
        '悬浮窗权限': kOverlayPermissionId,
        '应用列表读取权限': kInstalledAppsPermissionId,
        '公共文件访问': kPublicStoragePermissionId,
      };

  String? _lastAgentTaskId;
  String? _activeToolCardId;
  String? _activeThinkingCardId;
  String? _pendingAgentTextTaskId;
  bool _pendingThinkingRoundSplit = false;
  int _toolCardSequence = 0;
  int _thinkingRound = 0;

  String? get currentDispatchTaskId;

  String get deepThinkingContent;
  set deepThinkingContent(String value);

  bool get isDeepThinking;
  set isDeepThinking(bool value);

  int get currentThinkingStage;
  set currentThinkingStage(int value);

  List<ChatMessageModel> get messages;

  bool get isAiResponding;
  set isAiResponding(bool value);

  void createThinkingCard(String taskID);

  void updateThinkingCard(String taskID);

  void createThinkingCardForAgent(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
  }) {
    createThinkingCard(taskID);
  }

  void updateThinkingCardForAgent(
    String taskID, {
    String? cardId,
    String? thinkingContent,
    bool? isLoading,
    int? stage,
    bool lockCompleted = true,
  }) {
    updateThinkingCard(taskID);
  }

  void resetDispatchState();

  void fallbackToChat(String taskID);

  void handleExecutableTaskClarify(String taskID, Map<String, dynamic> data);

  Future<void> persistAgentConversation();

  void handleAgentThinkingStart() {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;

    _lastAgentTaskId = taskId;
    currentThinkingStage = ThinkingStage.thinking.value;
    isDeepThinking = true;

    if (_thinkingRound == 0) {
      _thinkingRound = 1;
      _activeThinkingCardId = _baseThinkingCardId(taskId);
      final exists = messages.any((msg) => msg.id == _activeThinkingCardId);
      if (exists) {
        updateThinkingCardForAgent(
          taskId,
          cardId: _activeThinkingCardId,
          isLoading: true,
          stage: ThinkingStage.thinking.value,
        );
      } else {
        createThinkingCardForAgent(
          taskId,
          cardId: _activeThinkingCardId,
          isLoading: true,
          stage: ThinkingStage.thinking.value,
        );
      }
      return;
    }

    _pendingThinkingRoundSplit = true;
  }

  void handleAgentThinkingUpdate(String thinking) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;
    if (shouldIgnoreRegressiveStreamingSnapshot(
      deepThinkingContent,
      thinking,
    )) {
      return;
    }

    if (_pendingThinkingRoundSplit) {
      if (thinking.trim().isEmpty) {
        return;
      }

      final previousThinkingCardId = _resolveThinkingCardId(taskId);
      if (previousThinkingCardId != null) {
        updateThinkingCardForAgent(
          taskId,
          cardId: previousThinkingCardId,
          isLoading: false,
          stage: ThinkingStage.complete.value,
          lockCompleted: false,
        );
      }

      _thinkingRound += 1;
      _activeThinkingCardId = '$taskId-thinking-$_thinkingRound';
      createThinkingCardForAgent(
        taskId,
        cardId: _activeThinkingCardId,
        thinkingContent: thinking,
        isLoading: true,
        stage: ThinkingStage.thinking.value,
      );
      deepThinkingContent = thinking;
      _pendingThinkingRoundSplit = false;
      return;
    }

    deepThinkingContent = thinking;
    final thinkingCardId = _resolveThinkingCardId(taskId);
    if (thinkingCardId == null) return;

    updateThinkingCardForAgent(
      taskId,
      cardId: thinkingCardId,
      thinkingContent: thinking,
      isLoading: true,
      stage: currentThinkingStage,
    );
  }

  void handleAgentToolCallStart(AgentToolEventData event) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;

    _finalizePendingAgentTextIfNeeded(taskId);
    currentThinkingStage = ThinkingStage.toolCall.value;
    _toolCardSequence += 1;
    _activeToolCardId = '$taskId-tool-$_toolCardSequence';
    _upsertToolCard(
      taskId: taskId,
      cardId: _activeToolCardId!,
      event: event,
      status: 'running',
      summary: event.summary.isNotEmpty ? event.summary : '正在调用工具',
      progress: event.progress,
      resultPreviewJson: event.resultPreviewJson,
      rawResultJson: event.rawResultJson,
    );
    final thinkingCardId = _resolveThinkingCardId(taskId);
    if (thinkingCardId != null) {
      updateThinkingCardForAgent(
        taskId,
        cardId: thinkingCardId,
        isLoading: isDeepThinking,
        stage: ThinkingStage.toolCall.value,
      );
    }
  }

  void handleAgentToolCallProgress(AgentToolEventData event) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;

    if (_activeToolCardId != null) {
      _upsertToolCard(
        taskId: taskId,
        cardId: _activeToolCardId!,
        event: event,
        status: 'running',
        summary: event.summary.isNotEmpty ? event.summary : '正在调用工具',
        progress: event.progress,
        resultPreviewJson: event.resultPreviewJson,
        rawResultJson: event.rawResultJson,
      );
    }
  }

  void handleAgentToolCallComplete(AgentToolEventData event) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null || _activeToolCardId == null) return;

    _upsertToolCard(
      taskId: taskId,
      cardId: _activeToolCardId!,
      event: event,
      status: _resolveToolStatus(event),
      summary: event.summary,
      progress: event.progress,
      resultPreviewJson: event.resultPreviewJson,
      rawResultJson: event.rawResultJson,
    );
    _activeToolCardId = null;
  }

  void handleAgentChatMessage(
    String message, {
    bool isFinal = true,
    double? prefillTokensPerSecond,
    double? decodeTokensPerSecond,
  }) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;

    final aiTextMessageId =
        _resolvePendingAgentTextMessageId(taskId) ??
        _nextAgentTextMessageId(taskId);
    var visibleText = '';
    setState(() {
      final index = messages.indexWhere((msg) => msg.id == aiTextMessageId);
      if (index == -1) {
        final initialText = mergeAgentTextSnapshot('', message);
        visibleText = initialText;
        messages.insert(
          0,
          ChatMessageModel(
            id: aiTextMessageId,
            type: 1,
            user: 2,
            content: {
              'text': initialText,
              'id': aiTextMessageId,
              if (isFinal && prefillTokensPerSecond != null)
                'prefillTokensPerSecond': prefillTokensPerSecond,
              if (isFinal && decodeTokensPerSecond != null)
                'decodeTokensPerSecond': decodeTokensPerSecond,
            },
          ),
        );
      } else {
        final existing = messages[index];
        final content = Map<String, dynamic>.from(existing.content ?? {});
        final currentText = (content['text'] ?? '').toString();
        visibleText = mergeAgentTextSnapshot(currentText, message);
        content['text'] = visibleText;
        if (isFinal && prefillTokensPerSecond != null) {
          content['prefillTokensPerSecond'] = prefillTokensPerSecond;
        }
        if (isFinal && decodeTokensPerSecond != null) {
          content['decodeTokensPerSecond'] = decodeTokensPerSecond;
        }
        messages[index] = existing.copyWith(content: content);
      }
      if (isFinal) {
        isAiResponding = false;
      }
    });
    _pendingAgentTextTaskId = isFinal ? null : taskId;
    if (isFinal && currentDispatchTaskId == null) {
      _lastAgentTaskId = null;
    }
    if (visibleText.trim().isNotEmpty) {
      unawaited(
        VoicePlaybackCoordinator.instance.onAssistantMessageUpdated(
          messageId: aiTextMessageId,
          text: visibleText,
          isFinal: isFinal,
        ),
      );
    }
    if (isFinal) {
      _persistAgentConversationSafely();
    }
  }

  void handleAgentClarifyRequired(String question, List<String> missingFields) {
    if (currentDispatchTaskId == null) return;

    currentThinkingStage = ThinkingStage.complete.value;
    isDeepThinking = false;
    final taskId = currentDispatchTaskId!;
    final thinkingCardId = _resolveThinkingCardId(taskId);
    if (thinkingCardId != null) {
      updateThinkingCardForAgent(
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    handleExecutableTaskClarify(taskId, {
      'response': question,
      'is_task_but_incomplete': true,
      'missing_fields': missingFields,
    });
    _persistAgentConversationSafely();
  }

  void handleAgentComplete(
    bool success, {
    String outputKind = 'none',
    bool hasUserVisibleOutput = false,
  }) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;

    currentThinkingStage = ThinkingStage.complete.value;
    isDeepThinking = false;
    final thinkingCardId = _resolveThinkingCardId(taskId);
    if (thinkingCardId != null) {
      updateThinkingCardForAgent(
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    if (success) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;

        final normalizedOutputKind = outputKind.trim().toLowerCase();
        final hasVisibleOutput = messages.any((msg) {
          if (!msg.id.startsWith(taskId)) return false;
          if (msg.type == 1 && msg.user == 2) return true;
          final cardType = msg.cardData?['type'] as String?;
          return cardType == 'agent_tool_summary' ||
              cardType == 'permission_section';
        });
        final shouldInjectFallback =
            normalizedOutputKind == 'none' &&
            !hasUserVisibleOutput &&
            !hasVisibleOutput;
        if (shouldInjectFallback) {
          final fallbackId = _nextAgentTextMessageId(taskId);
          final index = messages.indexWhere((msg) => msg.id == fallbackId);
          setState(() {
            if (index == -1) {
              messages.insert(
                0,
                ChatMessageModel(
                  id: fallbackId,
                  type: 1,
                  user: 2,
                  content: {'text': '我已完成思考，但暂时无法生成回复，请重试。', 'id': fallbackId},
                ),
              );
            }
            isAiResponding = false;
          });
        } else {
          setState(() {
            isAiResponding = false;
          });
        }
        clearAgentStreamSessionState();
        resetDispatchState();
        _persistAgentConversationSafely();
      });
      return;
    }

    setState(() {
      isAiResponding = false;
    });
    clearAgentStreamSessionState();
    resetDispatchState();
    _persistAgentConversationSafely();
  }

  void handleAgentError(String error) {
    final taskId = currentDispatchTaskId ?? _lastAgentTaskId;
    if (taskId == null) return;

    debugPrint('Agent error: $error');

    currentThinkingStage = ThinkingStage.complete.value;
    isDeepThinking = false;
    final thinkingCardId = _resolveThinkingCardId(taskId);
    if (thinkingCardId != null) {
      updateThinkingCardForAgent(
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    final textId =
        _resolvePendingAgentTextMessageId(taskId) ??
        _nextAgentTextMessageId(taskId);
    final index = messages.indexWhere((msg) => msg.id == textId);
    final existingText = index == -1
        ? ''
        : (messages[index].content?['text'] as String? ?? '');
    final preservedText = existingText.trim();
    final fallbackMessage = error.trim().isEmpty
        ? (LegacyTextLocalizer.isEnglish
              ? "I can't generate a reply right now. Please try again."
              : '暂时无法生成回复，请重试。')
        : (LegacyTextLocalizer.isEnglish
              ? "I can't generate a reply right now. Please try again. ${error.trim()}"
              : '暂时无法生成回复，请重试。${error.trim()}');
    setState(() {
      if (index == -1) {
        messages.insert(
          0,
          ChatMessageModel(
            id: textId,
            type: 1,
            user: 2,
            content: {
              'text': preservedText.isNotEmpty
                  ? preservedText
                  : fallbackMessage,
              'id': textId,
            },
            isError: preservedText.isEmpty,
          ),
        );
      } else {
        final existing = messages[index];
        messages[index] = existing.copyWith(
          content: {
            'text': preservedText.isNotEmpty ? preservedText : fallbackMessage,
            'id': textId,
          },
          isError: preservedText.isEmpty,
        );
      }
      isAiResponding = false;
    });
    _pendingAgentTextTaskId = null;
    if (preservedText.isNotEmpty) {
      unawaited(
        VoicePlaybackCoordinator.instance.onAssistantMessageCompleted(
          messageId: textId,
          text: preservedText,
        ),
      );
    }

    clearAgentStreamSessionState();
    resetDispatchState();
    _persistAgentConversationSafely();
  }

  void handleAgentPermissionRequired(List<String> missing) {
    if (currentDispatchTaskId == null) return;

    currentThinkingStage = ThinkingStage.complete.value;
    isDeepThinking = false;
    final taskId = currentDispatchTaskId!;
    final thinkingCardId = _resolveThinkingCardId(taskId);
    if (thinkingCardId != null) {
      updateThinkingCardForAgent(
        taskId,
        cardId: thinkingCardId,
        isLoading: false,
        stage: ThinkingStage.complete.value,
      );
    }

    final executionPermissionIds = _resolveExecutionPermissionIds(missing);
    final shouldShowPermissionCard =
        executionPermissionIds.isNotEmpty &&
        executionPermissionIds.length == missing.length;
    final names = missing.join('、');
    final message = names.isEmpty ? '执行任务前需要先开启权限' : '执行任务前，请先开启：$names';

    interruptActiveToolCard();

    final textMessageId = _nextAgentTextMessageId(taskId);
    final cardMessageId = '$taskId-permission';

    setState(() {
      messages.insert(
        0,
        ChatMessageModel(
          id: textMessageId,
          type: 1,
          user: 2,
          content: {'text': message, 'id': textMessageId},
        ),
      );
      if (shouldShowPermissionCard) {
        messages.insert(
          0,
          ChatMessageModel(
            id: cardMessageId,
            type: 2,
            user: 3,
            content: {
              'cardData': {
                'type': 'permission_section',
                'requiredPermissionIds': executionPermissionIds,
              },
              'id': cardMessageId,
            },
          ),
        );
      }
      isAiResponding = false;
    });

    clearAgentStreamSessionState();
    resetDispatchState();
    _persistAgentConversationSafely();
  }

  List<String> _resolveExecutionPermissionIds(List<String> missing) {
    return missing
        .map((item) => item.trim())
        .map((item) => _executionPermissionNameToId[item])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  String _baseThinkingCardId(String taskId) => '$taskId-thinking';
  String _agentTextBaseId(String taskId) => '$taskId-text';

  String? _resolveThinkingCardId(String taskId) {
    if (_activeThinkingCardId != null) {
      return _activeThinkingCardId;
    }
    final baseId = _baseThinkingCardId(taskId);
    final exists = messages.any((msg) => msg.id == baseId);
    return exists ? baseId : null;
  }

  String? _resolvePendingAgentTextMessageId(String taskId) {
    if (_pendingAgentTextTaskId != taskId) return null;
    for (final message in messages) {
      if (_isAgentTextMessageForTask(message, taskId)) {
        return message.id;
      }
    }
    return null;
  }

  String _nextAgentTextMessageId(String taskId) {
    final baseId = _agentTextBaseId(taskId);
    var maxSequence = 0;
    for (final message in messages) {
      final sequence = _agentTextMessageSequence(message.id, taskId);
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    if (maxSequence == 0) {
      return baseId;
    }
    return '$baseId-${maxSequence + 1}';
  }

  bool _isAgentTextMessageForTask(ChatMessageModel message, String taskId) {
    if (message.type != 1 || message.user != 2) {
      return false;
    }
    return _agentTextMessageSequence(message.id, taskId) > 0;
  }

  int _agentTextMessageSequence(String messageId, String taskId) {
    final baseId = _agentTextBaseId(taskId);
    if (messageId == baseId) {
      return 1;
    }
    if (!messageId.startsWith('$baseId-')) {
      return 0;
    }
    return int.tryParse(messageId.substring(baseId.length + 1)) ?? 0;
  }

  void _resetThinkingRoundState() {
    _activeThinkingCardId = null;
    _thinkingRound = 0;
    _pendingThinkingRoundSplit = false;
  }

  void clearAgentStreamSessionState() {
    _lastAgentTaskId = null;
    _pendingAgentTextTaskId = null;
    _activeToolCardId = null;
    _resetThinkingRoundState();
  }

  void interruptActiveToolCard({String? summary}) {
    final cardId = _activeToolCardId;
    if (cardId == null) return;

    setState(() {
      final index = messages.indexWhere((msg) => msg.id == cardId);
      if (index == -1) {
        return;
      }

      final existingCardData = Map<String, dynamic>.from(
        messages[index].cardData ?? const {},
      );
      existingCardData['status'] = 'interrupted';
      existingCardData['success'] = false;
      if (summary != null && summary.trim().isNotEmpty) {
        existingCardData['summary'] = summary.trim();
      }

      messages[index] = messages[index].copyWith(
        content: {'cardData': existingCardData, 'id': cardId},
      );
    });

    _activeToolCardId = null;
  }

  void _finalizePendingAgentTextIfNeeded(String taskId) {
    final pendingTextMessageId = _resolvePendingAgentTextMessageId(taskId);
    if (pendingTextMessageId == null) {
      _pendingAgentTextTaskId = null;
      return;
    }
    setState(() {
      messages.removeWhere(
        (msg) =>
            msg.id == pendingTextMessageId &&
            (msg.text?.trim().isEmpty ?? true),
      );
    });
    _pendingAgentTextTaskId = null;
  }

  void _persistAgentConversationSafely() {
    Future<void>.microtask(() async {
      try {
        await persistAgentConversation();
      } catch (e) {
        debugPrint('persistAgentConversation failed: $e');
      }
    });
  }

  void _upsertToolCard({
    required String taskId,
    required String cardId,
    required AgentToolEventData event,
    required String status,
    required String summary,
    required String progress,
    required String resultPreviewJson,
    required String rawResultJson,
  }) {
    setState(() {
      final index = messages.indexWhere((msg) => msg.id == cardId);
      final existingCardData = index == -1
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(messages[index].cardData ?? const {});
      final existingTerminalOutput = (existingCardData['terminalOutput'] ?? '')
          .toString();
      final terminalOutput = event.toolType == 'terminal'
          ? _resolveTerminalOutput(
              existing: existingTerminalOutput,
              event: event,
            )
          : '';
      final cardData = {
        'type': 'agent_tool_summary',
        'taskId': taskId,
        'toolTaskId': event.taskId.isNotEmpty
            ? event.taskId
            : (existingCardData['toolTaskId'] ?? '').toString(),
        'cardId': cardId,
        'toolName': event.toolName,
        'displayName': event.displayName,
        'toolTitle': event.toolTitle.isNotEmpty
            ? event.toolTitle
            : (existingCardData['toolTitle'] ?? '').toString(),
        'toolType': event.toolType,
        'serverName': event.serverName,
        'status': status,
        'summary': summary.isNotEmpty
            ? summary
            : (existingCardData['summary'] ?? '').toString(),
        'compileStatus': event.compileStatus.isNotEmpty
            ? event.compileStatus
            : (existingCardData['compileStatus'] ?? '').toString(),
        'executionRoute': event.executionRoute.isNotEmpty
            ? event.executionRoute
            : (existingCardData['executionRoute'] ?? '').toString(),
        'progress': progress.isNotEmpty
            ? progress
            : (existingCardData['progress'] ?? '').toString(),
        'argsJson': event.argsJson.isNotEmpty
            ? event.argsJson
            : (existingCardData['argsJson'] ?? '').toString(),
        'resultPreviewJson': resultPreviewJson.isNotEmpty
            ? resultPreviewJson
            : (existingCardData['resultPreviewJson'] ?? '').toString(),
        'rawResultJson': rawResultJson.isNotEmpty
            ? rawResultJson
            : (existingCardData['rawResultJson'] ?? '').toString(),
        'terminalOutput': terminalOutput,
        'terminalOutputDelta': event.terminalOutputDelta,
        'terminalSessionId':
            event.terminalSessionId ?? existingCardData['terminalSessionId'],
        'terminalStreamState': event.terminalStreamState.isNotEmpty
            ? event.terminalStreamState
            : (existingCardData['terminalStreamState'] ?? '').toString(),
        'workspaceId': event.workspaceId ?? existingCardData['workspaceId'],
        'artifacts': event.artifacts.isNotEmpty
            ? event.artifacts
            : (existingCardData['artifacts'] ?? const []),
        'actions': event.actions.isNotEmpty
            ? event.actions
            : (existingCardData['actions'] ?? const []),
        'success': event.success,
        'showScheduleAction': event.toolType == 'schedule',
        'showAlarmAction': event.toolType == 'alarm',
      };

      if (index == -1) {
        messages.insert(0, ChatMessageModel.cardMessage(cardData, id: cardId));
      } else {
        messages[index] = messages[index].copyWith(
          content: {'cardData': cardData, 'id': cardId},
        );
      }
    });
  }

  String _resolveTerminalOutput({
    required String existing,
    required AgentToolEventData event,
  }) {
    if (event.terminalOutput.isNotEmpty) {
      return _trimTerminalOutput(event.terminalOutput);
    }
    if (event.terminalOutputDelta.isNotEmpty) {
      return _trimTerminalOutput(existing + event.terminalOutputDelta);
    }
    return existing;
  }

  String _resolveToolStatus(AgentToolEventData event) {
    final normalized = event.status.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return event.success ? 'success' : 'error';
  }

  String _trimTerminalOutput(String value) {
    if (value.isEmpty) return value;

    var candidate = value;
    if (candidate.length > _maxTerminalOutputChars) {
      candidate = candidate.substring(
        candidate.length - _maxTerminalOutputChars,
      );
    }

    final lines = candidate.split('\n');
    if (lines.length > _maxTerminalOutputLines) {
      candidate = lines
          .sublist(lines.length - _maxTerminalOutputLines)
          .join('\n');
    }

    final wasTrimmed =
        candidate.length < value.length ||
        lines.length > _maxTerminalOutputLines;
    if (!wasTrimmed) {
      return candidate;
    }

    const notice = '[更早输出已省略]\n';
    final body = candidate.startsWith(notice)
        ? candidate.substring(notice.length)
        : candidate;
    final remaining = _maxTerminalOutputChars - notice.length;
    return '$notice${body.substring(body.length > remaining ? body.length - remaining : 0)}';
  }
}
