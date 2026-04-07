import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_tool_activity_strip.dart';
import 'package:ui/features/home/pages/command_overlay/services/tool_card_detail_gesture_gate.dart';
import 'package:ui/models/chat_message_model.dart';

void main() {
  testWidgets(
    'renders current tool title and expands history without duplicating current item',
    (tester) async {
      final messages = [
        ChatMessageModel.cardMessage({
          'type': 'agent_tool_summary',
          'status': 'running',
          'toolType': 'terminal',
          'toolTitle': '检查 git 状态',
          'summary': '终端正在运行',
          'terminalOutput': 'git status\nOn branch main',
        }),
        ChatMessageModel.cardMessage({
          'type': 'agent_tool_summary',
          'status': 'success',
          'toolType': 'workspace',
          'toolTitle': '读取配置文件',
          'summary': '已读取 app.yaml',
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatToolActivityStrip(messages: messages)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kChatToolActivityBarKey), findsOneWidget);
      expect(find.text('检查 git 状态'), findsOneWidget);

      await tester.tap(find.byKey(kChatToolActivityToggleKey));
      await tester.pumpAndSettle();

      expect(find.byKey(kChatToolActivityPanelKey), findsOneWidget);
      expect(find.byKey(kChatToolActivityPreviewKey), findsNothing);
      expect(find.byType(ToolActivityRow), findsNWidgets(2));
      expect(find.text('检查 git 状态'), findsOneWidget);
      expect(find.text('读取配置文件'), findsOneWidget);

      final rowHeight = tester
          .getSize(find.byType(ToolActivityRow).first)
          .height;
      final historyRowHeight = tester
          .getSize(find.byType(ToolActivityRow).last)
          .height;
      final terminalTypeRight = tester.getTopRight(find.text('终端')).dx;
      final workspaceTypeRight = tester.getTopRight(find.text('工作区')).dx;
      final runningTagRight = tester.getTopRight(find.text('运行中')).dx;
      final successTagRight = tester.getTopRight(find.text('成功')).dx;

      expect(rowHeight, closeTo(32, 0.1));
      expect(historyRowHeight, closeTo(rowHeight, 0.1));
      expect(terminalTypeRight, closeTo(workspaceTypeRight, 1));
      expect(runningTagRight, closeTo(successTagRight, 1));
    },
  );

  testWidgets('thumbnail opens current tool detail only', (tester) async {
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'terminal',
        'toolName': 'terminal_execute',
        'toolTitle': '查看日志',
        'summary': '终端执行完成',
        'argsJson': jsonEncode({
          'command': 'tail -n 2 app.log',
          'workingDirectory': '/workspace',
        }),
        'terminalOutput': 'line 1\nline 2',
      }),
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'browser',
        'toolName': 'browser_use',
        'toolTitle': '打开官网',
        'summary': '页面已加载',
        'argsJson': jsonEncode({'url': 'https://omnimind.ai'}),
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatToolActivityStrip(messages: messages)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(kChatToolActivityPreviewKey),
        matching: find.text(r'$ cd /workspace && tail -n 2 app.log'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(kChatToolActivityPreviewKey));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);

    expect(
      find.descendant(of: dialog, matching: find.text('查看日志')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('tail -n 2 app.log', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('line 2', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('打开官网')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('页面已加载')),
      findsNothing,
    );
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(
      find.descendant(of: dialog, matching: find.text('终端')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('成功')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('终端 · 成功')),
      findsNothing,
    );
  });

  testWidgets('expanded history row opens its own tool detail', (tester) async {
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'terminal',
        'toolName': 'terminal_execute',
        'toolTitle': '查看日志',
        'summary': '终端执行完成',
        'argsJson': jsonEncode({
          'command': 'tail -n 2 app.log',
          'workingDirectory': '/workspace',
        }),
        'terminalOutput': 'line 1\nline 2',
      }),
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'browser',
        'toolName': 'browser_use',
        'toolTitle': '打开官网',
        'summary': '页面已加载',
        'argsJson': jsonEncode({
          'url': 'https://omnimind.ai/docs',
          'query': 'docs',
        }),
        'resultPreviewJson': jsonEncode({
          'currentUrl': 'https://omnimind.ai/docs',
          'title': 'Omnimind Docs',
        }),
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatToolActivityStrip(messages: messages)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(kChatToolActivityToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开官网'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);

    expect(
      find.descendant(of: dialog, matching: find.text('打开官网')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
          'browser_use --url https://omnimind.ai/docs --query docs',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
          'currentUrl: https://omnimind.ai/docs',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
          'title: Omnimind Docs',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('line 2', findRichText: true),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('浏览器')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('成功')),
      findsOneWidget,
    );
  });

  testWidgets('timeout thumbnail and detail dialog render dedicated status', (
    tester,
  ) async {
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'timeout',
        'toolType': 'terminal',
        'toolName': 'terminal_execute',
        'toolTitle': '等待超时',
        'summary': '终端命令等待超时，可能仍在后台继续运行。',
        'argsJson': jsonEncode({
          'command': 'sleep 10',
          'workingDirectory': '/workspace',
        }),
        'terminalOutput': 'still running',
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatToolActivityStrip(messages: messages)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(kChatToolActivityPreviewKey),
        matching: find.text(r'$ cd /workspace && sleep 10'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(kChatToolActivityPreviewKey));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);

    expect(
      find.descendant(of: dialog, matching: find.text('超时')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('sleep 10', findRichText: true),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('still running', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('occupied height stays stable when expanding history', (
    tester,
  ) async {
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'running',
        'toolType': 'terminal',
        'toolTitle': '检查 git 状态',
        'summary': '终端正在运行',
        'terminalOutput': 'git status\nOn branch main',
      }),
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'workspace',
        'toolTitle': '读取配置文件',
        'summary': '已读取 app.yaml',
      }),
    ];
    final reportedHeights = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatToolActivityStrip(
            messages: messages,
            onOccupiedHeightChanged: reportedHeights.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialHeight = reportedHeights.single;

    await tester.tap(find.byKey(kChatToolActivityToggleKey));
    await tester.pumpAndSettle();

    expect(reportedHeights.last, closeTo(initialHeight, 0.1));
    expect(reportedHeights.length, 1);
  });

  testWidgets(
    'thumbnail overlays the bar on the left and the bar is slightly narrower',
    (tester) async {
      final messages = [
        ChatMessageModel.cardMessage({
          'type': 'agent_tool_summary',
          'status': 'running',
          'toolType': 'terminal',
          'toolTitle': '检查 git 状态',
          'summary': '终端正在运行',
          'terminalOutput': 'git status\nOn branch main',
        }),
        ChatMessageModel.cardMessage({
          'type': 'agent_tool_summary',
          'status': 'success',
          'toolType': 'workspace',
          'toolTitle': '读取配置文件',
          'summary': '已读取 app.yaml',
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 52,
                  bottom: 24,
                  width: 280,
                  child: ChatToolActivityStrip(
                    messages: messages,
                    anchorRect: const Rect.fromLTWH(52, 0, 280, 0),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final previewTopLeft = tester.getTopLeft(
        find.byKey(kChatToolActivityPreviewKey),
      );
      final previewTopRight = tester.getTopRight(
        find.byKey(kChatToolActivityPreviewKey),
      );
      final barTopLeft = tester.getTopLeft(find.byKey(kChatToolActivityBarKey));
      final titleTopLeft = tester.getTopLeft(find.text('检查 git 状态'));
      final barSize = tester.getSize(find.byKey(kChatToolActivityBarKey));
      final barShape = tester.widget<PhysicalShape>(
        find.byKey(kChatToolActivityBarKey),
      );

      expect(previewTopLeft.dx, 52);
      expect(previewTopLeft.dy, lessThan(barTopLeft.dy));
      expect(barTopLeft.dx, closeTo(72, 0.1));
      expect(barSize.width, closeTo(240, 0.1));
      expect(titleTopLeft.dx, greaterThan(previewTopRight.dx - 12));
      expect(barShape.color, const Color(0xFFF9FCFF));
      expect(find.text('运行中'), findsOneWidget);
      expect(find.text('1/2'), findsNothing);
    },
  );

  testWidgets('expanded strip can be dismissed by tapping outside', (
    tester,
  ) async {
    var expanded = true;
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'running',
        'toolType': 'terminal',
        'toolTitle': '检查 git 状态',
        'summary': '终端正在运行',
      }),
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'workspace',
        'toolTitle': '读取配置文件',
        'summary': '已读取 app.yaml',
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Stack(
                children: [
                  if (expanded)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => setState(() => expanded = false),
                      ),
                    ),
                  Positioned(
                    left: 52,
                    bottom: 24,
                    width: 280,
                    child: ChatToolActivityStrip(
                      messages: messages,
                      anchorRect: const Rect.fromLTWH(52, 0, 280, 0),
                      expanded: expanded,
                      onExpandedChanged: (value) =>
                          setState(() => expanded = value),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kChatToolActivityPanelKey), findsOneWidget);

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();

    expect(find.byKey(kChatToolActivityPreviewKey), findsOneWidget);
  });

  testWidgets('expanded history drawer holds gesture gate while dragging', (
    tester,
  ) async {
    final messages = List<ChatMessageModel>.generate(6, (index) {
      return ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': index == 0 ? 'running' : 'success',
        'toolType': 'workspace',
        'toolTitle': '工具调用 ${index + 1}',
        'summary': '结果 ${index + 1}',
      });
    });

    addTearDown(() {
      if (ToolCardDetailGestureGate.hasActivePointers) {
        fail('gesture gate should be released after the drag completes');
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 52,
                bottom: 24,
                width: 280,
                child: ChatToolActivityStrip(
                  messages: messages,
                  anchorRect: const Rect.fromLTWH(52, 0, 280, 0),
                  expanded: true,
                  onExpandedChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panelCenter = tester.getCenter(find.byKey(kChatToolActivityPanelKey));
    final gesture = await tester.startGesture(panelCenter);
    await tester.pump();

    expect(ToolCardDetailGestureGate.hasActivePointers, isTrue);

    await gesture.moveBy(const Offset(0, -48));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ToolCardDetailGestureGate.hasActivePointers, isFalse);
  });
}
