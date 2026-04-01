import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/widgets/app_background_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preview renders dedicated layers for chat and workspace', (
    tester,
  ) async {
    const config = AppBackgroundConfig(
      enabled: true,
      sourceType: AppBackgroundSourceType.local,
      localImagePath: '/tmp/missing-background.png',
      remoteImageUrl: '',
      blurSigma: 8,
      frostOpacity: 0.2,
      brightness: 1,
      focalX: 0,
      focalY: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 420,
              child: AppBackgroundPreview(
                config: config,
                kind: BackgroundPreviewKind.chat,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('app-background-preview-chat')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 420,
              child: AppBackgroundPreview(
                config: config,
                kind: BackgroundPreviewKind.workspace,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('app-background-preview-workspace')),
      findsOneWidget,
    );
  });

  testWidgets('preview drag reports normalized focal point updates', (
    tester,
  ) async {
    Offset? lastOffset;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 420,
            child: AppBackgroundPreview(
              config: const AppBackgroundConfig(
                enabled: true,
                sourceType: AppBackgroundSourceType.local,
                localImagePath: '/tmp/missing-background.png',
                remoteImageUrl: '',
                blurSigma: 8,
                frostOpacity: 0.2,
                brightness: 1,
                focalX: 0,
                focalY: 0,
              ),
              kind: BackgroundPreviewKind.chat,
              onFocalPointChanged: (offset) {
                lastOffset = offset;
              },
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('app-background-preview-drag-chat')),
      const Offset(140, 210),
    );
    await tester.pump();

    expect(lastOffset, isNotNull);
    expect(lastOffset!.dx, greaterThan(0.8));
    expect(lastOffset!.dy, greaterThan(0.8));
  });
}
