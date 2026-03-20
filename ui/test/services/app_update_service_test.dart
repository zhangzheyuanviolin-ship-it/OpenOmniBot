import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/app_update');

  tearDown(() async {
    AppUpdateService.statusNotifier.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('checkNow updates status notifier from channel response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkNow') {
            return <String, dynamic>{
              'currentVersion': '0.0.1',
              'latestVersion': '0.0.2',
              'hasUpdate': true,
              'checkedAt': 1,
              'publishedAt': 2,
              'releaseUrl': 'https://example.com/release',
              'releaseNotes': 'notes',
              'apkName': 'OpenOmniBot-v0.0.2.apk',
              'apkDownloadUrl': 'https://example.com/app.apk',
            };
          }
          return null;
        });

    final status = await AppUpdateService.checkNow();

    expect(status, isNotNull);
    expect(status!.hasUpdate, isTrue);
    expect(AppUpdateService.statusNotifier.value?.latestVersion, '0.0.2');
  });
}
