import 'dart:io';

import 'package:flutter/services.dart';
import 'package:ui/generated/host_bridge.g.dart';

class HostCapabilities {
  const HostCapabilities({
    required this.platform,
    required this.appStoreDistribution,
    required this.supportsTerminal,
    required this.supportsApkInstall,
    required this.supportsLocalModels,
    required this.supportsInAppBrowserAutomation,
    required this.supportsExternalAppAutomation,
    required this.supportsOverlay,
    required this.supportsPreciseBackgroundSchedule,
    required this.supportsSpeechRecognition,
    required this.supportsWorkspacePublicStorage,
  });

  final String platform;
  final bool appStoreDistribution;
  final bool supportsTerminal;
  final bool supportsApkInstall;
  final bool supportsLocalModels;
  final bool supportsInAppBrowserAutomation;
  final bool supportsExternalAppAutomation;
  final bool supportsOverlay;
  final bool supportsPreciseBackgroundSchedule;
  final bool supportsSpeechRecognition;
  final bool supportsWorkspacePublicStorage;

  bool get isIOS => platform.toLowerCase() == 'ios';
  bool get isAndroid => platform.toLowerCase() == 'android';

  factory HostCapabilities.fromMessage(HostCapabilitiesMessage message) {
    return HostCapabilities(
      platform: message.platform,
      appStoreDistribution: message.appStoreDistribution,
      supportsTerminal: message.supportsTerminal,
      supportsApkInstall: message.supportsApkInstall,
      supportsLocalModels: message.supportsLocalModels,
      supportsInAppBrowserAutomation: message.supportsInAppBrowserAutomation,
      supportsExternalAppAutomation: message.supportsExternalAppAutomation,
      supportsOverlay: message.supportsOverlay,
      supportsPreciseBackgroundSchedule:
          message.supportsPreciseBackgroundSchedule,
      supportsSpeechRecognition: message.supportsSpeechRecognition,
      supportsWorkspacePublicStorage: message.supportsWorkspacePublicStorage,
    );
  }

  factory HostCapabilities.fallback() {
    if (Platform.isIOS) {
      return const HostCapabilities(
        platform: 'ios',
        appStoreDistribution: true,
        supportsTerminal: false,
        supportsApkInstall: false,
        supportsLocalModels: true,
        supportsInAppBrowserAutomation: true,
        supportsExternalAppAutomation: false,
        supportsOverlay: false,
        supportsPreciseBackgroundSchedule: false,
        supportsSpeechRecognition: true,
        supportsWorkspacePublicStorage: true,
      );
    }
    return const HostCapabilities(
      platform: 'android',
      appStoreDistribution: false,
      supportsTerminal: true,
      supportsApkInstall: true,
      supportsLocalModels: true,
      supportsInAppBrowserAutomation: true,
      supportsExternalAppAutomation: true,
      supportsOverlay: true,
      supportsPreciseBackgroundSchedule: true,
      supportsSpeechRecognition: true,
      supportsWorkspacePublicStorage: true,
    );
  }
}

class HostPlatformBridge {
  HostPlatformBridge._();

  static final HostCapabilitiesApi _hostCapabilitiesApi = HostCapabilitiesApi();
  static final WorkspaceBridgeApi _workspaceBridgeApi = WorkspaceBridgeApi();
  static final TerminalRuntimeBridgeApi _terminalBridgeApi =
      TerminalRuntimeBridgeApi();
  static final LocalModelBridgeApi _localModelBridgeApi = LocalModelBridgeApi();
  static final BrowserBridgeApi _browserBridgeApi = BrowserBridgeApi();
  static final PermissionBridgeApi _permissionBridgeApi = PermissionBridgeApi();
  static final DeviceBridgeApi _deviceBridgeApi = DeviceBridgeApi();

  static HostCapabilities? _cachedCapabilities;

  static HostCapabilities get cachedCapabilities =>
      _cachedCapabilities ?? HostCapabilities.fallback();

  static Future<HostCapabilities> getCapabilities({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCapabilities != null) {
      return _cachedCapabilities!;
    }
    try {
      final capabilities = HostCapabilities.fromMessage(
        await _hostCapabilitiesApi.getCapabilities(),
      );
      _cachedCapabilities = capabilities;
      return capabilities;
    } on MissingPluginException {
      final fallback = HostCapabilities.fallback();
      _cachedCapabilities = fallback;
      return fallback;
    } on PlatformException {
      final fallback = HostCapabilities.fallback();
      _cachedCapabilities = fallback;
      return fallback;
    }
  }

  static Future<WorkspacePathsMessage?> tryResolveWorkspacePaths() async {
    return _safeCall(_workspaceBridgeApi.resolveWorkspacePaths);
  }

  static Future<TerminalRuntimeStatusMessage?>
  tryInspectTerminalRuntime() async {
    return _safeCall(_terminalBridgeApi.inspectRuntime);
  }

  static Future<TerminalRuntimeStatusMessage?>
  tryPrepareTerminalRuntime() async {
    return _safeCall(_terminalBridgeApi.prepareRuntime);
  }

  static Future<PackageInstallResultMessage?> tryInstallPackages(
    List<String> packageIds, {
    bool allowThirdPartyRepositories = false,
  }) async {
    return _safeCall(
      () => _terminalBridgeApi.installPackages(
        PackageInstallRequestMessage(
          packageIds: packageIds,
          allowThirdPartyRepositories: allowThirdPartyRepositories,
        ),
      ),
    );
  }

  static Future<List<String>?> tryListInstalledPackages() async {
    return _safeCall(_terminalBridgeApi.listInstalledPackages);
  }

  static Future<LocalModelStatusMessage?> tryGetLocalModelStatus() async {
    return _safeCall(_localModelBridgeApi.getStatus);
  }

  static Future<LocalModelStatusMessage?> tryLoadModel({
    required String modelId,
    required String backendId,
  }) async {
    return _safeCall(() => _localModelBridgeApi.loadModel(modelId, backendId));
  }

  static Future<LocalModelStatusMessage?> tryStopModel() async {
    return _safeCall(_localModelBridgeApi.stopModel);
  }

  static Future<BrowserSessionSnapshotMessage?>
  tryGetBrowserSessionSnapshot() async {
    return _safeCall(_browserBridgeApi.getLiveSessionSnapshot);
  }

  static Future<PermissionSnapshotMessage?> tryGetPermissionSnapshot() async {
    return _safeCall(_permissionBridgeApi.getPermissionSnapshot);
  }

  static Future<bool> openSystemSettings() async {
    return (await _safeCall(_permissionBridgeApi.openAppSettings)) ?? false;
  }

  static Future<DeviceInfoMessage?> tryGetDeviceInfo() async {
    return _safeCall(_deviceBridgeApi.getDeviceInfo);
  }

  static Future<T?> _safeCall<T>(Future<T> Function() task) async {
    try {
      return await task();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
