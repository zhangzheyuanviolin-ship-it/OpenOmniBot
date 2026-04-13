import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_widgets.dart';

void main() {
  testWidgets('empty chat state offsets with bottom overlay inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageList(
            messages: const [],
            scrollController: ScrollController(),
            bottomOverlayInset: 128,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );

    await tester.pump();

    final animatedPadding = tester.widget<AnimatedPadding>(
      find.byType(AnimatedPadding),
    );

    expect(animatedPadding.padding, const EdgeInsets.only(bottom: 128));
    expect(find.text('有什么可以帮助你的？'), findsOneWidget);
  });
}
