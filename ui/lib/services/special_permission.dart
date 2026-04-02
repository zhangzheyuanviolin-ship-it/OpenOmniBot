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
    required this.completedAt,
  });

  final bool running;
  final bool completed;
  final bool? success;
  final double progress;
  final String stage;
  final List<String> logLines;
  final DateTime? completedAt;

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
      completedAt: _parseEmbeddedTerminalInitTimestamp(map['completedAt']),
    );
  }
}

DateTime? _parseEmbeddedTerminalInitTimestamp(dynamic rawValue) {
  if (rawValue is! num) {
    return null;
  }
  final millis = rawValue.toInt();
  if (millis <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

class EmbeddedTerminalRuntimeStatus {
  const EmbeddedTerminalRuntimeStatus({
    required this.supported,
    required this.runtimeReady,
    required this.basePackagesReady,
    required this.allReady,
    required this.missingCommands,
    required this.message,
    required this.nodeReady,
    required this.nodeVersion,
    required this.nodeMinMajor,
    required this.pnpmReady,
    required this.pnpmVersion,
    required this.workspaceAccessGranted,
  });

  final bool supported;
  final bool runtimeReady;
  final bool basePackagesReady;
  final bool allReady;
  final List<String> missingCommands;
  final String message;
  final bool nodeReady;
  final String? nodeVersion;
  final int nodeMinMajor;
  final bool pnpmReady;
  final String? pnpmVersion;
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
      nodeReady: map['nodeReady'] == true,
      nodeVersion: (map['nodeVersion'] as String?)?.trim(),
      nodeMinMajor: (map['nodeMinMajor'] as num?)?.toInt() ?? 22,
      pnpmReady: map['pnpmReady'] == true,
      pnpmVersion: (map['pnpmVersion'] as String?)?.trim(),
      workspaceAccessGranted: map['workspaceAccessGranted'] == true,
    );
  }
}

class EmbeddedTerminalSetupStatus {
  const EmbeddedTerminalSetupStatus({required this.packages});

  final Map<String, bool> packages;

  factory EmbeddedTerminalSetupStatus.fromMap(Map<dynamic, dynamic>? map) {
    final rawPackages = map?['packages'];
    final packages = <String, bool>{};
    if (rawPackages is Map) {
      for (final entry in rawPackages.entries) {
        packages[entry.key.toString()] = entry.value == true;
      }
    }
    return EmbeddedTerminalSetupStatus(packages: packages);
  }
}

class EmbeddedTerminalSetupInventoryItem {
  const EmbeddedTerminalSetupInventoryItem({
    required this.ready,
    required this.version,
  });

  final bool ready;
  final String? version;

  factory EmbeddedTerminalSetupInventoryItem.fromMap(
    Map<dynamic, dynamic>? map,
  ) {
    return EmbeddedTerminalSetupInventoryItem(
      ready: map?['ready'] == true,
      version: (map?['version'] as String?)?.trim(),
    );
  }
}

class EmbeddedTerminalSetupInventory {
  const EmbeddedTerminalSetupInventory({required this.packages});

  final Map<String, EmbeddedTerminalSetupInventoryItem> packages;

  factory EmbeddedTerminalSetupInventory.fromMap(Map<dynamic, dynamic>? map) {
    final rawPackages = map?['packages'];
    final packages = <String, EmbeddedTerminalSetupInventoryItem>{};
    if (rawPackages is Map) {
      for (final entry in rawPackages.entries) {
        packages[entry.key
            .toString()] = EmbeddedTerminalSetupInventoryItem.fromMap(
          entry.value is Map
              ? Map<dynamic, dynamic>.from(entry.value as Map)
              : const <dynamic, dynamic>{},
        );
      }
    }
    return EmbeddedTerminalSetupInventory(packages: packages);
  }
}

class EmbeddedTerminalSetupResult {
  const EmbeddedTerminalSetupResult({
    required this.success,
    required this.message,
    required this.output,
  });

  final bool success;
  final String message;
  final String output;

  factory EmbeddedTerminalSetupResult.fromMap(Map<dynamic, dynamic>? map) {
    return EmbeddedTerminalSetupResult(
      success: map?['success'] == true,
      message: (map?['message'] as String? ?? '').trim(),
      output: (map?['output'] as String? ?? '').trim(),
    );
  }
}

class EmbeddedTerminalSetupSessionSnapshot {
  const EmbeddedTerminalSetupSessionSnapshot({
    required this.sessionId,
    required this.running,
    required this.completed,
    required this.success,
    required this.message,
    required this.selectedPackageIds,
  });

  final String? sessionId;
  final bool running;
  final bool completed;
  final bool? success;
  final String message;
  final List<String> selectedPackageIds;

  bool get hasSession => (sessionId ?? '').trim().isNotEmpty;

  factory EmbeddedTerminalSetupSessionSnapshot.fromMap(
    Map<dynamic, dynamic>? map,
  ) {
    final rawSelectedPackageIds = map?['selectedPackageIds'];
    return EmbeddedTerminalSetupSessionSnapshot(
      sessionId: (map?['sessionId'] as String?)?.trim(),
      running: map?['running'] == true,
      completed: map?['completed'] == true,
      success: map?['success'] as bool?,
      message: (map?['message'] as String? ?? '').trim(),
      selectedPackageIds: rawSelectedPackageIds is List
          ? rawSelectedPackageIds
                .map((item) => item.toString())
                .where((item) => item.trim().isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class EmbeddedTerminalAutoStartTask {
  const EmbeddedTerminalAutoStartTask({
    required this.id,
    required this.name,
    required this.command,
    required this.workingDirectory,
    required this.enabled,
    required this.running,
    required this.sessionId,
  });

  final String id;
  final String name;
  final String command;
  final String? workingDirectory;
  final bool enabled;
  final bool running;
  final String sessionId;

  factory EmbeddedTerminalAutoStartTask.fromMap(Map<dynamic, dynamic>? map) {
    return EmbeddedTerminalAutoStartTask(
      id: (map?['id'] as String? ?? '').trim(),
      name: (map?['name'] as String? ?? '').trim(),
      command: (map?['command'] as String? ?? '').trim(),
      workingDirectory: (map?['workingDirectory'] as String?)?.trim(),
      enabled: map?['enabled'] != false,
      running: map?['running'] == true,
      sessionId: (map?['sessionId'] as String? ?? '').trim(),
    );
  }
}

class EmbeddedTerminalAutoStartTaskList {
  const EmbeddedTerminalAutoStartTaskList({required this.tasks});

  final List<EmbeddedTerminalAutoStartTask> tasks;

  factory EmbeddedTerminalAutoStartTaskList.fromMap(
    Map<dynamic, dynamic>? map,
  ) {
    final rawTasks = map?['tasks'];
    return EmbeddedTerminalAutoStartTaskList(
      tasks: rawTasks is List
          ? rawTasks
                .map(
                  (item) => EmbeddedTerminalAutoStartTask.fromMap(
                    item is Map
                        ? Map<dynamic, dynamic>.from(item)
                        : const <dynamic, dynamic>{},
                  ),
                )
                .toList(growable: false)
          : const <EmbeddedTerminalAutoStartTask>[],
    );
  }
}

class EmbeddedTerminalAutoStartTaskRunResult {
  const EmbeddedTerminalAutoStartTaskRunResult({
    required this.taskId,
    required this.started,
    required this.alreadyRunning,
    required this.message,
    required this.sessionId,
  });

  final String taskId;
  final bool started;
  final bool alreadyRunning;
  final String message;
  final String sessionId;

  factory EmbeddedTerminalAutoStartTaskRunResult.fromMap(
    Map<dynamic, dynamic>? map,
  ) {
    return EmbeddedTerminalAutoStartTaskRunResult(
      taskId: (map?['taskId'] as String? ?? '').trim(),
      started: map?['started'] == true,
      alreadyRunning: map?['alreadyRunning'] == true,
      message: (map?['message'] as String? ?? '').trim(),
      sessionId: (map?['sessionId'] as String? ?? '').trim(),
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

Future<EmbeddedTerminalSetupStatus> getEmbeddedTerminalSetupStatus() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getEmbeddedTerminalSetupStatus',
  );
  return EmbeddedTerminalSetupStatus.fromMap(result ?? const {});
}

Future<EmbeddedTerminalSetupInventory>
getEmbeddedTerminalSetupInventory() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getEmbeddedTerminalSetupInventory',
  );
  return EmbeddedTerminalSetupInventory.fromMap(result ?? const {});
}

Future<EmbeddedTerminalSetupSessionSnapshot>
getEmbeddedTerminalSetupSessionSnapshot() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getEmbeddedTerminalSetupSessionSnapshot',
  );
  return EmbeddedTerminalSetupSessionSnapshot.fromMap(result ?? const {});
}

Future<EmbeddedTerminalSetupResult> installEmbeddedTerminalPackages(
  List<String> packageIds,
) async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'installEmbeddedTerminalPackages',
    {'packageIds': packageIds},
  );
  return EmbeddedTerminalSetupResult.fromMap(result ?? const {});
}

Future<EmbeddedTerminalSetupSessionSnapshot> startEmbeddedTerminalSetupSession(
  List<String> packageIds,
) async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'startEmbeddedTerminalSetupSession',
    {'packageIds': packageIds},
  );
  return EmbeddedTerminalSetupSessionSnapshot.fromMap(result ?? const {});
}

Future<void> dismissEmbeddedTerminalSetupSession() async {
  await spePermission.invokeMethod<void>('dismissEmbeddedTerminalSetupSession');
}

Future<EmbeddedTerminalAutoStartTaskList>
getEmbeddedTerminalAutoStartTasks() async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'getEmbeddedTerminalAutoStartTasks',
  );
  return EmbeddedTerminalAutoStartTaskList.fromMap(result ?? const {});
}

Future<EmbeddedTerminalAutoStartTask> saveEmbeddedTerminalAutoStartTask({
  String? id,
  required String name,
  required String command,
  String? workingDirectory,
  required bool enabled,
}) async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'saveEmbeddedTerminalAutoStartTask',
    <String, dynamic>{
      'id': id,
      'name': name,
      'command': command,
      'workingDirectory': workingDirectory,
      'enabled': enabled,
    },
  );
  return EmbeddedTerminalAutoStartTask.fromMap(result ?? const {});
}

Future<void> deleteEmbeddedTerminalAutoStartTask(String id) async {
  await spePermission.invokeMethod<void>(
    'deleteEmbeddedTerminalAutoStartTask',
    {'id': id},
  );
}

Future<EmbeddedTerminalAutoStartTaskRunResult> runEmbeddedTerminalAutoStartTask(
  String id,
) async {
  final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
    'runEmbeddedTerminalAutoStartTask',
    <String, dynamic>{'id': id},
  );
  return EmbeddedTerminalAutoStartTaskRunResult.fromMap(result ?? const {});
}

Future<void> openNativeTerminal({
  bool openSetup = false,
  List<String> setupPackageIds = const <String>[],
}) async {
  await spePermission.invokeMethod<void>('openNativeTerminal', {
    'openSetup': openSetup,
    'setupPackageIds': setupPackageIds,
  });
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
    debugPrint('检查内置 workspace 状态失败: $e');
    return false;
  }
}

Future<void> openWorkspaceStorageSettings() async {
  await spePermission.invokeMethod('openWorkspaceStorageSettings');
}

Future<bool> isPublicStorageAccessGranted() async {
  try {
    return await spePermission.invokeMethod<bool>(
          'isPublicStorageAccessGranted',
        ) ??
        false;
  } catch (e) {
    debugPrint('检查公共文件访问权限失败: $e');
    return false;
  }
}

Future<void> openPublicStorageSettings() async {
  await spePermission.invokeMethod('openPublicStorageSettings');
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
