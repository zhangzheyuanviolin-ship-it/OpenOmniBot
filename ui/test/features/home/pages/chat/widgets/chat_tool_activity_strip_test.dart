import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_tool_activity_strip.dart';
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
    },
  );

  testWidgets('opens transcript dialog from thumbnail preview', (tester) async {
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'terminal',
        'toolTitle': '查看日志',
        'summary': '终端执行完成',
        'terminalOutput': 'line 1\nline 2',
      }),
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'browser',
        'toolTitle': '打开官网',
        'summary': '页面已加载',
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatToolActivityStrip(messages: messages)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(kChatToolActivityPreviewKey));
    await tester.pumpAndSettle();

    expect(find.text('查看日志'), findsWidgets);
    expect(find.textContaining('line 2'), findsWidgets);
    expect(find.textContaining('浏览器'), findsWidgets);
  });

  testWidgets('thumbnail aligns with anchor left edge and sits above the bar', (
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
    final barInk = tester.widget<Ink>(find.byKey(kChatToolActivityBarKey));
    final decoration = barInk.decoration! as BoxDecoration;
    final borderRadius = decoration.borderRadius! as BorderRadius;

    expect(previewTopLeft.dx, 52);
    expect(previewTopLeft.dy, lessThan(barTopLeft.dy));
    expect(titleTopLeft.dx, greaterThan(previewTopRight.dx - 12));
    expect(decoration.color, const Color(0xFFF9FCFF));
    expect(borderRadius.bottomLeft, Radius.zero);
    expect(borderRadius.bottomRight, Radius.zero);
  });
}
