import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/utils/ui.dart';

// The channel name must match the one in MainActivity.kt
const spePermission = MethodChannel(
  'cn.com.omnimind.bot/SpecialPermissionEvent',
);
const _specialPermissionEvents = EventChannel(
  'cn.com.omnimind.bot/SpecialPermissionEvents',
);

class EmbeddedTerminalInitProgress {
  const EmbeddedTerminalInitProgress({
    required this.kind,
    required this.message,
    required this.timestamp,
  });

  final String kind;
  final String message;
  final DateTime timestamp;

  factory EmbeddedTerminalInitProgress.fromMap(Map<dynamic, dynamic> map) {
    final timestampValue = map['timestamp'];
    final millis = timestampValue is num
        ? timestampValue.toInt()
        : DateTime.now().millisecondsSinceEpoch;
    return EmbeddedTerminalInitProgress(
      kind: (map['kind'] as String? ?? 'status').trim(),
      message: (map['message'] as String? ?? '').trimRight(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

class EmbeddedTerminalInitSnapshot {
  const EmbeddedTerminalInitSnapshot({
    required this.running,
    required this.completed,
    required this.success,
    required this.progress,
    required this.stage,
    required this.logLines,
  });

  final bool running;
  final bool completed;
  final bool? success;
  final double progress;
  final String stage;
  final List<String> logLines;

  factory EmbeddedTerminalInitSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final rawLogLines = map['logLines'];
    return EmbeddedTerminalInitSnapshot(
      running: map['running'] == true,
      completed: map['completed'] == true,
      success: map['success'] as bool?,
      progress: ((map['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      stage: (map['stage'] as String? ?? '').trim(),
      logLines: rawLogLines is List
          ? rawLogLines.map((line) => line.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

class EmbeddedTerminalRuntimeStatus {
  const EmbeddedTerminalRuntimeStatus({
    required this.supported,
    required this.runtimeReady,
    required this.basePackagesReady,
    required this.allReady,
    required this.missingCommands,
    required this.message,
    required this.workspaceAccessGranted,
  });

  final bool supported;
  final bool runtimeReady;
  final bool basePackagesReady;
  final bool allReady;
  final List<String> missingCommands;
  final String message;
  final bool workspaceAccessGranted;

  factory EmbeddedTerminalRuntimeStatus.fromMap(Map<dynamic, dynamic> map) {
    final rawMissing = map['missingCommands'];
    return EmbeddedTerminalRuntimeStatus(
      supported: map['supported'] == true,
      runtimeReady: map['runtimeReady'] == true,
      basePackagesReady: map['basePackagesReady'] == true,
      allReady: map['allReady'] == true,
      missingCommands: rawMissing is List
          ? rawMissing.map((it) => it.toString()).toList(growable: false)
          : const <String>[],
      message: (map['message'] as String? ?? '').trim(),
      workspaceAccessGranted: map['workspaceAccessGranted'] == true,
    );
  }
}

class OpenClawDeployRequest {
  const OpenClawDeployRequest({
    required this.providerBaseUrl,
    required this.providerApiKey,
    required this.modelId,
    required this.configJson,
  });

  final String providerBaseUrl;
  final String providerApiKey;
  final String modelId;
  final String configJson;

  Map<String, dynamic> toMap() {
    return {
      'providerBaseUrl': providerBaseUrl,
      'providerApiKey': providerApiKey,
      'modelId': modelId,
      'configJson': configJson,
    };
  }
}

class OpenClawDeployResult {
  const OpenClawDeployResult({
    required this.accepted,
    required this.alreadyRunning,
    required this.message,
  });

  final bool accepted;
  final bool alreadyRunning;
  final String message;

  factory OpenClawDeployResult.fromMap(Map<dynamic, dynamic>? map) {
    return OpenClawDeployResult(
      accepted: map?['accepted'] == true,
      alreadyRunning: map?['alreadyRunning'] == true,
      message: (map?['message'] as String? ?? '').trim(),
    );
  }
}

class OpenClawDeploySnapshot {
  const OpenClawDeploySnapshot({
    required this.running,
    required this.completed,
    required this.success,
    required this.progress,
    required this.stage,
    required this.logLines,
    required this.gatewayBaseUrl,
    required this.gatewayToken,
    required this.errorMessage,
  });

  final bool running;
  final bool completed;
  final bool? success;
  final double progress;
  final String stage;
  final List<String> logLines;
  final String? gatewayBaseUrl;
  final String? gatewayToken;
  final String? errorMessage;

  factory OpenClawDeploySnapshot.fromMap(Map<dynamic, dynamic>? map) {
    final rawLogLines = map?['logLines'];
    return OpenClawDeploySnapshot(
      running: map?['running'] == true,
      completed: map?['completed'] == true,
      success: map?['success'] as bool?,
      progress: ((map?['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      stage: (map?['stage'] as String? ?? '').trim(),
      logLines: rawLogLines is List
          ? rawLogLines.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      gatewayBaseUrl: (map?['gatewayBaseUrl'] as String?)?.trim(),
      gatewayToken: (map?['gatewayToken'] as String?)?.trim(),
      errorMessage: (map?['errorMessage'] as String?)?.trim(),
    );
  }
}

class OpenClawGatewayStatus {
  const OpenClawGatewayStatus({
    required this.installed,
    required this.configured,
    required this.autoStartEnabled,
    required this.running,
    required this.healthy,
    required this.restarting,
    required this.dashboardUrl,
    required this.lastError,
    required this.legacyConfigNeedsRedeploy,
    required this.uptimeSeconds,
  });

  final bool installed;
  final bool configured;
  final bool autoStartEnabled;
  final bool running;
  final bool healthy;
  final bool restarting;
  final String? dashboardUrl;
  final String? lastError;
  final bool legacyConfigNeedsRedeploy;
  final int? uptimeSeconds;

  factory OpenClawGatewayStatus.fromMap(Map<dynamic, dynamic>? map) {
    return OpenClawGatewayStatus(
      installed: map?['installed'] == true,
      configured: map?['configured'] == true,
      autoStartEnabled: map?['autoStartEnabled'] == true,
      running: map?['running'] == true,
      healthy: map?['healthy'] == true,
      restarting: map?['restarting'] == true,
      dashboardUrl: (map?['dashboardUrl'] as String?)?.trim(),
      lastError: (map?['lastError'] as String?)?.trim(),
      legacyConfigNeedsRedeploy: map?['legacyConfigNeedsRedeploy'] == true,
      uptimeSeconds: (map?['uptimeSeconds'] as num?)?.toInt(),
    );
  }
}

Stream<EmbeddedTerminalInitProgress> get embeddedTerminalInitProgressStream {
  return _specialPermissionEvents.receiveBroadcastStream().map((event) {
    final payload = event is Map
        ? Map<dynamic, dynamic>.from(event)
        : const <dynamic, dynamic>{};
    return EmbeddedTerminalInitProgress.fromMap(payload);
  });
}

Future<EmbeddedTerminalInitSnapshot> getEmbeddedTerminalInitSnapshot() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getEmbeddedTerminalInitSnapshot',
  );
  return EmbeddedTerminalInitSnapshot.fromMap(result ?? const {});
}

Future<EmbeddedTerminalRuntimeStatus> getEmbeddedTerminalRuntimeStatus() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getEmbeddedTerminalRuntimeStatus',
  );
  return EmbeddedTerminalRuntimeStatus.fromMap(result ?? const {});
}

Future<OpenClawDeployResult> startOpenClawDeploy(
  OpenClawDeployRequest request,
) async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'startOpenClawDeploy',
    request.toMap(),
  );
  return OpenClawDeployResult.fromMap(result ?? const {});
}

Future<OpenClawDeploySnapshot> getOpenClawDeploySnapshot() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getOpenClawDeploySnapshot',
  );
  return OpenClawDeploySnapshot.fromMap(result ?? const {});
}

Future<OpenClawGatewayStatus> getOpenClawGatewayStatus() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getOpenClawGatewayStatus',
  );
  return OpenClawGatewayStatus.fromMap(result ?? const {});
}

Future<void> setOpenClawGatewayAutoStart(bool enabled) async {
  await spePermission.invokeMethod<void>('setOpenClawGatewayAutoStart', {
    'enabled': enabled,
  });
}

Future<void> startOpenClawGateway({bool forceRestart = false}) async {
  await spePermission.invokeMethod<void>('startOpenClawGateway', {
    'forceRestart': forceRestart,
  });
}

Future<void> stopOpenClawGateway() async {
  await spePermission.invokeMethod<void>('stopOpenClawGateway');
}

Future<void> openNativeTerminal() async {
  await spePermission.invokeMethod<void>('openNativeTerminal');
}

/// 检查无障碍权限，如果没有权限则弹出授权对话框
/// 返回 true 表示有权限，false 表示没有权限
Future<bool> checkAccessibilityPermission(BuildContext context) async {
  try {
    final hasPermission = await spePermission.invokeMethod(
      'isAccessibilityServiceEnabled',
    );
    if (hasPermission == true) {
      return true;
    }

    if (!context.mounted) {
      return false;
    }

    // 没有权限，弹出对话框
    final result = await AppDialog.confirm(
      context,
      title: '无障碍权限',
      content: '每次开启App需重新授权无障碍的权限，这也是为了你的安全～',
      cancelText: '取消',
      confirmText: '去授权',
    );

    if (!context.mounted) {
      return false;
    }
    if (result == true) {
      await spePermission.invokeMethod('openAccessibilitySettings');
    }

    return false;
  } catch (e) {
    debugPrint('检查无障碍权限失败: $e');
    return false;
  }
}

Future<bool> requestPermission(List<String> permissions) async {
  try {
    final hasPermission = await spePermission.invokeMethod(
      'requestPermissions',
      {'permissions': permissions},
    );
    return hasPermission == "Success";
  } catch (e) {
    debugPrint('检查无障碍权限失败: $e');
    return false;
  }
}

Future<bool> isTermuxInstalled() async {
  try {
    return await spePermission.invokeMethod<bool>('isTermuxInstalled') ?? false;
  } catch (e) {
    debugPrint('检查 Termux 安装状态失败: $e');
    return false;
  }
}

Future<bool> openTermuxApp() async {
  try {
    return await spePermission.invokeMethod<bool>('openTermuxApp') ?? false;
  } catch (e) {
    debugPrint('打开 Termux 失败: $e');
    return false;
  }
}

Future<bool> isTermuxRunCommandPermissionGranted() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'isTermuxRunCommandPermissionGranted',
        ) ??
        false;
  } catch (e) {
    debugPrint('检查 Termux RUN_COMMAND 权限失败: $e');
    return false;
  }
}

Future<bool> requestTermuxRunCommandPermission() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'requestTermuxRunCommandPermission',
        ) ??
        false;
  } catch (e) {
    debugPrint('请求 Termux RUN_COMMAND 权限失败: $e');
    return false;
  }
}

Future<bool> ensureInstalledAppsPermission() async {
  try {
    final hasPermission =
        await spePermission.invokeMethod<bool>(
          'isInstalledAppsPermissionGranted',
        ) ??
        false;
    if (hasPermission) {
      return true;
    }
    await openInstalledAppsSettings();
  } catch (e) {
    debugPrint('检查应用列表读取权限失败: $e');
  }
  return false;
}

Future<void> openInstalledAppsSettings() async {
  await spePermission.invokeMethod('openInstalledAppsSettings');
}

Future<void> openAppDetailsSettings() async {
  await spePermission.invokeMethod('openAppDetailsSettings');
}

Future<bool> isNotificationPermissionGranted() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'isNotificationPermissionGranted',
        ) ??
        false;
  } catch (e) {
    debugPrint('检查通知权限失败: $e');
    return false;
  }
}

Future<bool> requestNotificationPermission() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'requestNotificationPermission',
        ) ??
        false;
  } catch (e) {
    debugPrint('请求通知权限失败: $e');
    return false;
  }
}

Future<bool> ensureNotificationPermission() async {
  if (await isNotificationPermissionGranted()) {
    return true;
  }
  return requestNotificationPermission();
}

Future<bool> isWorkspaceStorageAccessGranted() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'isWorkspaceStorageAccessGranted',
        ) ??
        false;
  } catch (e) {
    debugPrint('检查公共 workspace 访问权限失败: $e');
    return false;
  }
}

Future<void> openWorkspaceStorageSettings() async {
  await spePermission.invokeMethod('openWorkspaceStorageSettings');
}

Future<Map<String, dynamic>> prepareTermuxLiveWrapper() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'prepareTermuxLiveWrapper',
  );
  return Map<String, dynamic>.from(result ?? const {});
}

Future<bool> isUnknownAppInstallAllowed() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'isUnknownAppInstallAllowed',
        ) ??
        false;
  } catch (e) {
    debugPrint('检查未知应用安装权限失败: $e');
    return false;
  }
}

Future<void> openUnknownAppInstallSettings() async {
  await spePermission.invokeMethod('openUnknownAppInstallSettings');
}

Future<Map<String, dynamic>> downloadAndInstallTermuxApk(
  String downloadUrl,
) async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'downloadAndInstallTermuxApk',
    {'downloadUrl': downloadUrl},
  );
  return Map<String, dynamic>.from(result ?? const {});
}
