import 'dart:convert';

import 'package:ui/features/home/pages/command_overlay/widgets/cards/terminal_output_utils.dart';
import 'package:ui/models/chat_message_model.dart';

const String kAgentToolSummaryCardType = 'agent_tool_summary';
const String kAgentToolTitleField = 'toolTitle';

List<Map<String, dynamic>> extractAgentToolCards(
  List<ChatMessageModel> messages,
) {
  return messages
      .map((message) => message.cardData)
      .whereType<Map<String, dynamic>>()
      .where(
        (cardData) =>
            (cardData['type'] ?? '').toString() == kAgentToolSummaryCardType,
      )
      .toList(growable: false);
}

Map<String, dynamic>? resolveActiveAgentToolCard(
  List<Map<String, dynamic>> cards,
) {
  for (final card in cards) {
    if ((card['status'] ?? '').toString() == 'running') {
      return card;
    }
  }
  if (cards.isEmpty) {
    return null;
  }
  return cards.first;
}

String resolveAgentToolTitle(Map<String, dynamic> cardData) {
  final explicit = (cardData[kAgentToolTitleField] ?? '').toString().trim();
  if (explicit.isNotEmpty) {
    return explicit;
  }

  final fromArgs = _extractToolTitleFromArgs(
    (cardData['argsJson'] ?? '').toString(),
  );
  if (fromArgs.isNotEmpty) {
    return fromArgs;
  }

  final summary = (cardData['summary'] ?? '').toString().trim();
  if (summary.isNotEmpty) {
    return summary;
  }

  final displayName = (cardData['displayName'] ?? '工具调用').toString().trim();
  final serverName = (cardData['serverName'] ?? '').toString().trim();
  if ((cardData['toolType'] ?? '').toString() == 'mcp' &&
      serverName.isNotEmpty) {
    return '$displayName · $serverName';
  }
  return displayName.isEmpty ? '工具调用' : displayName;
}

String resolveAgentToolTerminalOutput(Map<String, dynamic> cardData) {
  return TerminalOutputUtils.buildDisplayOutput(
    terminalOutput: (cardData['terminalOutput'] ?? '').toString(),
    rawResultJson: (cardData['rawResultJson'] ?? '').toString(),
    resultPreviewJson: (cardData['resultPreviewJson'] ?? '').toString(),
  );
}

String resolveAgentToolPreview(Map<String, dynamic> cardData) {
  final toolType = (cardData['toolType'] ?? '').toString();
  if (toolType == 'terminal') {
    final output = resolveAgentToolTerminalOutput(cardData).trim();
    if (output.isNotEmpty) {
      final nonEmptyLines = output
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      if (nonEmptyLines.isNotEmpty) {
        return nonEmptyLines.last;
      }
      return output;
    }
  }

  final progress = (cardData['progress'] ?? '').toString().trim();
  final summary = (cardData['summary'] ?? '').toString().trim();
  final title = resolveAgentToolTitle(cardData);
  if (progress.isNotEmpty && progress != title) {
    return progress;
  }
  if (summary.isNotEmpty && summary != title) {
    return summary;
  }
  return resolveAgentToolStatusLabel(cardData);
}

String resolveAgentToolStatusLabel(Map<String, dynamic> cardData) {
  final status = (cardData['status'] ?? 'running').toString();
  final toolType = (cardData['toolType'] ?? 'builtin').toString();
  if (status == 'interrupted') {
    return '中断';
  }
  switch (status) {
    case 'success':
      return '成功';
    case 'error':
      return '失败';
    default:
      if (toolType == 'terminal') return '运行中';
      if (toolType == 'browser') return '浏览中';
      if (toolType == 'mcp') return '响应中';
      if (toolType == 'memory') return '处理中';
      return '执行中';
  }
}

String resolveAgentToolTypeLabel(Map<String, dynamic> cardData) {
  switch ((cardData['toolType'] ?? '').toString()) {
    case 'terminal':
      return '终端';
    case 'browser':
      return '浏览器';
    case 'workspace':
      return '工作区';
    case 'schedule':
      return '定时';
    case 'alarm':
      return '提醒';
    case 'calendar':
      return '日历';
    case 'memory':
      return '记忆';
    case 'skill':
      return 'Skill';
    case 'subagent':
      return '子任务';
    case 'mcp':
      return 'MCP';
    default:
      return '工具';
  }
}

String buildAgentToolTranscript(
  List<Map<String, dynamic>> cards, {
  int maxTotalLines = 40,
  int maxTerminalLinesPerTool = 10,
}) {
  if (cards.isEmpty) {
    return '';
  }

  final transcriptLines = <String>[];
  for (final card in cards.reversed) {
    final title = resolveAgentToolTitle(card);
    transcriptLines.add('\$ $title');

    if ((card['toolType'] ?? '').toString() == 'terminal') {
      final output = resolveAgentToolTerminalOutput(card).trimRight();
      if (output.isNotEmpty) {
        final lines = output.split('\n');
        final start = lines.length > maxTerminalLinesPerTool
            ? lines.length - maxTerminalLinesPerTool
            : 0;
        transcriptLines.addAll(lines.sublist(start));
      } else {
        transcriptLines.add('> ${resolveAgentToolPreview(card)}');
      }
    } else {
      transcriptLines.add(
        '> ${resolveAgentToolTypeLabel(card)} · ${resolveAgentToolPreview(card)}',
      );
    }
    transcriptLines.add('');
  }

  if (transcriptLines.isEmpty) {
    return '';
  }

  var normalized = transcriptLines.join('\n').trimRight();
  if (maxTotalLines > 0) {
    final lines = normalized.split('\n');
    if (lines.length > maxTotalLines) {
      normalized = [
        '[更早记录已省略]',
        ...lines.sublist(lines.length - maxTotalLines),
      ].join('\n');
    }
  }
  return normalized;
}

String _extractToolTitleFromArgs(String argsJson) {
  final text = argsJson.trim();
  if (text.isEmpty) {
    return '';
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      return '';
    }
    return (decoded['tool_title'] ?? '').toString().trim();
  } catch (_) {
    return '';
  }
}
