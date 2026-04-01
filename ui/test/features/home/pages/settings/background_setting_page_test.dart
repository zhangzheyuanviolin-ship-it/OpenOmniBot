import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/home/pages/settings/background_setting_page.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/widgets/app_background_widgets.dart';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    AppBackgroundService.notifier.value = AppBackgroundConfig.defaults;
  });

  tearDown(() async {
    AppBackgroundService.notifier.value = AppBackgroundConfig.defaults;
  });

  testWidgets('supports auto-saving appearance updates from the preview', (
    tester,
  ) async {
    AppBackgroundService.notifier.value = const AppBackgroundConfig(
      enabled: true,
      sourceType: AppBackgroundSourceType.remote,
      localImagePath: '',
      remoteImageUrl: 'https://example.com/existing-background.png',
      blurSigma: 10,
      frostOpacity: 0.2,
      brightness: 1,
      focalX: 0.1,
      focalY: -0.1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _SvgTestAssetBundle(),
          child: const BackgroundSettingPage(),
        ),
      ),
    );

    expect(find.text('外观设置'), findsOneWidget);
    expect(find.byType(AppBackgroundPreview), findsOneWidget);
    expect(find.textContaining('聊天文本 ·'), findsOneWidget);
    expect(find.byKey(const ValueKey('background-save-button')), findsNothing);
    expect(find.byKey(const ValueKey('background-reset-button')), findsNothing);
    expect(find.byKey(const ValueKey('background-source-none')), findsNothing);

    final workspacePreviewChip = find.byKey(
      const ValueKey('background-preview-kind-workspace'),
    );
    await tester.ensureVisible(workspacePreviewChip);
    await tester.tap(workspacePreviewChip, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Workspace 预览'), findsOneWidget);

    final remoteSourceChip = find.byKey(
      const ValueKey('background-source-remote'),
    );
    await tester.ensureVisible(remoteSourceChip);
    await tester.tap(remoteSourceChip);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('background-remote-url-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('appearance-text-color-field')),
      '#1D3E7B',
    );
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(
      AppBackgroundService.current.chatTextColorMode,
      AppBackgroundTextColorMode.custom,
    );
    expect(AppBackgroundService.current.chatTextHexColor, '#1D3E7B');

    await tester.ensureVisible(find.byType(Switch).first);
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(AppBackgroundService.current.enabled, isFalse);
  });

  testWidgets('flushes pending appearance changes when leaving immediately', (
    tester,
  ) async {
    AppBackgroundService.notifier.value = const AppBackgroundConfig(
      enabled: true,
      sourceType: AppBackgroundSourceType.remote,
      localImagePath: '',
      remoteImageUrl: 'https://example.com/existing-background.png',
      blurSigma: 10,
      frostOpacity: 0.2,
      brightness: 1,
      focalX: 0.1,
      focalY: -0.1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _SvgTestAssetBundle(),
          child: const BackgroundSettingPage(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('appearance-text-color-field')),
      '#1D3E7B',
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      AppBackgroundService.current.chatTextColorMode,
      AppBackgroundTextColorMode.custom,
    );
    expect(AppBackgroundService.current.chatTextHexColor, '#1D3E7B');
  });
}
