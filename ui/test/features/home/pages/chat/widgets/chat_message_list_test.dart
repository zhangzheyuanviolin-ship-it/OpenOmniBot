import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/deep_thinking_card.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_widgets.dart';
import 'package:ui/l10n/generated/app_localizations.dart';
import 'package:ui/models/chat_message_model.dart';

void main() {
  testWidgets('empty chat state offsets with bottom overlay inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildLocalizedApp(
        child: ChatMessageList(
          messages: const [],
          scrollController: ScrollController(),
          bottomOverlayInset: 128,
          onBeforeTaskExecute: () async {},
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

  testWidgets(
    'parent handoff keeps list away from latest on follow-up frames',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildMessagesWithThinkingCard();

      await tester.pumpWidget(
        _buildChatMessageListHarness(
          controller: controller,
          messages: messages,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );

      final deepThinkingCard = find.descendant(
        of: find.byType(ChatMessageList),
        matching: find.byType(DeepThinkingCard),
      );
      expect(deepThinkingCard, findsOneWidget);

      await tester.tap(
        find.descendant(of: deepThinkingCard, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();

      final dragStart =
          tester.getTopLeft(deepThinkingCard) + const Offset(120, 96);
      await tester.dragFrom(dragStart, const Offset(0, 60));
      await tester.pump();

      final movedOffset = controller.offset;
      expect(movedOffset, lessThan(controller.position.maxScrollExtent - 48));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      expect(controller.offset, closeTo(movedOffset, 1));
    },
  );

  testWidgets('list resumes auto-follow after layout returns it to latest', (
    tester,
  ) async {
    final controller = ScrollController();
    var messages = _buildMessagesWithThinkingCard();
    late StateSetter setState;

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: StatefulBuilder(
          builder: (context, stateSetter) {
            setState = stateSetter;
            return SizedBox(
              width: 400,
              height: 520,
              child: ChatMessageList(
                messages: messages,
                scrollController: controller,
                onBeforeTaskExecute: () async {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deepThinkingCard = find.descendant(
      of: find.byType(ChatMessageList),
      matching: find.byType(DeepThinkingCard),
    );
    await tester.tap(
      find.descendant(of: deepThinkingCard, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    final dragStart =
        tester.getTopLeft(deepThinkingCard) + const Offset(120, 96);
    await tester.dragFrom(dragStart, const Offset(0, 60));
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(controller.position.maxScrollExtent));

    setState(() {
      messages = <ChatMessageModel>[
        messages.first,
        ...messages.skip(1).take(1),
      ];
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));

    setState(() {
      messages = <ChatMessageModel>[
        ChatMessageModel.assistantMessage('新的最新消息', id: 'new-latest'),
        ...messages,
      ];
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
  });
}

Widget _buildChatMessageListHarness({
  required ScrollController controller,
  required List<ChatMessageModel> messages,
}) {
  return _buildLocalizedApp(
    child: SizedBox(
      width: 400,
      height: 520,
      child: ChatMessageList(
        messages: messages,
        scrollController: controller,
        onBeforeTaskExecute: () async {},
      ),
    ),
  );
}

Widget _buildLocalizedApp({required Widget child}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

List<ChatMessageModel> _buildMessagesWithThinkingCard() {
  return [
    ChatMessageModel.cardMessage(<String, dynamic>{
      'type': 'deep_thinking',
      'thinkingContent': List.generate(
        80,
        (index) => '第 ${index + 1} 行思考内容，供消息列表滚动回归测试使用。',
      ).join('\n'),
      'stage': 4,
      'isLoading': false,
      'isCollapsible': true,
      'taskID': 'thinking-card',
    }, id: 'thinking-card'),
    ...List.generate(12, (index) {
      return ChatMessageModel.assistantMessage(
        List.generate(
          4,
          (line) => '较早消息 ${index + 1} - 第 ${line + 1} 行',
        ).join('\n'),
        id: 'older-$index',
      );
    }),
  ];
}
