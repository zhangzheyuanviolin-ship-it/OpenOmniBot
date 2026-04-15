import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/generated/host_bridge.g.dart',
    dartOptions: DartOptions(),
    swiftOut: '../ios_app/Runner/Generated/HostBridge.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
enum ToolExecutionStateMessage {
  success,
  unsupported,
  userMediated,
  policyBlocked,
}

class HostCapabilitiesMessage {
  HostCapabilitiesMessage({
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

  String platform;
  bool appStoreDistribution;
  bool supportsTerminal;
  bool supportsApkInstall;
  bool supportsLocalModels;
  bool supportsInAppBrowserAutomation;
  bool supportsExternalAppAutomation;
  bool supportsOverlay;
  bool supportsPreciseBackgroundSchedule;
  bool supportsSpeechRecognition;
  bool supportsWorkspacePublicStorage;
}

class WorkspacePathsMessage {
  WorkspacePathsMessage({
    required this.rootPath,
    required this.shellRootPath,
    required this.internalRootPath,
  });

  String rootPath;
  String shellRootPath;
  String internalRootPath;
}

class TerminalRuntimeStatusMessage {
  TerminalRuntimeStatusMessage({
    required this.supported,
    required this.runtimeReady,
    required this.basePackagesReady,
    required this.allReady,
    required this.missingCommands,
    required this.message,
    required this.nodeReady,
    this.nodeVersion,
    required this.nodeMinMajor,
    required this.pnpmReady,
    this.pnpmVersion,
    required this.workspaceAccessGranted,
    required this.repoInstallEnabled,
  });

  bool supported;
  bool runtimeReady;
  bool basePackagesReady;
  bool allReady;
  List<String> missingCommands;
  String message;
  bool nodeReady;
  String? nodeVersion;
  int nodeMinMajor;
  bool pnpmReady;
  String? pnpmVersion;
  bool workspaceAccessGranted;
  bool repoInstallEnabled;
}

class TerminalSessionSnapshotMessage {
  TerminalSessionSnapshotMessage({
    required this.sessionId,
    required this.currentDirectory,
    required this.transcript,
    required this.commandRunning,
  });

  String sessionId;
  String currentDirectory;
  String transcript;
  bool commandRunning;
}

class TerminalCommandRequestMessage {
  TerminalCommandRequestMessage({
    required this.command,
    this.workingDirectory,
    required this.timeoutSeconds,
    required this.environment,
  });

  String command;
  String? workingDirectory;
  int timeoutSeconds;
  Map<String?, String?> environment;
}

class TerminalCommandResultMessage {
  TerminalCommandResultMessage({
    required this.success,
    required this.timedOut,
    this.exitCode,
    required this.output,
    this.errorMessage,
    required this.sessionId,
    required this.transcript,
    required this.currentDirectory,
    required this.completed,
    required this.executionState,
  });

  bool success;
  bool timedOut;
  int? exitCode;
  String output;
  String? errorMessage;
  String sessionId;
  String transcript;
  String currentDirectory;
  bool completed;
  ToolExecutionStateMessage executionState;
}

class PackageInstallRequestMessage {
  PackageInstallRequestMessage({
    required this.packageIds,
    required this.allowThirdPartyRepositories,
  });

  List<String> packageIds;
  bool allowThirdPartyRepositories;
}

class PackageInstallResultMessage {
  PackageInstallResultMessage({
    required this.success,
    required this.message,
    required this.output,
    required this.executionState,
    required this.installedPackages,
  });

  bool success;
  String message;
  String output;
  ToolExecutionStateMessage executionState;
  List<String> installedPackages;
}

class LocalModelBackendMessage {
  LocalModelBackendMessage({
    required this.id,
    required this.label,
    required this.available,
  });

  String id;
  String label;
  bool available;
}

class LocalModelStatusMessage {
  LocalModelStatusMessage({
    required this.apiRunning,
    required this.apiReady,
    required this.apiState,
    required this.apiHost,
    required this.apiPort,
    required this.baseUrl,
    this.activeModelId,
    required this.backend,
    required this.loadedBackend,
    this.loadedModelId,
    required this.backends,
  });

  bool apiRunning;
  bool apiReady;
  String apiState;
  String apiHost;
  int apiPort;
  String baseUrl;
  String? activeModelId;
  String backend;
  String loadedBackend;
  String? loadedModelId;
  List<LocalModelBackendMessage> backends;
}

class BrowserSessionSnapshotMessage {
  BrowserSessionSnapshotMessage({
    required this.available,
    required this.workspaceId,
    this.activeTabId,
    required this.currentUrl,
    required this.title,
    this.userAgentProfile,
  });

  bool available;
  String workspaceId;
  int? activeTabId;
  String currentUrl;
  String title;
  String? userAgentProfile;
}

class PermissionSnapshotMessage {
  PermissionSnapshotMessage({
    required this.microphoneGranted,
    required this.speechRecognitionGranted,
    required this.notificationGranted,
    required this.filesAccessAvailable,
    required this.overlaySupported,
    required this.externalAutomationSupported,
  });

  bool microphoneGranted;
  bool speechRecognitionGranted;
  bool notificationGranted;
  bool filesAccessAvailable;
  bool overlaySupported;
  bool externalAutomationSupported;
}

class DeviceInfoMessage {
  DeviceInfoMessage({
    required this.deviceId,
    required this.model,
    required this.localizedModel,
    required this.systemVersion,
    required this.appVersion,
    required this.platform,
    this.ipAddress,
  });

  String deviceId;
  String model;
  String localizedModel;
  String systemVersion;
  String appVersion;
  String platform;
  String? ipAddress;
}

@HostApi()
abstract class HostCapabilitiesApi {
  HostCapabilitiesMessage getCapabilities();
}

@HostApi()
abstract class WorkspaceBridgeApi {
  WorkspacePathsMessage resolveWorkspacePaths();
}

@HostApi()
abstract class TerminalRuntimeBridgeApi {
  @async
  TerminalRuntimeStatusMessage inspectRuntime();

  @async
  TerminalRuntimeStatusMessage prepareRuntime();

  @async
  TerminalSessionSnapshotMessage openSession(String? workingDirectory);

  @async
  TerminalCommandResultMessage exec(TerminalCommandRequestMessage request);

  @async
  TerminalSessionSnapshotMessage writeStdin(String sessionId, String text);

  @async
  TerminalSessionSnapshotMessage readSession(String sessionId);

  @async
  void closeSession(String sessionId);

  @async
  PackageInstallResultMessage installPackages(
    PackageInstallRequestMessage request,
  );

  @async
  List<String> listInstalledPackages();
}

@HostApi()
abstract class LocalModelBridgeApi {
  @async
  LocalModelStatusMessage getStatus();

  @async
  LocalModelStatusMessage loadModel(String modelId, String backendId);

  @async
  LocalModelStatusMessage stopModel();
}

@HostApi()
abstract class BrowserBridgeApi {
  BrowserSessionSnapshotMessage getLiveSessionSnapshot();
}

@HostApi()
abstract class PermissionBridgeApi {
  @async
  PermissionSnapshotMessage getPermissionSnapshot();

  @async
  bool openAppSettings();
}

@HostApi()
abstract class DeviceBridgeApi {
  @async
  DeviceInfoMessage getDeviceInfo();
}
