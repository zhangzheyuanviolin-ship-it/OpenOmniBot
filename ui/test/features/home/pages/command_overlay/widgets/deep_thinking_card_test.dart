import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/services/tool_card_detail_gesture_gate.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/card_widget_factory.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/deep_thinking_card.dart';

void main() {
  testWidgets(
    'historical completed thinking card stays visible after restore',
    (tester) async {
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
      expect(find.byType(DeepThinkingCard), findsOneWidget);
    },
  );

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
    expect(find.byType(DeepThinkingCard), findsOneWidget);
  });

  testWidgets('auto-collapses when completion settles after staged updates', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: '流式思考内容',
            stage: 3,
            isLoading: true,
            isCollapsible: false,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: '流式思考内容',
            stage: 4,
            isLoading: true,
            isCollapsible: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('流式思考内容'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: '流式思考内容',
            stage: 4,
            isLoading: false,
            isCollapsible: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('思考完成'), findsOneWidget);
    expect(find.textContaining('流式思考内容'), findsNothing);
  });

  testWidgets('nested thinking scroll hands off leftover drag at bottom edge', (
    tester,
  ) async {
    final parentController = ScrollController();

    await tester.pumpWidget(
      _buildNestedThinkingHarness(parentController: parentController),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    final innerScrollable = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(Scrollable),
    );
    final innerState = tester.state<ScrollableState>(innerScrollable);

    expect(innerState.position.pixels, 0);
    expect(parentController.offset, 0);

    await tester.drag(innerScrollable, const Offset(0, -80));
    await tester.pump();

    expect(innerState.position.pixels, greaterThan(0));
    expect(parentController.offset, 0);

    innerState.position.jumpTo(innerState.position.maxScrollExtent - 20);
    await tester.pump();

    await tester.drag(innerScrollable, const Offset(0, -60));
    await tester.pump();

    expect(
      innerState.position.pixels,
      closeTo(innerState.position.maxScrollExtent, 1),
    );
    expect(parentController.offset, greaterThan(0));
    expect(
      parentController.offset,
      lessThan(parentController.position.maxScrollExtent),
    );
    expect(parentController.offset, lessThan(120));
  });

  testWidgets(
    'same drag starts on inner content then smoothly hands off after bottom',
    (tester) async {
      final parentController = ScrollController();

      await tester.pumpWidget(
        _buildNestedThinkingHarness(parentController: parentController),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      final innerScrollable = find.descendant(
        of: find.byType(DeepThinkingCard),
        matching: find.byType(Scrollable),
      );
      final innerState = tester.state<ScrollableState>(innerScrollable);

      expect(innerState.position.pixels, 0);
      expect(parentController.offset, 0);

      final gesture = await tester.startGesture(
        tester.getCenter(innerScrollable),
      );
      final stepCount = (innerState.position.maxScrollExtent / 80).ceil() + 2;
      for (var index = 0; index < stepCount; index++) {
        await gesture.moveBy(const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        innerState.position.pixels,
        closeTo(innerState.position.maxScrollExtent, 1),
      );

      expect(parentController.offset, greaterThan(0));
      expect(
        parentController.offset,
        lessThan(parentController.position.maxScrollExtent),
      );
      expect(parentController.offset, lessThan(200));
    },
  );

  testWidgets('nested thinking scroll hands off upward drag from top edge', (
    tester,
  ) async {
    final parentController = ScrollController();

    await tester.pumpWidget(
      _buildNestedThinkingHarness(parentController: parentController),
    );
    await tester.pumpAndSettle();

    parentController.jumpTo(180);
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    final innerScrollable = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(Scrollable),
    );

    final before = parentController.offset;
    await tester.drag(innerScrollable, const Offset(0, 60));
    await tester.pump();

    expect(parentController.offset, lessThan(before));
    expect(parentController.offset, greaterThan(0));
  });

  testWidgets('thinking content drag is isolated from page-level listeners', (
    tester,
  ) async {
    final parentController = ScrollController();

    expect(ToolCardDetailGestureGate.hasActivePointers, isFalse);

    await tester.pumpWidget(
      _buildNestedThinkingHarness(parentController: parentController),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    final innerScrollable = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(Scrollable),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(innerScrollable),
    );
    await tester.pump();

    expect(ToolCardDetailGestureGate.hasActivePointers, isTrue);

    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(ToolCardDetailGestureGate.hasActivePointers, isFalse);
  });

  testWidgets('thinking content keeps ballistic scrolling after fling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: List.generate(
              120,
              (index) => '第 ${index + 1} 行思考内容，验证抬手后的惯性滚动。',
            ).join('\n'),
            stage: 4,
            isLoading: false,
            isCollapsible: false,
            maxHeight: 120,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final innerScrollable = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(Scrollable),
    );
    final innerState = tester.state<ScrollableState>(innerScrollable);

    innerState.position.jumpTo(200);
    await tester.pump();

    await tester.fling(innerScrollable, const Offset(0, -120), 800);
    await tester.pump();

    final afterRelease = innerState.position.pixels;
    expect(innerState.position.activity, isA<BallisticScrollActivity>());
    await tester.pump(const Duration(milliseconds: 80));

    expect(innerState.position.pixels, greaterThan(afterRelease));
  });

  testWidgets('completed thinking expands from top after prior bottom scroll', (
    tester,
  ) async {
    final longThinkingText = List.generate(
      80,
      (index) => '第 ${index + 1} 行思考内容，验证展开后重置到顶部。',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: longThinkingText,
            stage: 4,
            isLoading: false,
            isCollapsible: false,
            maxHeight: 120,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var innerScrollable = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(Scrollable),
    );
    var innerState = tester.state<ScrollableState>(innerScrollable);
    innerState.position.jumpTo(innerState.position.maxScrollExtent);
    await tester.pump();

    expect(innerState.position.pixels, innerState.position.maxScrollExtent);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeepThinkingCard(
            thinkingText: longThinkingText,
            stage: 4,
            isLoading: false,
            isCollapsible: true,
            maxHeight: 120,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    innerScrollable = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(Scrollable),
    );
    innerState = tester.state<ScrollableState>(innerScrollable);

    expect(
      innerState.position.pixels,
      closeTo(innerState.position.minScrollExtent, 1),
    );
  });
}

Widget _buildNestedThinkingHarness({
  required ScrollController parentController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          height: 320,
          child: SingleChildScrollView(
            controller: parentController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 180),
                DeepThinkingCard(
                  thinkingText: List.generate(
                    80,
                    (index) => '第 ${index + 1} 行思考内容，保留足够高度用于滚动联动测试。',
                  ).join('\n'),
                  stage: 4,
                  isLoading: false,
                  isCollapsible: true,
                  maxHeight: 120,
                  parentScrollController: parentController,
                ),
                const SizedBox(height: 960),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
