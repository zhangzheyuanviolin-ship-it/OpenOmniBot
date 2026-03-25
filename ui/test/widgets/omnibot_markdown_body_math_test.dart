import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/widgets/omnibot_markdown_body.dart';

void main() {
  const plainText = '这是普通文本。';
  const inlineSample = r'这是行内公式 $E=mc^2$。';
  const blockSample = r'''
$$
\int_0^1 x^2 dx = \frac{1}{3}
$$
''';
  const inlineWideFractionSample =
      r'复杂分式 $\frac{\frac{a+b+c+d+e+f+g+h}{x+y+z+w}}{\frac{1}{2}+\frac{3}{4}+\frac{5}{6}}$。';
  const mixedSample = r'''
这是行内公式 $E=mc^2$。

$$
\int_0^1 x^2 dx = \frac{1}{3}
$$
''';

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }

  Future<void> expectNoException(
    WidgetTester tester, {
    required String data,
    bool selectable = false,
    bool useSelectionArea = false,
  }) async {
    await tester.pumpWidget(
      wrap(
        useSelectionArea
            ? SelectionArea(
                child: OmnibotMarkdownBody(
                  data: data,
                  baseStyle: const TextStyle(fontSize: 14),
                  selectable: selectable,
                ),
              )
            : OmnibotMarkdownBody(
                data: data,
                baseStyle: const TextStyle(fontSize: 14),
                selectable: selectable,
              ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('renders plain text without exception in default mode', (
    tester,
  ) async {
    await expectNoException(tester, data: plainText);
  });

  testWidgets('renders inline math without exception in default mode', (
    tester,
  ) async {
    await expectNoException(tester, data: inlineSample);
  });

  testWidgets('renders wide inline fraction without overflow exception', (
    tester,
  ) async {
    await expectNoException(tester, data: inlineWideFractionSample);
  });

  testWidgets('renders block math without exception in default mode', (
    tester,
  ) async {
    await expectNoException(tester, data: blockSample);
  });

  testWidgets('renders mixed math without exception in default mode', (
    tester,
  ) async {
    await expectNoException(tester, data: mixedSample);
  });

  testWidgets(
    'renders mixed math without exception when wrapped by SelectionArea',
    (tester) async {
      await expectNoException(
        tester,
        data: mixedSample,
        useSelectionArea: true,
      );
    },
  );

  testWidgets('renders mixed math without exception when selectable=true', (
    tester,
  ) async {
    await expectNoException(tester, data: mixedSample, selectable: true);
  });
}
