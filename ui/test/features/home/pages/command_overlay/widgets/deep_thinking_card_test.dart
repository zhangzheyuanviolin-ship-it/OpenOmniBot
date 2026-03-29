import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/card_widget_factory.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/deep_thinking_card.dart';

void main() {
  testWidgets('historical completed thinking card starts expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: '历史思考内容',
            stage: 4,
            isCollapsible: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('思考完成'), findsOneWidget);
    expect(find.textContaining('历史思考内容'), findsOneWidget);
  });

  testWidgets('thinking expansion stays anchored to the top edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: '第一行\n第二行',
            stage: 4,
            isCollapsible: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final animatedSize = tester.widget<AnimatedSize>(find.byType(AnimatedSize));

    expect(animatedSize.alignment, Alignment.topLeft);
  });

  testWidgets('card factory restores persisted deep thinking payloads', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardWidgetFactory.createCard(<String, dynamic>{
            'type': 'deep_thinking',
            'thinkingContent': '恢复后的思考内容',
            'stage': 4.0,
            'startTime': 1711711711000.0,
            'endTime': 1711711719000.0,
            'isLoading': false,
            'isExecutable': false,
            'isCollapsible': true,
            'taskID': 'agent-task-1',
          }, enableThinkingCollapse: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('思考完成'), findsOneWidget);
    expect(find.textContaining('恢复后的思考内容'), findsOneWidget);
  });
}
