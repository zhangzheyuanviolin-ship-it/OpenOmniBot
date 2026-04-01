import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    AppBackgroundService.notifier.value = AppBackgroundConfig.defaults;
  });

  tearDown(() async {
    AppBackgroundService.notifier.value = AppBackgroundConfig.defaults;
  });

  test('fromJson clamps background values into supported range', () {
    final config = AppBackgroundConfig.fromJson(const <String, dynamic>{
      'enabled': true,
      'sourceType': 'remote',
      'remoteImageUrl': 'https://example.com/bg.jpg',
      'blurSigma': 100,
      'frostOpacity': -1,
      'brightness': 3,
      'focalX': -3,
      'focalY': 4,
    });

    expect(config.enabled, isTrue);
    expect(config.sourceType, AppBackgroundSourceType.remote);
    expect(config.blurSigma, 24);
    expect(config.frostOpacity, 0);
    expect(config.brightness, 1.5);
    expect(config.focalX, -1);
    expect(config.focalY, 1);
  });

  test('save load and reset round-trip shared background config', () async {
    const config = AppBackgroundConfig(
      enabled: true,
      sourceType: AppBackgroundSourceType.remote,
      localImagePath: '',
      remoteImageUrl: 'https://example.com/background.jpg',
      blurSigma: 12,
      frostOpacity: 0.22,
      brightness: 1.1,
      focalX: 0.3,
      focalY: -0.25,
    );

    await AppBackgroundService.save(config);

    expect(AppBackgroundService.current.isActive, isTrue);
    expect(
      AppBackgroundService.current.remoteImageUrl,
      'https://example.com/background.jpg',
    );

    AppBackgroundService.notifier.value = AppBackgroundConfig.defaults;
    await AppBackgroundService.load();

    expect(AppBackgroundService.current.enabled, isTrue);
    expect(
      AppBackgroundService.current.sourceType,
      AppBackgroundSourceType.remote,
    );
    expect(
      AppBackgroundService.current.remoteImageUrl,
      'https://example.com/background.jpg',
    );
    expect(AppBackgroundService.current.blurSigma, 12);
    expect(AppBackgroundService.current.frostOpacity, 0.22);
    expect(AppBackgroundService.current.brightness, 1.1);
    expect(AppBackgroundService.current.focalX, 0.3);
    expect(AppBackgroundService.current.focalY, -0.25);

    await AppBackgroundService.reset();

    expect(AppBackgroundService.current.enabled, isFalse);
    expect(
      AppBackgroundService.current.sourceType,
      AppBackgroundSourceType.none,
    );
    expect(AppBackgroundService.current.remoteImageUrl, isEmpty);
  });
}
