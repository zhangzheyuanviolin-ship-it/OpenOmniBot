import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat_history/widgets/chat_history_conversation_item.dart';
import 'package:ui/models/conversation_model.dart';

void main() {
  testWidgets('tap still opens the conversation item', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        child: ChatHistoryConversationItem(
          conversation: _conversation(id: 1, title: 'Conversation A'),
          onTap: () => tapCount++,
          onDelete: () {},
        ),
      ),
    );

    await tester.tap(find.text('Conversation A'));
    await tester.pumpAndSettle();

    expect(tapCount, 1);
  });

  testWidgets('tap delete action triggers delete callback once', (
    tester,
  ) async {
    var deleteCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        child: ChatHistoryConversationItem(
          conversation: _conversation(id: 2, title: 'Conversation B'),
          onTap: () {},
          onDelete: () => deleteCount++,
        ),
      ),
    );

    await tester.drag(find.byType(Slidable), const Offset(-220, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CustomSlidableAction));
    await tester.pumpAndSettle();

    expect(deleteCount, 1);
  });

  testWidgets('dragging far still exposes a quick delete action', (
    tester,
  ) async {
    var deleteCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        child: ChatHistoryConversationItem(
          conversation: _conversation(id: 3, title: 'Conversation C'),
          onTap: () {},
          onDelete: () => deleteCount++,
        ),
      ),
    );

    await tester.drag(find.byType(Slidable), const Offset(-800, 0));
    await tester.pumpAndSettle();

    expect(find.byType(CustomSlidableAction), findsOneWidget);

    await tester.tap(find.byType(CustomSlidableAction));
    await tester.pumpAndSettle();

    expect(deleteCount, 1);
  });

  testWidgets('renders a mode badge for OpenClaw threads', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        child: ChatHistoryConversationItem(
          conversation: _conversation(
            id: 4,
            title: 'Conversation D',
            mode: ConversationMode.openclaw,
          ),
          onTap: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('OpenClaw'), findsOneWidget);
  });
}

Widget _buildTestApp({required Widget child}) {
  return DefaultAssetBundle(
    bundle: _TestAssetBundle(),
    child: MaterialApp(
      home: Scaffold(
        body: SlidableAutoCloseBehavior(child: ListView(children: [child])),
      ),
    ),
  );
}

ConversationModel _conversation({
  required int id,
  required String title,
  ConversationMode mode = ConversationMode.normal,
}) {
  return ConversationModel(
    id: id,
    mode: mode,
    title: title,
    summary: 'Summary',
    status: 0,
    lastMessage: 'Last message',
    messageCount: 3,
    createdAt: DateTime(2026, 3, 20, 9).millisecondsSinceEpoch,
    updatedAt: DateTime(2026, 3, 20, 10).millisecondsSinceEpoch,
  );
}

class _TestAssetBundle extends CachingAssetBundle {
  static const String _svg = '''
<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="20" height="20" fill="#FFFFFF"/>
</svg>
''';

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_svg));
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return _svg;
  }
}
