import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/data_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/DataSync');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getStatus parses sync status payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStatus') {
            return <String, dynamic>{
              'enabled': true,
              'configured': true,
              'state': 'syncing',
              'namespace': 'demo',
              'deviceId': 'device-a',
              'pendingOutboxCount': 3,
              'openConflictCount': 1,
              'progress': <String, dynamic>{
                'stage': 'push',
                'detail': 'uploading',
                'percent': 42,
              },
            };
          }
          return null;
        });

    final status = await DataSyncService.getStatus();

    expect(status.enabled, isTrue);
    expect(status.state, 'syncing');
    expect(status.progress.percent, 42);
    expect(status.pendingOutboxCount, 3);
  });

  test('exportPairingPayload parses encoded payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'exportPairingPayload') {
            expect((call.arguments as Map)['passphrase'], 'onetimer');
            return <String, dynamic>{
              'encodedPayload': 'payload-json',
              'namespace': 'demo',
              'createdAt': 1234,
            };
          }
          return null;
        });

    final payload = await DataSyncService.exportPairingPayload('onetimer');

    expect(payload.encodedPayload, 'payload-json');
    expect(payload.namespace, 'demo');
    expect(payload.createdAt, 1234);
  });
}
