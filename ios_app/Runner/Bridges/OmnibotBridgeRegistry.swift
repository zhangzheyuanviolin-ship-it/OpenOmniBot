import AVFoundation
@preconcurrency import Flutter
import Foundation
import Speech
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class OmnibotBridgeRegistry: NSObject, @preconcurrency HostCapabilitiesApi, @preconcurrency WorkspaceBridgeApi, @preconcurrency TerminalRuntimeBridgeApi, @preconcurrency LocalModelBridgeApi, @preconcurrency BrowserBridgeApi, @preconcurrency PermissionBridgeApi, @preconcurrency DeviceBridgeApi {
    static let shared = OmnibotBridgeRegistry()

    private weak var engine: FlutterEngine?
    private var specialPermissionChannel: FlutterMethodChannel?
    private var localModelChannel: FlutterMethodChannel?
    private var browserChannel: FlutterMethodChannel?
    private var fileChannel: FlutterMethodChannel?
    private var deviceChannel: FlutterMethodChannel?
    private var appStateChannel: FlutterMethodChannel?
    private var overlayChannel: FlutterMethodChannel?
    private var hideFromRecentsChannel: FlutterMethodChannel?

    private override init() {
        super.init()
    }

    func register(on engine: FlutterEngine) {
        self.engine = engine
        HostCapabilitiesApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        WorkspaceBridgeApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        TerminalRuntimeBridgeApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        LocalModelBridgeApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        BrowserBridgeApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        PermissionBridgeApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        DeviceBridgeApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
        registerLegacyChannels(on: engine)
    }

    func getCapabilities() throws -> HostCapabilitiesMessage {
        HostCapabilitiesMessage(
            platform: "ios",
            appStoreDistribution: true,
            supportsTerminal: true,
            supportsApkInstall: true,
            supportsLocalModels: true,
            supportsInAppBrowserAutomation: true,
            supportsExternalAppAutomation: false,
            supportsOverlay: false,
            supportsPreciseBackgroundSchedule: false,
            supportsSpeechRecognition: true,
            supportsWorkspacePublicStorage: true
        )
    }

    func resolveWorkspacePaths() throws -> WorkspacePathsMessage {
        TerminalRuntimeCoordinator.shared.resolveWorkspacePaths()
    }

    func inspectRuntime(completion: @escaping (Result<TerminalRuntimeStatusMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.inspectRuntime()))
    }

    func prepareRuntime(completion: @escaping (Result<TerminalRuntimeStatusMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.prepareRuntime()))
    }

    func openSession(workingDirectory: String?, completion: @escaping (Result<TerminalSessionSnapshotMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.openSession(workingDirectory: workingDirectory)))
    }

    func exec(request: TerminalCommandRequestMessage, completion: @escaping (Result<TerminalCommandResultMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.exec(request: request)))
    }

    func writeStdin(sessionId: String, text: String, completion: @escaping (Result<TerminalSessionSnapshotMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.writeStdin(sessionId: sessionId, text: text)))
    }

    func readSession(sessionId: String, completion: @escaping (Result<TerminalSessionSnapshotMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.readSession(sessionId: sessionId)))
    }

    func closeSession(sessionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        TerminalRuntimeCoordinator.shared.closeSession(sessionId: sessionId)
        completion(.success(()))
    }

    func installPackages(request: PackageInstallRequestMessage, completion: @escaping (Result<PackageInstallResultMessage, Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.installPackages(request)))
    }

    func listInstalledPackages(completion: @escaping (Result<[String], Error>) -> Void) {
        completion(.success(TerminalRuntimeCoordinator.shared.listInstalledPackagesSync()))
    }

    func getStatus(completion: @escaping (Result<LocalModelStatusMessage, Error>) -> Void) {
        Task {
            completion(.success(await LocalModelCoordinator.shared.statusMessage()))
        }
    }

    func loadModel(modelId: String, backendId: String, completion: @escaping (Result<LocalModelStatusMessage, Error>) -> Void) {
        Task {
            do {
                completion(.success(try await LocalModelCoordinator.shared.loadModel(modelId: modelId, backendId: backendId)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func stopModel(completion: @escaping (Result<LocalModelStatusMessage, Error>) -> Void) {
        Task {
            completion(.success(await LocalModelCoordinator.shared.stopModel()))
        }
    }

    func getLiveSessionSnapshot() throws -> BrowserSessionSnapshotMessage {
        BrowserSessionStore.shared.currentSnapshot()
    }

    func getPermissionSnapshot(completion: @escaping (Result<PermissionSnapshotMessage, Error>) -> Void) {
        Task {
            completion(.success(await makePermissionSnapshot()))
        }
    }

    func openAppSettings(completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            completion(.success(false))
            return
        }
        UIApplication.shared.open(url) { success in
            completion(.success(success))
        }
    }

    func getDeviceInfo(completion: @escaping (Result<DeviceInfoMessage, Error>) -> Void) {
        let device = UIDevice.current
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        completion(
            .success(
                DeviceInfoMessage(
                    deviceId: device.identifierForVendor?.uuidString ?? UUID().uuidString,
                    model: device.model,
                    localizedModel: device.localizedModel,
                    systemVersion: device.systemVersion,
                    appVersion: version,
                    platform: "ios",
                    ipAddress: nil
                )
            )
        )
    }

    private func registerLegacyChannels(on engine: FlutterEngine) {
        specialPermissionChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/SpecialPermissionEvent",
            binaryMessenger: engine.binaryMessenger
        )
        specialPermissionChannel?.setMethodCallHandler(handleSpecialPermissionCall)

        let specialPermissionEvents = FlutterEventChannel(
            name: "cn.com.omnimind.bot/SpecialPermissionEvents",
            binaryMessenger: engine.binaryMessenger
        )
        specialPermissionEvents.setStreamHandler(EmptyStreamHandler())

        localModelChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/MnnLocalModels",
            binaryMessenger: engine.binaryMessenger
        )
        localModelChannel?.setMethodCallHandler(handleLocalModelCall)

        let localModelEvents = FlutterEventChannel(
            name: "cn.com.omnimind.bot/MnnLocalModelsEvents",
            binaryMessenger: engine.binaryMessenger
        )
        localModelEvents.setStreamHandler(EmptyStreamHandler())

        browserChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/AgentBrowserSession",
            binaryMessenger: engine.binaryMessenger
        )
        browserChannel?.setMethodCallHandler(handleBrowserCall)

        fileChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/file_save",
            binaryMessenger: engine.binaryMessenger
        )
        fileChannel?.setMethodCallHandler(handleFileCall)

        deviceChannel = FlutterMethodChannel(
            name: "device_info",
            binaryMessenger: engine.binaryMessenger
        )
        deviceChannel?.setMethodCallHandler(handleDeviceCall)

        appStateChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/app_state",
            binaryMessenger: engine.binaryMessenger
        )
        appStateChannel?.setMethodCallHandler(handleAppStateCall)

        overlayChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/overlay",
            binaryMessenger: engine.binaryMessenger
        )
        overlayChannel?.setMethodCallHandler(handleOverlayCall)

        hideFromRecentsChannel = FlutterMethodChannel(
            name: "hide_from_recents",
            binaryMessenger: engine.binaryMessenger
        )
        hideFromRecentsChannel?.setMethodCallHandler(handleHideFromRecentsCall)
    }

    private func handleSpecialPermissionCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getWorkspacePathSnapshot":
            let paths = TerminalRuntimeCoordinator.shared.resolveWorkspacePaths()
            result([
                "rootPath": paths.rootPath,
                "shellRootPath": paths.shellRootPath,
                "internalRootPath": paths.internalRootPath,
            ])
        case "getEmbeddedTerminalRuntimeStatus":
            let status = TerminalRuntimeCoordinator.shared.inspectRuntime()
            result(terminalStatusDictionary(status))
        case "getEmbeddedTerminalSetupStatus":
            result(["packages": Dictionary(uniqueKeysWithValues: TerminalRuntimeCoordinator.shared.listInstalledPackagesSync().map { ($0, true) })])
        case "getEmbeddedTerminalSetupInventory":
            result([
                "packages": Dictionary(uniqueKeysWithValues: TerminalRuntimeCoordinator.shared.listInstalledPackagesSync().map { ($0, ["ready": true, "version": NSNull()]) })
            ])
        case "getEmbeddedTerminalSetupSessionSnapshot":
            result(TerminalRuntimeCoordinator.shared.currentSetupSnapshot())
        case "installEmbeddedTerminalPackages":
            let args = (call.arguments as? [String: Any]) ?? [:]
            let packageIds = (args["packageIds"] as? [String]) ?? []
            let response = TerminalRuntimeCoordinator.shared.installPackages(
                PackageInstallRequestMessage(
                    packageIds: packageIds,
                    allowThirdPartyRepositories: false
                )
            )
            result([
                "success": response.success,
                "message": response.message,
                "output": response.output,
            ])
        case "startEmbeddedTerminalSetupSession":
            let args = (call.arguments as? [String: Any]) ?? [:]
            let packageIds = (args["packageIds"] as? [String]) ?? []
            _ = TerminalRuntimeCoordinator.shared.installPackages(
                PackageInstallRequestMessage(
                    packageIds: packageIds,
                    allowThirdPartyRepositories: false
                )
            )
            result([
                "sessionId": "ios-terminal-setup",
                "running": false,
                "completed": true,
                "success": true,
                "progress": 1.0,
                "stage": "completed",
                "logLines": ["Runtime prepared on iOS"],
            ])
        case "dismissEmbeddedTerminalSetupSession":
            result(nil)
        case "openNativeTerminal":
            pushFlutterRoute("/home/omnibot_workspace")
            result(true)
        case "isAccessibilityServiceEnabled", "isOverlayPermission", "isInstalledAppsPermissionGranted":
            result(false)
        case "isIgnoringBatteryOptimizations":
            result(true)
        case "openAccessibilitySettings", "openOverlaySettings", "openInstalledAppsSettings",
             "openBatteryOptimizationSettings", "openAppDetailsSettings", "openWorkspaceStorageSettings",
             "openPublicStorageSettings", "openUnknownAppInstallSettings", "openAutoStartSettings":
            openSettings()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleLocalModelCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            switch call.method {
            case "getConfig":
                let status = await LocalModelCoordinator.shared.statusMessage()
                result(localModelConfigDictionary(status))
            case "setActiveModel":
                let args = (call.arguments as? [String: Any]) ?? [:]
                let modelId = args["modelId"] as? String ?? ""
                let status = try? await LocalModelCoordinator.shared.loadModel(modelId: modelId, backendId: "llama.cpp")
                let resolvedStatus: LocalModelStatusMessage
                if let status {
                    resolvedStatus = status
                } else {
                    resolvedStatus = await LocalModelCoordinator.shared.statusMessage()
                }
                result(localModelConfigDictionary(resolvedStatus))
            case "startApiService":
                let args = (call.arguments as? [String: Any]) ?? [:]
                let modelId = args["modelId"] as? String ?? ""
                let status = try? await LocalModelCoordinator.shared.loadModel(modelId: modelId, backendId: "llama.cpp")
                let resolvedStatus: LocalModelStatusMessage
                if let status {
                    resolvedStatus = status
                } else {
                    resolvedStatus = await LocalModelCoordinator.shared.statusMessage()
                }
                result(localModelConfigDictionary(resolvedStatus))
            case "stopApiService":
                let status = await LocalModelCoordinator.shared.stopModel()
                result(localModelConfigDictionary(status))
            case "getBackend":
                let status = await LocalModelCoordinator.shared.statusMessage()
                result(status.backend)
            case "setBackend":
                let args = (call.arguments as? [String: Any]) ?? [:]
                result((args["backend"] as? String) ?? "llama.cpp")
            case "getOverview":
                let status = await LocalModelCoordinator.shared.statusMessage()
                result([
                    "config": localModelConfigDictionary(status),
                    "installedModels": [],
                    "market": [
                        "source": "bundled",
                        "category": "llm",
                        "availableSources": ["bundled", "workspace"],
                        "models": [],
                    ],
                ])
            case "listInstalledModels", "refreshInstalledModels":
                result([])
            case "listMarketModels":
                result([
                    "source": "bundled",
                    "category": "llm",
                    "availableSources": ["bundled", "workspace"],
                    "models": [],
                ])
            case "startDownload", "pauseDownload":
                result(nil)
            case "deleteModel":
                result([])
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleBrowserCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getLiveBrowserSessionSnapshot":
            let snapshot = BrowserSessionStore.shared.currentSnapshot()
            result(browserSnapshotDictionary(snapshot))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleFileCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = (call.arguments as? [String: Any]) ?? [:]
        let path = args["sourcePath"] as? String ?? ""
        let url = URL(fileURLWithPath: path)
        switch call.method {
        case "saveFileWithSystemDialog":
            presentDocumentExporter(for: url)
            result(path)
        case "openFile", "shareFile":
            presentShareSheet(for: url)
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleDeviceCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let device = UIDevice.current
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        switch call.method {
        case "getAndroidId":
            result(device.identifierForVendor?.uuidString)
        case "getDeviceInfo":
            result([
                "deviceId": device.identifierForVendor?.uuidString ?? UUID().uuidString,
                "model": device.model,
                "localizedModel": device.localizedModel,
                "systemVersion": device.systemVersion,
                "platform": "ios",
            ])
        case "getIpAddress":
            result(nil)
        case "getAppVersion":
            result([
                "versionName": appVersion,
                "platform": "ios",
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleAppStateCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initHalfScreenEngine", "clearPendingShareDraft", "applyLanguagePreference":
            result(true)
        case "exitApp":
            result(false)
        case "getPendingShareDraft":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleOverlayCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showMessage":
            result(false)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleHideFromRecentsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setExcludeFromRecents":
            result(false)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func terminalStatusDictionary(_ status: TerminalRuntimeStatusMessage) -> [String: Any] {
        [
            "supported": status.supported,
            "runtimeReady": status.runtimeReady,
            "basePackagesReady": status.basePackagesReady,
            "allReady": status.allReady,
            "missingCommands": status.missingCommands,
            "message": status.message,
            "nodeReady": status.nodeReady,
            "nodeVersion": status.nodeVersion as Any,
            "nodeMinMajor": status.nodeMinMajor,
            "pnpmReady": status.pnpmReady,
            "pnpmVersion": status.pnpmVersion as Any,
            "workspaceAccessGranted": status.workspaceAccessGranted,
        ]
    }

    private func localModelConfigDictionary(_ status: LocalModelStatusMessage) -> [String: Any] {
        [
            "backend": status.backend,
            "autoStartOnAppOpen": false,
            "apiRunning": status.apiRunning,
            "apiReady": status.apiReady,
            "apiState": status.apiState,
            "apiHost": status.apiHost,
            "apiPort": status.apiPort,
            "baseUrl": status.baseUrl,
            "activeModelId": status.activeModelId as Any,
            "downloadProvider": "OmniInfer",
            "availableSources": ["bundled", "workspace"],
            "loadedBackend": status.loadedBackend,
            "loadedModelId": status.loadedModelId as Any,
        ]
    }

    private func browserSnapshotDictionary(_ snapshot: BrowserSessionSnapshotMessage) -> [String: Any] {
        [
            "available": snapshot.available,
            "workspaceId": snapshot.workspaceId,
            "activeTabId": snapshot.activeTabId as Any,
            "currentUrl": snapshot.currentUrl,
            "title": snapshot.title,
            "userAgentProfile": snapshot.userAgentProfile as Any,
        ]
    }

    private func pushFlutterRoute(_ route: String) {
        guard let engine else { return }
        let routerChannel = FlutterMethodChannel(name: "ui_router_channel", binaryMessenger: engine.binaryMessenger)
        routerChannel.invokeMethod("push", arguments: ["route": route])
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func presentDocumentExporter(for url: URL) {
        guard let presenter = topPresenter() else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        presenter.present(picker, animated: true)
    }

    private func presentShareSheet(for url: URL) {
        guard let presenter = topPresenter() else { return }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        presenter.present(controller, animated: true)
    }

    private func topPresenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        return root?.topPresentedController ?? root
    }

    private func makePermissionSnapshot() async -> PermissionSnapshotMessage {
        let microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        let authorizationStatus = await notificationAuthorizationStatus()
        let notificationsGranted = authorizationStatus == .authorized || authorizationStatus == .provisional
        return PermissionSnapshotMessage(
            microphoneGranted: microphoneGranted,
            speechRecognitionGranted: speechGranted,
            notificationGranted: notificationsGranted,
            filesAccessAvailable: true,
            overlaySupported: false,
            externalAutomationSupported: false
        )
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}

private final class EmptyStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        nil
    }
}

private extension UIViewController {
    var topPresentedController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topPresentedController
        }
        return self
    }
}
