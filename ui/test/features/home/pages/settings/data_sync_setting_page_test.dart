import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/settings/data_sync_setting_page.dart';
import 'package:ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/DataSync');
  late List<MethodCall> recordedCalls;

  Widget buildApp() {
    return MaterialApp(
      locale: const Locale('zh'),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const DataSyncSettingPage(),
    );
  }

  setUp(() {
    recordedCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCalls.add(call);
          switch (call.method) {
            case 'getConfig':
              return <String, dynamic>{
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
            case 'getStatus':
              return <String, dynamic>{
                'enabled': true,
                'configured': true,
                'state': 'success',
                'namespace': 'demo',
                'deviceId': 'device-a',
                'pendingOutboxCount': 2,
                'openConflictCount': 1,
                'lastMessage': '同步完成',
                'progress': <String, dynamic>{'percent': 100},
              };
            case 'testConnection':
              return <String, dynamic>{'success': true, 'message': '连接成功'};
            default:
              return <String, dynamic>{};
          }
        });
  });

  tearDown(() {
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
    expect(
      find.text('同步完成').evaluate().isNotEmpty ||
          find.text('Sync completed').evaluate().isNotEmpty ||
          find.text('Last sync succeeded').evaluate().isNotEmpty,
      isTrue,
    );
    final exportButtonFinder = find.text('导出配对二维码').evaluate().isNotEmpty
        ? find.text('导出配对二维码')
        : find.text('Export QR');
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    expect(
      exportButtonFinder.evaluate().isNotEmpty,
      isTrue,
    );
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

    expect(
      recordedCalls.where((call) => call.method == 'testConnection'),
      hasLength(1),
    );
  });
}
