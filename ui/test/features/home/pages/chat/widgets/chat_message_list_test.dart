import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_widgets.dart';
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
}
