import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/services/scheduled_task_scheduler_service.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/theme/app_theme.dart';

import 'core/router/go_router_manager.dart';
import 'services/event_bus.dart';

void main(List<String> args) async {
  String? initialRoute;

  // 可以在这里处理从原生传递过来的参数
  if (args.isNotEmpty) {
    // 处理参数的逻辑
    print('Received args from native: $args');

    // 检查是否有路由参数
    for (var arg in args) {
      if (arg.startsWith('--route=')) {
        initialRoute = arg.substring(8); // 提取路由路径
      }
    }
  } else {
    print('No args received from native');
  }

  // 设置初始路由
  if (initialRoute != null) {
    GoRouterManager.setInitialRoute(initialRoute);
  }
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.deferFirstFrame();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final container = ProviderContainer();
  await StorageService.init();
  await AppBackgroundService.load();
  await ScheduledTaskSchedulerService.initialize();
  await OmnibotResourceService.ensureWorkspacePathsLoaded();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(args: args),
    ),
  );
  WidgetsBinding.instance.allowFirstFrame();
}

@pragma('vm:entry-point')
void subEngineMain(List<String> args) async {
  GoRouterManager.setSubEngine(true);
  String? initialRoute;
  if (args.isNotEmpty) {
    for (var arg in args) {
      if (arg.startsWith('--route=')) {
        initialRoute = arg.substring(8);
      }
    }
  }
  if (initialRoute != null) {
    GoRouterManager.setInitialRoute(initialRoute);
  }
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final container = ProviderContainer();
  await StorageService.init();
  await AppBackgroundService.load();
  await ScheduledTaskSchedulerService.initialize();
  await OmnibotResourceService.ensureWorkspacePathsLoaded();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(args: args),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  final List<String> args;
  const MyApp({super.key, this.args = const []});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();

    final initStart = DateTime.now();
    print('🎨 [FlutterStartup] MyApp initState start');
    super.initState();
    _initializeApp();
    print(
      "⏱️  [FlutterStartup] MyApp initState cost: ${DateTime.now().difference(initStart).inMilliseconds}ms",
    );
  }

  Future<void> _initializeApp() async {
    final appInitStart = DateTime.now();
    try {
      ref.read(eventListenerProvider);
      print(
        "⏱️  [FlutterStartup] eventListenerProvider init cost: ${DateTime.now().difference(appInitStart).inMilliseconds}ms",
      );
    } catch (e) {
      print('⚠️  [FlutterStartup] initializeApp error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildStart = DateTime.now();
    print('🎨 [FlutterStartup] MyApp build start');

    final routerStart = DateTime.now();
    final router = GoRouterManager.createRouter(ref);
    print(
      "⏱️  [FlutterStartup] createRouter cost: ${DateTime.now().difference(routerStart).inMilliseconds}ms",
    );

    final widgetBuildStart = DateTime.now();
    final widget = AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false, // 改为 false，强制完全透明
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp.router(
        title: '小万',
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              padding: mediaQuery.padding.copyWith(bottom: 0),
              viewPadding: mediaQuery.viewPadding.copyWith(bottom: 0),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [const Locale('en', 'US'), const Locale('zh', 'CN')],
      ),
    );

    print(
      "⏱️  [FlutterStartup] Widget tree build cost: ${DateTime.now().difference(widgetBuildStart).inMilliseconds}ms",
    );
    print(
      "✅ [FlutterStartup] MyApp build total cost: ${DateTime.now().difference(buildStart).inMilliseconds}ms",
    );

    return widget;
  }
}
