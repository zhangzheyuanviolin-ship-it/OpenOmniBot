import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/agent_tool_transcript.dart';

void main() {
  test(
    'buildAgentToolTranscript renders non-terminal tool as pseudo command',
    () {
      final transcript = buildAgentToolTranscript({
        'toolName': 'file_read',
        'displayName': '读取文件',
        'toolType': 'workspace',
        'argsJson': jsonEncode({
          'path': '/workspace/README.md',
          'maxChars': 4000,
          'tool_title': '查看 README',
        }),
        'resultPreviewJson': jsonEncode({
          'path': '/workspace/README.md',
          'size': 32,
          'content': 'hello world',
        }),
        'status': 'success',
        'summary': '已读取文件',
      });

      expect(
        transcript.promptLine,
        r'$ file_read --path /workspace/README.md --maxChars 4000',
      );
      expect(transcript.outputText, contains('path: /workspace/README.md'));
      expect(transcript.outputText, contains('size: 32'));
      expect(transcript.outputText, contains('content: hello world'));
    },
  );

  test(
    'buildAgentToolTranscript renders terminal tool using native command',
    () {
      final transcript = buildAgentToolTranscript({
        'toolName': 'terminal_execute',
        'displayName': '终端执行',
        'toolType': 'terminal',
        'argsJson': jsonEncode({
          'command': 'git status',
          'workingDirectory': '/workspace',
        }),
        'terminalOutput': 'On branch main',
        'status': 'success',
        'summary': '终端命令执行成功',
      });

      expect(transcript.promptLine, r"$ cd /workspace && git status");
      expect(transcript.outputText, 'On branch main');
      expect(transcript.previewText, 'On branch main');
    },
  );
}
