import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';

void main() {
  const resolver = HdPadPaneLayoutResolver();

  test('uses defaults within supported width', () {
    final layout = resolver.resolve(1200);

    expect(layout.leftWidth, HdPadPaneLayoutResolver.defaultLeftWidth);
    expect(layout.rightWidth, HdPadPaneLayoutResolver.defaultRightWidth);
    expect(
      layout.centerWidth,
      1200 -
          HdPadPaneLayoutResolver.dividerHitWidth * 2 -
          HdPadPaneLayoutResolver.defaultLeftWidth -
          HdPadPaneLayoutResolver.defaultRightWidth,
    );
  });

  test('clamps oversized preferences to preserve minimum center width', () {
    final layout = resolver.resolve(
      960,
      preferredLeftWidth: 360,
      preferredRightWidth: 420,
    );

    expect(
      layout.leftWidth,
      greaterThanOrEqualTo(HdPadPaneLayoutResolver.minLeftWidth),
    );
    expect(
      layout.rightWidth,
      greaterThanOrEqualTo(HdPadPaneLayoutResolver.minRightWidth),
    );
    expect(
      layout.centerWidth,
      greaterThanOrEqualTo(HdPadPaneLayoutResolver.minCenterWidth),
    );
  });

  test('clamps saved widths to pane-specific bounds', () {
    final layout = resolver.resolve(
      1400,
      preferredLeftWidth: 120,
      preferredRightWidth: 1000,
    );

    expect(layout.leftWidth, HdPadPaneLayoutResolver.minLeftWidth);
    expect(
      layout.rightWidth,
      lessThanOrEqualTo(HdPadPaneLayoutResolver.maxRightWidth),
    );
    expect(
      layout.centerWidth,
      greaterThanOrEqualTo(HdPadPaneLayoutResolver.minCenterWidth),
    );
  });
}
