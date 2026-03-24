import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_widgets.dart';

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

class _ChatAppBarHarness extends StatefulWidget {
  const _ChatAppBarHarness({this.isBrowserEnabled = false});

  final bool isBrowserEnabled;

  @override
  State<_ChatAppBarHarness> createState() => _ChatAppBarHarnessState();
}

class _ChatAppBarHarnessState extends State<_ChatAppBarHarness> {
  ChatIslandDisplayLayer _displayLayer = ChatIslandDisplayLayer.mode;
  ChatSurfaceMode _activeMode = ChatSurfaceMode.normal;
  int _browserTapCount = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DefaultAssetBundle(
        bundle: _SvgTestAssetBundle(),
        child: Scaffold(
          body: Column(
            children: [
              ChatAppBar(
                onMenuTap: () {},
                onCompanionTap: () {},
                activeMode: _activeMode,
                onModeChanged: (value) {
                  setState(() {
                    _activeMode = value;
                  });
                },
                activeModelId: 'gpt-5.4',
                displayLayer: _displayLayer,
                onDisplayLayerChanged: (value) {
                  setState(() {
                    _displayLayer = value;
                  });
                },
                onTerminalTap: () {},
                onBrowserTap: () {
                  setState(() {
                    _browserTapCount += 1;
                  });
                },
                isBrowserEnabled: widget.isBrowserEnabled,
                activeToolType: null,
              ),
              Text('layer:${_displayLayer.wireName}'),
              Text('browserTaps:$_browserTapCount'),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('reveals model layer after idle delay in normal chat', (
    tester,
  ) async {
    await tester.pumpWidget(const _ChatAppBarHarness());

    expect(find.text('layer:mode'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1800));

    expect(find.text('layer:model'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);
  });

  testWidgets('supports vertical switching between model and tools layers', (
    tester,
  ) async {
    await tester.pumpWidget(const _ChatAppBarHarness());

    await tester.drag(find.byType(ChatModeSlider), const Offset(0, -42));
    await tester.pumpAndSettle();

    expect(find.text('layer:model'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);

    await tester.drag(find.text('gpt-5.4'), const Offset(0, 42));
    await tester.pumpAndSettle();

    expect(find.text('layer:tools'), findsOneWidget);
    expect(find.text('终端'), findsOneWidget);
    expect(find.text('浏览器'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-island-browser-button')));
    await tester.pumpAndSettle();

    expect(find.text('browserTaps:0'), findsOneWidget);
  });
}
