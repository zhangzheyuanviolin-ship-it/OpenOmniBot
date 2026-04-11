import 'package:flutter_test/flutter_test.dart';
import 'package:ui/models/chat_message_model.dart';

void main() {
  test('ChatMessageModel normalizes integer-like doubles recursively', () {
    final message = ChatMessageModel.fromJson({
      'id': 'history-message',
      'type': 2.0,
      'user': 3.0,
      'content': {
        'id': 99.0,
        'dbId': 123.0,
        'cardData': {
          'type': 'deep_thinking',
          'stage': 4.0,
          'startTime': 1774600557281.0,
          'nested': {'count': 2.0},
          'items': [
            1.0,
            {'delay': 5.0},
            1.5,
          ],
        },
      },
      'createAt': 1774600557281.0,
    });

    expect(message.type, 2);
    expect(message.user, 3);
    expect(message.contentId, '99');
    expect(message.dbId, 123);
    expect(message.cardData?['stage'], 4);
    expect(message.cardData?['startTime'], 1774600557281);

    final nested = message.cardData?['nested'] as Map<String, dynamic>;
    expect(nested['count'], 2);

    final items = message.cardData?['items'] as List<dynamic>;
    expect(items[0], 1);
    expect((items[1] as Map<String, dynamic>)['delay'], 5);
    expect(items[2], 1.5);
    expect(message.createAt.millisecondsSinceEpoch, 1774600557281);
  });

  test('ChatMessageModel parses legacy createAt strings', () {
    final message = ChatMessageModel.fromJson({
      'id': 'legacy-message',
      'type': 1,
      'user': 2,
      'content': {'text': 'hello'},
      'createAt': '1774600557281',
    });

    expect(message.text, 'hello');
    expect(message.createAt.millisecondsSinceEpoch, 1774600557281);
  });

  test(
    'ChatMessageModel strips persisted pure-chat json frames from assistant text',
    () {
      final message = ChatMessageModel.fromJson({
        'id': 'chat-only-history',
        'type': 1,
        'user': 2,
        'content': {
          'text':
              '{"choices":[{"delta":{"reasoning_content":"先分析一下"}}]}'
              '这是最终回答。',
        },
        'createAt': '1774600557281',
      });

      expect(message.text, '这是最终回答。');
    },
  );
}
