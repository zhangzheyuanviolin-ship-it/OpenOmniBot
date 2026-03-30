import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_widgets.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/message_bubble.dart';
import 'package:ui/models/chat_message_model.dart';

void main() {
  testWidgets('applies bottom overlay inset to the newest message', (
    tester,
  ) async {
    final messages = [
      ChatMessageModel.assistantMessage('最新一条', id: 'latest'),
      ChatMessageModel.userMessage('上一条', id: 'older'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            messages: messages,
            scrollController: ScrollController(),
            bottomOverlayInset: 128,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final padding = tester.widget<Padding>(
      find.byKey(const ValueKey('chat-message-list-item-0')),
    );

    expect(padding.padding, const EdgeInsets.only(bottom: 128));
  });

  testWidgets('completed thinking expands downward in reversed chat list', (
    tester,
  ) async {
    final messages = [
      ChatMessageModel.cardMessage({
        'type': 'deep_thinking',
        'thinkingContent': '第一行\n第二行\n第三行',
        'stage': 4,
        'isLoading': false,
        'isCollapsible': true,
      }, id: 'thinking-card'),
      ChatMessageModel.userMessage('上一条用户消息', id: 'older'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: ChatMessageList(
              messages: messages,
              scrollController: ScrollController(),
              onBeforeTaskExecute: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerFinder = find.text('思考完成');
    final headerTopBefore = tester.getTopLeft(headerFinder).dy;
    final cardTopBefore = tester
        .getTopLeft(find.byType(MessageBubble).first)
        .dy;

    await tester.tap(headerFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final headerTopMidAnimation = tester.getTopLeft(headerFinder).dy;
    final cardTopMidAnimation = tester
        .getTopLeft(find.byType(MessageBubble).first)
        .dy;

    await tester.pump(const Duration(milliseconds: 130));

    final headerTopAfter = tester.getTopLeft(headerFinder).dy;
    final cardTopAfter = tester.getTopLeft(find.byType(MessageBubble).first).dy;

    expect(headerTopMidAnimation, closeTo(headerTopBefore, 1.5));
    expect(headerTopAfter, closeTo(headerTopBefore, 1.5));
    expect(cardTopMidAnimation, closeTo(cardTopBefore, 1.5));
    expect(cardTopAfter, closeTo(cardTopBefore, 1.5));
    expect(find.textContaining('第一行'), findsOneWidget);
  });

  testWidgets('forwards user message long press callback', (tester) async {
    final message = ChatMessageModel.userMessage('长按这条消息', id: 'user-1');
    ChatMessageModel? pressedMessage;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            messages: [message],
            scrollController: ScrollController(),
            onBeforeTaskExecute: () async {},
            onUserMessageLongPressStart: (value, _) {
              pressedMessage = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('长按这条消息'));
    await tester.pumpAndSettle();

    expect(pressedMessage?.id, 'user-1');
  });
}
