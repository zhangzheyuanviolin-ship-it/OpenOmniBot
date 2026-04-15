import 'package:flutter_test/flutter_test.dart';
import 'package:ui/generated/host_bridge.g.dart';
import 'package:ui/services/host_platform_bridge.dart';

void main() {
  test('HostCapabilities.fromMessage maps platform flags', () {
    final message = HostCapabilitiesMessage(
      platform: 'ios',
      appStoreDistribution: true,
      supportsTerminal: true,
      supportsApkInstall: true,
      supportsLocalModels: true,
      supportsInAppBrowserAutomation: true,
      supportsExternalAppAutomation: false,
      supportsOverlay: false,
      supportsPreciseBackgroundSchedule: false,
      supportsSpeechRecognition: true,
      supportsWorkspacePublicStorage: true,
    );

    final capabilities = HostCapabilities.fromMessage(message);

    expect(capabilities.isIOS, isTrue);
    expect(capabilities.isAndroid, isFalse);
    expect(capabilities.supportsTerminal, isTrue);
    expect(capabilities.supportsExternalAppAutomation, isFalse);
    expect(capabilities.appStoreDistribution, isTrue);
  });
}
