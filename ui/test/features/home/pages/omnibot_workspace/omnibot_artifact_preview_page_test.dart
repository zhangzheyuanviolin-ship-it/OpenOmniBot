import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/omnibot_workspace/omnibot_artifact_preview_page.dart';

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

  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'omnibot_artifact_preview_test_',
    );
    file = File('${tempDir.path}/note.txt');
    await file.writeAsString('hello workspace');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('collapses file actions into a single more-actions button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _SvgTestAssetBundle(),
          child: OmnibotArtifactPreviewPage(
            path: file.path,
            title: 'note.txt',
            previewKind: 'text',
            mimeType: 'text/plain',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(
      find.byKey(const ValueKey('artifact-preview-more-actions')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('artifact-preview-more-actions')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('系统打开'), findsOneWidget);
    expect(find.text('分享文件'), findsOneWidget);
  });
}
