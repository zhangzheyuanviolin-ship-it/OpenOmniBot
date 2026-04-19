import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/message_bubble.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/scene_model_config_service.dart';
import 'package:ui/services/voice_playback_channel_service.dart';
import 'package:ui/services/voice_playback_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBubble(
    WidgetTester tester, {
    required ChatMessageModel message,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() async {
    await VoicePlaybackCoordinator.instance.debugResetForTest();
  });

  tearDown(() async {
    await VoicePlaybackCoordinator.instance.debugResetForTest();
  });

  testWidgets('shows voice button only when voice scene is bound', (tester) async {
    final message = ChatMessageModel.assistantMessage('你好，世界', id: 'voice-msg');

    VoicePlaybackCoordinator.instance.debugSetAvailabilityForTest(
      isBound: false,
    );
    await pumpBubble(tester, message: message);
    expect(find.byTooltip('播放语音'), findsNothing);

    VoicePlaybackCoordinator.instance.debugSetAvailabilityForTest(
      isBound: true,
      config: const SceneVoiceConfig(),
    );
    await pumpBubble(tester, message: message);
    expect(find.byTooltip('播放语音'), findsOneWidget);
  });

  testWidgets('shows pause tooltip when message is playing', (tester) async {
    final message = ChatMessageModel.assistantMessage('你好，世界', id: 'voice-msg');

    VoicePlaybackCoordinator.instance.debugSetAvailabilityForTest(
      isBound: true,
      config: const SceneVoiceConfig(),
    );
    VoicePlaybackCoordinator.instance.debugSetMessageStateForTest(
      'voice-msg',
      const VoiceMessagePlaybackState(
        status: VoicePlaybackStatus.playing,
        canReplay: true,
      ),
    );

    await pumpBubble(tester, message: message);
    expect(find.byTooltip('暂停语音'), findsOneWidget);
  });
}
