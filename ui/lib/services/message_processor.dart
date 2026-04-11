import 'dart:async';
import 'dart:convert';

import 'package:ui/models/block_models.dart';

import 'assists_core_service.dart';

/// Service responsible for processing AI messages and converting them to domain objects
class MessageProcessor {
  static final StreamController<AIResponse> _aiResponseController =
      StreamController<AIResponse>.broadcast();
  static final StreamController<AIChunkResponse> _chunkResponseController =
      StreamController<AIChunkResponse>.broadcast();

  /// A broadcast stream of AI responses pushed from native via onCardPush
  static Stream<AIResponse> get aiResponseStream =>
      _aiResponseController.stream;

  /// A broadcast stream of chunk responses pushed from native via onMessagePush
  static Stream<AIChunkResponse> get chunkResponseStream =>
      _chunkResponseController.stream;

  /// Initialize listening to native onCardPush and onMessagePush events
  static void initialize() {
    AssistsMessageService.initialize();

    // 监听onCardPush事件
    AssistsMessageService.setOnCardPushCallback((cardData) {
      try {
        // cardData is already a Map<String, dynamic> for a single block with task_id
        final AIResponse response = AIResponse.fromJson(cardData);
        _aiResponseController.add(response);
      } catch (e) {
        _aiResponseController.add(
          AIResponse(
            taskId: 'error',
            replyId: 'error',
            blocks: [
              UnknownBlock(
                'error',
                raw: {
                  'error': 'Failed to handle onCardPush: $e',
                  'original_data': cardData,
                },
                taskId: 'error',
              ),
            ],
          ),
        );
      }
    });

    // 监听onMessagePush事件（流式数据）
    AssistsMessageService.addOnChatTaskMessageCallBack((
      messageId,
      chunkData,
      type,
    ) {
      // try {
      //   final chunkResponse = AIChunkResponse.fromJson(chunkData, messageId);
      //   _chunkResponseController.add(chunkResponse);
      // } catch (e) {
      //   print('Failed to handle onMessagePush: $e');
      // }
    });
  }

  /// Dispose stream resources
  static Future<void> dispose() async {
    await _aiResponseController.close();
    await _chunkResponseController.close();
  }

  /// Processes raw JSON response from AI and converts it to AIResponse domain object
  static AIResponse processAIResponse(String jsonString) {
    try {
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      return AIResponse.fromJson(jsonData);
    } catch (e) {
      // If parsing fails, return an error response with unknown block
      return AIResponse(
        taskId: 'error',
        replyId: 'error',
        blocks: [
          UnknownBlock(
            'error',
            raw: {
              'error': 'Failed to parse AI response: $e',
              'original_data': jsonString,
            },
            taskId: 'error',
          ),
        ],
      );
    }
  }

  /// Processes raw JSON response from AI and converts it to a list of blocks
  static List<Block> processBlocks(String jsonString) {
    final response = processAIResponse(jsonString);
    return response.blocks;
  }

  static void addAiResponse(aiResponse) {
    _aiResponseController.add(aiResponse);
  }
}
