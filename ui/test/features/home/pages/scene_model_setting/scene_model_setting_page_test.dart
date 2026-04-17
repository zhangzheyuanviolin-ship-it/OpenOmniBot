import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/home/pages/scene_model_setting/scene_model_setting_page.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/theme/app_theme.dart';

class _SvgTestAssetBundle extends CachingAssetBundle {
  static final Uint8List _svgBytes = Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<rect width="24" height="24" fill="#000000"/>'
      '</svg>',
    ),
  );

  @override
  Future<ByteData> load(String key) async {
    return ByteData.view(_svgBytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return utf8.decode(_svgBytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');

  Widget buildTestApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: DefaultAssetBundle(bundle: _SvgTestAssetBundle(), child: child),
    );
  }

  late Map<String, dynamic> savedVoiceConfig;

  setUp(() async {
    AssistsMessageService.initialize();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.init();
    savedVoiceConfig = <String, dynamic>{
      'autoPlay': false,
      'voiceId': 'default_zh',
      'stylePreset': '默认',
      'customStyle': '',
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getSceneModelCatalog':
              return <Map<String, dynamic>>[
                <String, dynamic>{
                  'sceneId': 'scene.voice',
                  'description': '负责 AI 回复文本的语音合成与播放',
                  'defaultModel': '',
                  'effectiveModel': '',
                  'effectiveProviderProfileId': '',
                  'effectiveProviderProfileName': '',
                  'boundProviderProfileId': '',
                  'boundProviderProfileName': '',
                  'transport': 'openai_compatible',
                  'configSource': 'builtin',
                  'overrideApplied': false,
                  'overrideModel': '',
                  'providerConfigured': false,
                  'bindingExists': false,
                  'bindingProfileMissing': false,
                },
              ];
            case 'getSceneModelBindings':
              return <Map<String, dynamic>>[];
            case 'listModelProviderProfiles':
              return <String, dynamic>{
                'profiles': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 'provider-1',
                    'name': 'Provider One',
                    'baseUrl': 'https://example.com/v1',
                    'apiKey': 'secret',
                    'configured': true,
                    'protocolType': 'openai_compatible',
                  },
                ],
                'editingProfileId': 'provider-1',
              };
            case 'fetchProviderModels':
              return <Map<String, dynamic>>[];
            case 'getSceneVoiceConfig':
              return savedVoiceConfig;
            case 'saveSceneVoiceConfig':
              savedVoiceConfig = Map<String, dynamic>.from(
                (call.arguments as Map).cast<String, dynamic>(),
              );
              return savedVoiceConfig;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('voice scene expands and saves voice settings', (tester) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp(const SceneModelSettingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('未绑定'), findsOneWidget);

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    expect(find.text('AI 响应完成后自动播放'), findsOneWidget);
    expect(find.text('自定义风格描述'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '更温柔一点');
    await tester.tap(find.text('保存语音设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(savedVoiceConfig['customStyle'], '更温柔一点');
  });
}
