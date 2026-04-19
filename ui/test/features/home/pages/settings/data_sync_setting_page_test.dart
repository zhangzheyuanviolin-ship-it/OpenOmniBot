import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/pages/settings/data_sync_setting_page.dart';
import 'package:ui/services/data_sync_service.dart';
import 'package:ui/services/data_sync_status_center.dart';
import 'package:ui/theme/app_theme.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/data_sync_progress_toast_listener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/DataSync');
  late List<MethodCall> recordedCalls;
  late List<Map<String, dynamic>> getStatusQueue;
  late Map<String, dynamic> currentConfig;

  Widget buildApp() {
    return MaterialApp(
      navigatorKey: GoRouterManager.rootNavigatorKey,
      locale: const Locale('zh'),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          const DataSyncProgressToastListener(),
        ],
      ),
      home: const Scaffold(body: DataSyncSettingPage()),
    );
  }

  setUp(() {
    DataSyncStatusCenter.instance.reset();
    recordedCalls = <MethodCall>[];
    currentConfig = <String, dynamic>{
      'enabled': true,
      'configured': true,
      'supabaseUrl': 'https://demo.supabase.co',
      'anonKey': 'anon-key',
      'namespace': 'demo',
      'syncSecret': 'secret',
      's3Endpoint': 'https://s3.example.com',
      'region': 'auto',
      'bucket': 'demo-bucket',
      'accessKey': 'ak',
      'secretKey': 'sk',
      'sessionToken': '',
      'forcePathStyle': true,
      'deviceId': 'device-a',
    };
    getStatusQueue = <Map<String, dynamic>>[
      <String, dynamic>{
        'enabled': true,
        'configured': true,
        'state': 'success',
        'namespace': 'demo',
        'deviceId': 'device-a',
        'pendingOutboxCount': 2,
        'openConflictCount': 1,
        'lastMessage': '同步完成',
        'progress': <String, dynamic>{'percent': 100},
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCalls.add(call);
          switch (call.method) {
            case 'getConfig':
              return currentConfig;
            case 'getStatus':
              if (getStatusQueue.length > 1) {
                return getStatusQueue.removeAt(0);
              }
              return getStatusQueue.first;
            case 'testConnection':
              return <String, dynamic>{'success': true, 'message': '连接成功'};
            case 'syncNow':
              return <String, dynamic>{
                'enabled': true,
                'configured': true,
                'state': 'syncing',
                'namespace': 'demo',
                'deviceId': 'device-a',
                'lastMessage': '同步任务已加入队列',
                'progress': <String, dynamic>{
                  'stage': 'handshake',
                  'detail': '正在建立安全连接…',
                  'percent': 5,
                },
              };
            case 'importPairingPayload':
              currentConfig = <String, dynamic>{
                ...currentConfig,
                'enabled': true,
                'configured': true,
                'supabaseUrl': 'https://paired.supabase.co',
                'anonKey': 'paired-anon-key',
                'namespace': 'paired-demo',
                'syncSecret': 'paired-secret',
                's3Endpoint': 'https://paired-s3.example.com',
                'region': 'us-east-1',
                'bucket': 'paired-bucket',
                'accessKey': 'paired-ak',
                'secretKey': 'paired-sk',
                'sessionToken': 'paired-session',
                'forcePathStyle': false,
              };
              return <String, dynamic>{
                'enabled': true,
                'configured': true,
                'state': 'syncing',
                'namespace': 'paired-demo',
                'deviceId': 'device-a',
                'lastMessage': '配对导入成功，正在执行首次全量同步',
                'currentStep': 'pairing_import',
                'progress': <String, dynamic>{
                  'stage': 'pull',
                  'detail': '正在拉取远端变更',
                  'percent': 18,
                },
              };
            default:
              return <String, dynamic>{};
          }
        });
  });

  tearDown(() {
    DataSyncStatusCenter.instance.reset();
    hideToast();
    hideProgressToast();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('renders sync form, summary, and action buttons', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('数据同步').evaluate().isNotEmpty ||
          find.text('Data Sync').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('Supabase URL'), findsOneWidget);
    expect(find.text('sync namespace'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final exportButtonFinder = find.text('导出配对二维码').evaluate().isNotEmpty
        ? find.text('导出配对二维码')
        : find.text('Export QR');
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    expect(exportButtonFinder.evaluate().isNotEmpty, isTrue);
    expect(
      find.text('导入配对二维码').evaluate().isNotEmpty ||
          find.text('Import QR').evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      find.text('查看冲突/失败').evaluate().isNotEmpty ||
          find.text('View Conflicts').evaluate().isNotEmpty,
      isTrue,
    );

    final testConnectionFinder = find.text('连接测试').evaluate().isNotEmpty
        ? find.text('连接测试')
        : find.text('Test Connection');
    await tester.tap(testConnectionFinder);
    await tester.pump();
    hideToast();
    await tester.pump();

    expect(
      recordedCalls.where((call) => call.method == 'testConnection'),
      hasLength(1),
    );
  });

  testWidgets('shows sync start toast after tapping sync now', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    final syncNowFinder = find.text('立即同步').evaluate().isNotEmpty
        ? find.text('立即同步')
        : find.text('Sync Now');
    await tester.tap(syncNowFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('已开始同步').evaluate().isNotEmpty ||
          find.text('Sync started').evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      recordedCalls.where((call) => call.method == 'syncNow'),
      hasLength(1),
    );

    hideToast();
    await tester.pump();
  });

  testWidgets('sync start toast does not become a persistent progress toast', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    final syncNowFinder = find.text('立即同步').evaluate().isNotEmpty
        ? find.text('立即同步')
        : find.text('Sync Now');
    await tester.tap(syncNowFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    GoRouterManager.rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other Page')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Other Page'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    hideToast();
    await tester.pump();
  });

  testWidgets('does not show sync start toast when app resumes', (
    tester,
  ) async {
    getStatusQueue = <Map<String, dynamic>>[
      <String, dynamic>{
        'enabled': true,
        'configured': true,
        'state': 'success',
        'namespace': 'demo',
        'deviceId': 'device-a',
        'pendingOutboxCount': 0,
        'openConflictCount': 0,
        'lastMessage': '同步完成',
        'progress': <String, dynamic>{'percent': 100},
      },
      <String, dynamic>{
        'enabled': true,
        'configured': true,
        'state': 'syncing',
        'namespace': 'demo',
        'deviceId': 'device-a',
        'currentStep': 'pull',
        'lastMessage': '同步进行中',
        'progress': <String, dynamic>{
          'stage': 'pull',
          'detail': '正在拉取变更',
          'percent': 15,
        },
      },
    ];

    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('已开始同步'), findsNothing);
    expect(find.text('Sync started'), findsNothing);
  });

  testWidgets('does not show completion toast for automatic sync', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    DataSyncStatusCenter.instance.observeStatus(
      const DataSyncStatus(
        enabled: true,
        configured: true,
        state: 'syncing',
        namespace: 'demo',
        deviceId: 'device-a',
        currentStep: 'pull',
        progress: DataSyncProgress(percent: 12),
      ),
    );
    await tester.pump();

    DataSyncStatusCenter.instance.observeStatus(
      const DataSyncStatus(
        enabled: true,
        configured: true,
        state: 'success',
        namespace: 'demo',
        deviceId: 'device-a',
        lastMessage: '同步完成',
        progress: DataSyncProgress(percent: 100),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('shows completion toast for manual sync only', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    DataSyncStatusCenter.instance.armManualSyncFeedback();
    DataSyncStatusCenter.instance.observeStatus(
      const DataSyncStatus(
        enabled: true,
        configured: true,
        state: 'syncing',
        namespace: 'demo',
        deviceId: 'device-a',
        currentStep: 'push',
        progress: DataSyncProgress(percent: 48),
      ),
    );
    await tester.pump();

    DataSyncStatusCenter.instance.observeStatus(
      const DataSyncStatus(
        enabled: true,
        configured: true,
        state: 'success',
        namespace: 'demo',
        deviceId: 'device-a',
        lastMessage: '同步完成',
        progress: DataSyncProgress(percent: 100),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    hideToast();
    await tester.pump();
  });

  testWidgets('import pairing refreshes config fields immediately', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();

    final importFinder = find.text('导入配对二维码').evaluate().isNotEmpty
        ? find.text('导入配对二维码')
        : find.text('Import QR');
    await tester.tap(importFinder);
    await tester.pumpAndSettle();

    final pasteFinder = find.text('粘贴导入串').evaluate().isNotEmpty
        ? find.text('粘贴导入串')
        : find.text('Paste payload');
    await tester.tap(pasteFinder);
    await tester.pumpAndSettle();

    final importDialog = find.byType(AlertDialog);
    final importInput = find.descendant(
      of: importDialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(importInput, '{"v":2,"payload":{}}');
    final okFinder = find.text('确定').evaluate().isNotEmpty
        ? find.text('确定')
        : find.text('OK');
    await tester.tap(okFinder);
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(0, 2400), 2000);
    await tester.pumpAndSettle();

    final controllerValues = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((field) => field.controller?.text ?? '')
        .toSet();
    expect(controllerValues, contains('https://paired.supabase.co'));
    expect(controllerValues, contains('paired-demo'));
    expect(
      recordedCalls.where((call) => call.method == 'importPairingPayload'),
      hasLength(1),
    );
    expect(
      recordedCalls.where((call) => call.method == 'getConfig').length,
      greaterThanOrEqualTo(2),
    );
  });
}
