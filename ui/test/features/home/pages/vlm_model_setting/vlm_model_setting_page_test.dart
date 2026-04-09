import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/home/pages/vlm_model_setting/vlm_model_setting_page.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assistCoreChannel = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, (call) async {
      switch (call.method) {
        case 'listModelProviderProfiles':
          return <String, dynamic>{
            'profiles': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'provider-1',
                'name': 'DeepSeek',
                'baseUrl': 'https://api.openai.com/v1',
                'apiKey': 'sk-demo',
                'sourceType': 'custom',
                'readOnly': false,
                'ready': true,
                'statusText': '',
                'configured': true,
                'protocolType': 'openai_compatible',
              },
            ],
            'editingProfileId': 'provider-1',
          };
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, null);
  });

  testWidgets(
    'provider page renders header actions without layout exceptions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const VlmModelSettingPage(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('模型提供商'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-config-title')),
          matching: find.text('DeepSeek'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('provider-protocol-type-button')),
          matching: find.text('OpenAI'),
        ),
        findsOneWidget,
      );
      expect(find.text('模型类型'), findsNothing);
      final providerRight = tester
          .getTopRight(find.byKey(const Key('provider-config-title')))
          .dx;
      final protocolLeft = tester
          .getTopLeft(find.byKey(const Key('provider-protocol-type-button')))
          .dx;
      expect(protocolLeft - providerRight, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
