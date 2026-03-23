import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/services/chat_service.dart';
import 'package:ui/models/chat_message_model.dart';

void main() {
  group('ChatService.getRecentMessages', () {
    ChatMessageModel makeMsg(String id, {int type = 1, int user = 1, bool isError = false}) {
      return ChatMessageModel(
        id: id,
        type: type,
        user: user,
        content: {'text': 'msg $id', 'id': id},
        isError: isError,
      );
    }

    test('returns all messages when count is below maxCount', () {
      final messages = [
        makeMsg('3', user: 2),
        makeMsg('2', user: 1),
        makeMsg('1', user: 1),
      ];
      final result = ChatService.getRecentMessages(messages);
      expect(result.length, 3);
    });

    test('returns most recent maxCount messages when list exceeds maxCount', () {
      // Messages are newest-first (index 0 = newest)
      final messages = List.generate(
        25,
        (i) => makeMsg('${25 - i}', user: i.isEven ? 1 : 2),
      );
      final result = ChatService.getRecentMessages(messages, maxCount: 20);
      expect(result.length, 20);
      // First result should be newest (index 0 of original list)
      expect(result.first.id, messages.first.id);
    });

    test('filters out card messages (type != 1)', () {
      final messages = [
        makeMsg('card', type: 2, user: 3),
        makeMsg('2', user: 2),
        makeMsg('1', user: 1),
      ];
      final result = ChatService.getRecentMessages(messages);
      expect(result.length, 2);
      expect(result.any((m) => m.type == 2), isFalse);
    });

    test('filters out error messages and their corresponding user messages', () {
      final aiErrorMsg = makeMsg('123-ai', user: 2, isError: true);
      final userMsg = makeMsg('123-user', user: 1);
      final normalMsg = makeMsg('456-user', user: 1);

      final messages = [aiErrorMsg, userMsg, normalMsg];
      final result = ChatService.getRecentMessages(messages);

      // Both error message and the corresponding user message should be filtered
      expect(result.any((m) => m.isError), isFalse);
      expect(result.any((m) => m.id == '123-user'), isFalse);
      expect(result.any((m) => m.id == '456-user'), isTrue);
    });

    test('default maxCount is 20 (not 10)', () {
      // Create 15 messages - all should be returned with default maxCount of 20
      final messages = List.generate(
        15,
        (i) => makeMsg('${15 - i}', user: i.isEven ? 1 : 2),
      );
      final result = ChatService.getRecentMessages(messages);
      expect(result.length, 15);
    });

    test('returns empty list for empty input', () {
      final result = ChatService.getRecentMessages([]);
      expect(result.isEmpty, isTrue);
    });
  });
}
