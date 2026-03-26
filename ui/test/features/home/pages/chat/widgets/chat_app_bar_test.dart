import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  const _ChatAppBarHarness();

  @override
  State<_ChatAppBarHarness> createState() => _ChatAppBarHarnessState();
}

class _ChatAppBarHarnessState extends State<_ChatAppBarHarness> {
  ChatIslandDisplayLayer _displayLayer = ChatIslandDisplayLayer.model;
  ChatSurfaceMode _activeMode = ChatSurfaceMode.normal;
  int _browserTapCount = 0;
  int _envTapCount = 0;

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
                onTerminalEnvironmentTap: (_) {
                  setState(() {
                    _envTapCount += 1;
                  });
                },
                onTerminalTap: () {},
                onBrowserTap: () {
                  setState(() {
                    _browserTapCount += 1;
                  });
                },
                hasTerminalEnvironment: true,
                isBrowserEnabled: false,
                activeToolType: null,
              ),
              Text('layer:${_displayLayer.wireName}'),
              Text('browserTaps:$_browserTapCount'),
              Text('envTaps:$_envTapCount'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurfaceTransitionHarness extends StatefulWidget {
  const _SurfaceTransitionHarness({
    this.applyDelayByMode = const <ChatSurfaceMode, Duration>{},
  });

  final Map<ChatSurfaceMode, Duration> applyDelayByMode;

  @override
  State<_SurfaceTransitionHarness> createState() =>
      _SurfaceTransitionHarnessState();
}

class _SurfaceTransitionHarnessState extends State<_SurfaceTransitionHarness> {
  static const Duration _revealDelay = Duration(milliseconds: 1700);

  late final PageController _pageController = PageController(
    initialPage: _pageIndexForSurface(ChatSurfaceMode.openclaw),
  );
  ChatSurfaceMode _activeMode = ChatSurfaceMode.openclaw;
  ChatIslandDisplayLayer _normalDisplayLayer = ChatIslandDisplayLayer.model;
  Timer? _revealTimer;
  bool _revealInterrupted = false;
  bool _isSurfacePageScrolling = false;
  int _surfaceSwitchRequestId = 0;
  int? _pageGesturePointerId;
  double _pageVerticalDragDelta = 0;

  int _pageIndexForSurface(ChatSurfaceMode mode) => switch (mode) {
    ChatSurfaceMode.workspace => 0,
    ChatSurfaceMode.normal => 1,
    ChatSurfaceMode.openclaw => 2,
  };

  ChatSurfaceMode _surfaceForPageIndex(int pageIndex) => switch (pageIndex) {
    0 => ChatSurfaceMode.workspace,
    2 => ChatSurfaceMode.openclaw,
    _ => ChatSurfaceMode.normal,
  };

  void _cancelReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
  }

  void _interruptReveal() {
    _cancelReveal();
    _revealInterrupted = true;
  }

  void _forceNormalModeLayer() {
    _normalDisplayLayer = ChatIslandDisplayLayer.mode;
  }

  bool _canRevealModel() {
    return _activeMode == ChatSurfaceMode.normal &&
        !_isSurfacePageScrolling &&
        !_revealInterrupted &&
        _normalDisplayLayer == ChatIslandDisplayLayer.mode;
  }

  void _scheduleReveal() {
    _cancelReveal();
    if (!_canRevealModel()) {
      return;
    }
    _revealTimer = Timer(_revealDelay, () {
      _revealTimer = null;
      if (!mounted || !_canRevealModel()) {
        return;
      }
      setState(() {
        _normalDisplayLayer = ChatIslandDisplayLayer.model;
      });
    });
  }

  void _handleSurfaceScrollStart() {
    _cancelReveal();
    if (!mounted) {
      _isSurfacePageScrolling = true;
      _forceNormalModeLayer();
      return;
    }
    if (_isSurfacePageScrolling &&
        _normalDisplayLayer == ChatIslandDisplayLayer.mode) {
      return;
    }
    setState(() {
      _isSurfacePageScrolling = true;
      _forceNormalModeLayer();
    });
  }

  void _handleSurfaceScrollSettled(ChatSurfaceMode mode) {
    _cancelReveal();
    if (!mounted) {
      _isSurfacePageScrolling = false;
      if (mode == ChatSurfaceMode.normal) {
        _revealInterrupted = false;
        _forceNormalModeLayer();
      }
      return;
    }
    final shouldSetState =
        _isSurfacePageScrolling ||
        (mode == ChatSurfaceMode.normal &&
            _normalDisplayLayer != ChatIslandDisplayLayer.mode);
    if (shouldSetState) {
      setState(() {
        _isSurfacePageScrolling = false;
        if (mode == ChatSurfaceMode.normal) {
          _revealInterrupted = false;
          _forceNormalModeLayer();
        }
      });
    } else {
      _isSurfacePageScrolling = false;
      if (mode == ChatSurfaceMode.normal) {
        _revealInterrupted = false;
      }
    }
    if (mode == ChatSurfaceMode.normal) {
      _scheduleReveal();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _handleSurfaceScrollStart();
      return false;
    }
    if (notification is UserScrollNotification) {
      final direction = notification.direction;
      if (direction == ScrollDirection.forward ||
          direction == ScrollDirection.reverse) {
        _handleSurfaceScrollStart();
      }
      return false;
    }
    if (notification is ScrollEndNotification) {
      final pageMetrics = notification.metrics;
      final rawPage = pageMetrics is PageMetrics
          ? pageMetrics.page
          : (_pageController.hasClients ? _pageController.page : null);
      final settledIndex =
          (rawPage ?? _pageIndexForSurface(_activeMode).toDouble()).round();
      _handleSurfaceScrollSettled(_surfaceForPageIndex(settledIndex));
    }
    return false;
  }

  Future<void> _switchMode(
    ChatSurfaceMode targetMode, {
    bool syncPage = true,
  }) async {
    final requestId = ++_surfaceSwitchRequestId;
    bool isStaleRequest() => !mounted || requestId != _surfaceSwitchRequestId;
    if (_activeMode == targetMode) {
      if (targetMode == ChatSurfaceMode.normal && !syncPage) {
        _scheduleReveal();
      }
      return;
    }

    _cancelReveal();
    final delay = widget.applyDelayByMode[targetMode] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (isStaleRequest()) {
      return;
    }

    setState(() {
      _activeMode = targetMode;
      if (targetMode == ChatSurfaceMode.normal) {
        _revealInterrupted = false;
        _forceNormalModeLayer();
      }
    });
    if (syncPage) {
      await _pageController.animateToPage(
        _pageIndexForSurface(targetMode),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (targetMode == ChatSurfaceMode.normal && !_isSurfacePageScrolling) {
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _cancelReveal();
    _pageController.dispose();
    super.dispose();
  }

  void _handlePagePointerDown(PointerDownEvent event) {
    _pageGesturePointerId = event.pointer;
    _pageVerticalDragDelta = 0;
  }

  void _handlePagePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pageGesturePointerId ||
        _activeMode != ChatSurfaceMode.normal) {
      return;
    }
    _pageVerticalDragDelta += event.delta.dy;
    if (_revealTimer != null &&
        !_revealInterrupted &&
        _pageVerticalDragDelta.abs() >= 6) {
      _interruptReveal();
    }
  }

  void _handlePagePointerUp(PointerUpEvent event) {
    if (event.pointer != _pageGesturePointerId) {
      return;
    }
    if (_activeMode == ChatSurfaceMode.normal &&
        _pageVerticalDragDelta.abs() >= 18) {
      setState(() {
        _normalDisplayLayer = _pageVerticalDragDelta > 0
            ? ChatIslandDisplayLayer.tools
            : ChatIslandDisplayLayer.model;
      });
    }
    _pageGesturePointerId = null;
    _pageVerticalDragDelta = 0;
  }

  void _handlePagePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pageGesturePointerId) {
      return;
    }
    _pageGesturePointerId = null;
    _pageVerticalDragDelta = 0;
  }

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
                  _switchMode(value);
                },
                activeModelId: 'gpt-5.4',
                displayLayer: _activeMode == ChatSurfaceMode.normal
                    ? _normalDisplayLayer
                    : ChatIslandDisplayLayer.mode,
                onInteracted: _cancelReveal,
                onDisplayLayerChanged: (value) {
                  _cancelReveal();
                  setState(() {
                    _normalDisplayLayer = value;
                  });
                },
                onTerminalEnvironmentTap: (_) {},
                onTerminalTap: () {},
                onBrowserTap: () {},
                hasTerminalEnvironment: false,
                isBrowserEnabled: true,
                activeToolType: null,
              ),
              Text('active:${_activeMode.name}'),
              Text('layer:${_normalDisplayLayer.wireName}'),
              TextButton(
                key: const ValueKey('request-normal'),
                onPressed: () {
                  _switchMode(ChatSurfaceMode.normal, syncPage: false);
                },
                child: const Text('request-normal'),
              ),
              TextButton(
                key: const ValueKey('request-openclaw'),
                onPressed: () {
                  _switchMode(ChatSurfaceMode.openclaw, syncPage: false);
                },
                child: const Text('request-openclaw'),
              ),
              TextButton(
                key: const ValueKey('simulate-page-scroll'),
                onPressed: () {
                  _interruptReveal();
                },
                child: const Text('simulate-page-scroll'),
              ),
              Expanded(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handlePagePointerDown,
                  onPointerMove: _handlePagePointerMove,
                  onPointerUp: _handlePagePointerUp,
                  onPointerCancel: _handlePagePointerCancel,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (pageIndex) {
                        _switchMode(
                          _surfaceForPageIndex(pageIndex),
                          syncPage: false,
                        );
                      },
                      children: const [
                        ColoredBox(color: Colors.white),
                        ColoredBox(color: Colors.white),
                        ColoredBox(color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _tapModeSegment(WidgetTester tester, int index) async {
  final slider = find.byType(ChatModeSlider);
  final box = tester.renderObject<RenderBox>(slider);
  final topLeft = box.localToGlobal(Offset.zero);
  final segmentWidth = box.size.width / 3;
  final tapOffset =
      topLeft + Offset(segmentWidth * (index + 0.5), box.size.height / 2);
  await tester.tapAt(tapOffset);
}

Future<void> _pumpSurfaceSwitch(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260));
}

void main() {
  testWidgets('keeps model layer visible by default in normal chat', (
    tester,
  ) async {
    await tester.pumpWidget(const _ChatAppBarHarness());

    expect(find.text('layer:model'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);
  });

  testWidgets('supports direct island swipe between model and tools layers', (
    tester,
  ) async {
    await tester.pumpWidget(const _ChatAppBarHarness());

    await tester.drag(find.text('gpt-5.4'), const Offset(0, -42));
    await tester.pumpAndSettle();

    expect(find.text('layer:model'), findsOneWidget);
    expect(find.text('gpt-5.4'), findsOneWidget);

    await tester.drag(find.text('gpt-5.4'), const Offset(0, 42));
    await tester.pumpAndSettle();

    expect(find.text('layer:tools'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-island-terminal-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-island-terminal-env-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-island-browser-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('chat-island-terminal-env-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('envTaps:1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-island-browser-button')));
    await tester.pumpAndSettle();

    expect(find.text('browserTaps:0'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('chat-island-terminal-button')),
      const Offset(0, -42),
    );
    await tester.pumpAndSettle();

    expect(find.text('layer:model'), findsOneWidget);
  });

  testWidgets(
    'reveals model only after normal surface settles and stays idle',
    (tester) async {
      await tester.pumpWidget(const _SurfaceTransitionHarness());

      expect(find.text('active:openclaw'), findsOneWidget);

      await _tapModeSegment(tester, 1);
      await _pumpSurfaceSwitch(tester);

      expect(find.text('active:normal'), findsOneWidget);
      expect(find.text('layer:mode'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1699));
      expect(find.text('layer:mode'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('layer:model'), findsOneWidget);
    },
  );

  testWidgets('resets reveal delay after repeated surface switches', (
    tester,
  ) async {
    await tester.pumpWidget(const _SurfaceTransitionHarness());

    await _tapModeSegment(tester, 1);
    await _pumpSurfaceSwitch(tester);
    expect(find.text('active:normal'), findsOneWidget);
    expect(find.text('layer:mode'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));

    await _tapModeSegment(tester, 2);
    await _pumpSurfaceSwitch(tester);
    expect(find.text('active:openclaw'), findsOneWidget);

    await _tapModeSegment(tester, 1);
    await _pumpSurfaceSwitch(tester);
    expect(find.text('active:normal'), findsOneWidget);
    expect(find.text('layer:mode'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1699));
    expect(find.text('layer:mode'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('layer:model'), findsOneWidget);
  });

  testWidgets('interrupts delayed reveal when page scroll happens in time', (
    tester,
  ) async {
    await tester.pumpWidget(const _SurfaceTransitionHarness());

    await _tapModeSegment(tester, 1);
    await _pumpSurfaceSwitch(tester);
    expect(find.text('active:normal'), findsOneWidget);
    expect(find.text('layer:mode'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('simulate-page-scroll')));
    await tester.pump();

    expect(find.text('layer:mode'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('layer:mode'), findsOneWidget);
  });

  testWidgets('ignores stale async surface switch requests', (tester) async {
    await tester.pumpWidget(
      const _SurfaceTransitionHarness(
        applyDelayByMode: <ChatSurfaceMode, Duration>{
          ChatSurfaceMode.normal: Duration(milliseconds: 120),
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey('request-normal')));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byKey(const ValueKey('request-openclaw')));
    await tester.pump(const Duration(milliseconds: 140));

    expect(find.text('active:openclaw'), findsOneWidget);
    expect(find.text('layer:model'), findsOneWidget);
  });
}
