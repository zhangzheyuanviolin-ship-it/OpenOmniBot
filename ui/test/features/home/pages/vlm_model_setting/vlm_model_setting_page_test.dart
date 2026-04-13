import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/home/pages/vlm_model_setting/vlm_model_setting_page.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assistCoreChannel = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );
  Map<String, dynamic> profilePayload({
    String baseUrl = 'https://api.openai.com/v1',
    String protocolType = 'openai_compatible',
  }) {
    return <String, dynamic>{
      'profiles': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'provider-1',
          'name': 'DeepSeek',
          'baseUrl': baseUrl,
          'apiKey': 'sk-demo',
          'sourceType': 'custom',
          'readOnly': false,
          'ready': true,
          'statusText': '',
          'configured': true,
          'protocolType': protocolType,
        },
      ],
      'editingProfileId': 'provider-1',
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, (call) async {
      switch (call.method) {
        case 'listModelProviderProfiles':
          return profilePayload();
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

  testWidgets('base url hint mentions trailing marker override', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const VlmModelSettingPage(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final baseUrlField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Base URL',
      ),
    );
    expect(baseUrlField.decoration?.hintText, contains('末尾加 #'));
  });

  testWidgets('anthropic profile shows full messages request url', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, (call) async {
      switch (call.method) {
        case 'listModelProviderProfiles':
          return profilePayload(
            baseUrl: 'https://api.anthropic.com',
            protocolType: 'anthropic',
          );
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const VlmModelSettingPage(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('https://api.anthropic.com/v1/messages'), findsOneWidget);
  });

  testWidgets('provider fields do not auto-save while focused', (tester) async {
    var saveCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, (call) async {
      switch (call.method) {
        case 'listModelProviderProfiles':
          return profilePayload();
        case 'saveModelProviderProfile':
          saveCalls += 1;
          final args = Map<dynamic, dynamic>.from(
            (call.arguments as Map?) ?? const <String, dynamic>{},
          );
          return <String, dynamic>{
            'id': 'provider-1',
            'name': (args['name'] ?? 'DeepSeek').toString(),
            'baseUrl': (args['baseUrl'] ?? '').toString(),
            'apiKey': (args['apiKey'] ?? '').toString(),
            'sourceType': 'custom',
            'readOnly': false,
            'ready': true,
            'statusText': '',
            'configured': true,
            'protocolType': (args['protocolType'] ?? 'openai_compatible')
                .toString(),
          };
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const VlmModelSettingPage(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Provider 名称',
    );
    await tester.tap(nameField);
    await tester.pump();
    await tester.enterText(nameField, 'DeepSeek Pro');

    await tester.pump(const Duration(milliseconds: 700));

    expect(saveCalls, 0);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(saveCalls, 1);
  });

  testWidgets('file sync does not reload provider fields while editing', (
    tester,
  ) async {
    var listCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, (call) async {
      switch (call.method) {
        case 'listModelProviderProfiles':
          listCalls += 1;
          return profilePayload();
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const VlmModelSettingPage(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(listCalls, 1);

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Provider 名称',
    );
    await tester.tap(nameField);
    await tester.pump();
    await tester.enterText(nameField, 'DeepSeek Pro');

    AssistsMessageService.dispatchAgentAiConfigChanged(
      const AgentAiConfigChangedEvent(source: 'file', path: '/tmp/config.json'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(listCalls, 1);
    expect(find.text('DeepSeek Pro'), findsOneWidget);
  });
}
