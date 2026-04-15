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

    private let modelProviderStore = ModelProviderProfileStore.shared

    private var specialPermissionChannel: FlutterMethodChannel?
    private var localModelChannel: FlutterMethodChannel?
    private var browserChannel: FlutterMethodChannel?
    private var fileChannel: FlutterMethodChannel?
    private var deviceChannel: FlutterMethodChannel?
    private var appStateChannel: FlutterMethodChannel?
    private var overlayChannel: FlutterMethodChannel?
    private var hideFromRecentsChannel: FlutterMethodChannel?
    private var assistCoreChannels: [FlutterMethodChannel] = []
    private var iosChromeChannels: [FlutterMethodChannel] = []

    private override init() {
        super.init()
    }

    func register(on engine: FlutterEngine) {
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
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        completion(.success(true))
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
        specialPermissionChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleSpecialPermissionCall(call, result: result, engine: engine)
        }

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

        let assistCoreChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/AssistCoreEvent",
            binaryMessenger: engine.binaryMessenger
        )
        assistCoreChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleAssistCoreCall(call, result: result)
        }
        assistCoreChannels.append(assistCoreChannel)

        let iosChromeChannel = FlutterMethodChannel(
            name: "cn.com.omnimind.bot/ios_chrome",
            binaryMessenger: engine.binaryMessenger
        )
        iosChromeChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleIOSChromeCall(call, result: result)
        }
        iosChromeChannels.append(iosChromeChannel)
    }

    private func handleSpecialPermissionCall(_ call: FlutterMethodCall, result: @escaping FlutterResult, engine: FlutterEngine) {
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
            let args = (call.arguments as? [String: Any]) ?? [:]
            let openSetup = args["openSetup"] as? Bool ?? false
            let setupPackageIds = (args["setupPackageIds"] as? [String]) ?? []
            _ = TerminalRuntimeCoordinator.shared.prepareRuntime()
            if openSetup && setupPackageIds.isEmpty == false {
                let installResult = TerminalRuntimeCoordinator.shared.installPackages(
                    PackageInstallRequestMessage(
                        packageIds: setupPackageIds,
                        allowThirdPartyRepositories: false
                    )
                )
                guard installResult.success else {
                    result(
                        FlutterError(
                            code: "OPEN_NATIVE_TERMINAL_SETUP_ERROR",
                            message: installResult.message,
                            details: nil
                        )
                    )
                    return
                }
            }
            let paths = TerminalRuntimeCoordinator.shared.resolveWorkspacePaths()
            pushFlutterRoute(
                "/home/omnibot_workspace",
                extra: [
                    "workspacePath": paths.rootPath,
                    "workspaceShellPath": paths.shellRootPath,
                    "workspaceId": NSNull(),
                ],
                on: engine
            )
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

    private func handleIOSChromeCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = (call.arguments as? [String: Any]) ?? [:]
        switch call.method {
        case "setBottomTabBarHidden":
            let hidden = arguments["hidden"] as? Bool ?? false
            OmnibotChromeCoordinator.shared.setBottomTabBarHidden(hidden)
            result(nil)
        case "getBottomTabBarHidden":
            result(OmnibotChromeCoordinator.shared.isBottomTabBarHidden)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleAssistCoreCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = (call.arguments as? [String: Any]) ?? [:]
        switch call.method {
        case "getModelProviderConfig":
            Task {
                result(await modelProviderStore.currentConfig())
            }
        case "listModelProviderProfiles":
            Task {
                result(await modelProviderStore.listProfilesPayload())
            }
        case "saveModelProviderProfile":
            do {
                let saved = try modelProviderStore.saveProfile(
                    id: arguments["id"] as? String,
                    name: arguments["name"] as? String ?? "",
                    baseURL: arguments["baseUrl"] as? String ?? "",
                    apiKey: arguments["apiKey"] as? String ?? "",
                    protocolType: arguments["protocolType"] as? String ?? "openai_compatible"
                )
                notifyAgentAIConfigChanged()
                result(saved)
            } catch {
                result(FlutterError(code: "SAVE_MODEL_PROVIDER_PROFILE_ERROR", message: error.localizedDescription, details: nil))
            }
        case "deleteModelProviderProfile":
            Task {
                do {
                    let payload = try await modelProviderStore.deleteProfile(
                        profileID: arguments["profileId"] as? String ?? ""
                    )
                    notifyAgentAIConfigChanged()
                    result(payload)
                } catch {
                    result(FlutterError(code: "DELETE_MODEL_PROVIDER_PROFILE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        case "setEditingModelProviderProfile":
            Task {
                do {
                    let selected = try await modelProviderStore.setEditingProfile(
                        arguments["profileId"] as? String ?? ""
                    )
                    notifyAgentAIConfigChanged()
                    result(selected)
                } catch {
                    result(FlutterError(code: "SET_EDITING_MODEL_PROVIDER_PROFILE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        case "saveModelProviderConfig":
            Task {
                do {
                    let saved = try await modelProviderStore.saveConfig(
                        baseURL: arguments["baseUrl"] as? String ?? "",
                        apiKey: arguments["apiKey"] as? String ?? ""
                    )
                    notifyAgentAIConfigChanged()
                    result(saved)
                } catch {
                    result(FlutterError(code: "SAVE_MODEL_PROVIDER_CONFIG_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        case "clearModelProviderConfig":
            Task {
                do {
                    let cleared = try await modelProviderStore.clearConfig()
                    notifyAgentAIConfigChanged()
                    result(cleared)
                } catch {
                    result(FlutterError(code: "CLEAR_MODEL_PROVIDER_CONFIG_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        case "fetchProviderModels":
            Task {
                do {
                    let models = try await modelProviderStore.fetchProviderModels(
                        apiBase: arguments["apiBase"] as? String ?? "",
                        apiKey: arguments["apiKey"] as? String ?? "",
                        profileID: arguments["profileId"] as? String
                    )
                    result(models)
                } catch {
                    result(FlutterError(code: "FETCH_PROVIDER_MODELS_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        case "getSceneModelCatalog":
            Task {
                result(await modelProviderStore.sceneModelCatalogPayload())
            }
        case "getSceneModelBindings":
            result(modelProviderStore.sceneModelBindingsPayload())
        case "saveSceneModelBinding":
            do {
                let bindings = try modelProviderStore.saveSceneModelBinding(
                    sceneId: arguments["sceneId"] as? String ?? "",
                    providerProfileId: arguments["providerProfileId"] as? String ?? "",
                    modelId: arguments["modelId"] as? String ?? ""
                )
                notifyAgentAIConfigChanged()
                result(bindings)
            } catch {
                result(FlutterError(code: "SAVE_SCENE_MODEL_BINDING_ERROR", message: error.localizedDescription, details: nil))
            }
        case "clearSceneModelBinding":
            let bindings = modelProviderStore.clearSceneModelBinding(
                sceneId: arguments["sceneId"] as? String ?? ""
            )
            notifyAgentAIConfigChanged()
            result(bindings)
        case "getSceneModelOverrides":
            result(modelProviderStore.sceneModelOverridesPayload())
        case "saveSceneModelOverride":
            Task {
                do {
                    let overrides = try await modelProviderStore.saveSceneModelOverride(
                        sceneId: arguments["sceneId"] as? String ?? "",
                        modelId: arguments["model"] as? String ?? ""
                    )
                    notifyAgentAIConfigChanged()
                    result(overrides)
                } catch {
                    result(FlutterError(code: "SAVE_SCENE_MODEL_OVERRIDE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        case "clearSceneModelOverride":
            let overrides = modelProviderStore.clearSceneModelOverride(
                sceneId: arguments["sceneId"] as? String ?? ""
            )
            notifyAgentAIConfigChanged()
            result(overrides)
        case "copyToClipboard":
            UIPasteboard.general.string = arguments["text"] as? String ?? ""
            result("SUCCESS")
        case "getClipboardText":
            result(UIPasteboard.general.string ?? "")
        case "getNanoTime":
            result(Int64(Date().timeIntervalSince1970 * 1000))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func notifyAgentAIConfigChanged() {
        let payload: [String: Any] = [
            "source": "file",
            "path": "/workspace/.omnibot/provider-config.json",
        ]
        for channel in assistCoreChannels {
            channel.invokeMethod("onAgentAiConfigChanged", arguments: payload)
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

    private func pushFlutterRoute(_ route: String, extra: [String: Any]? = nil, on engine: FlutterEngine) {
        let routerChannel = FlutterMethodChannel(name: "ui_router_channel", binaryMessenger: engine.binaryMessenger)
        var payload: [String: Any] = ["route": route]
        if let extra {
            payload["extra"] = extra
        }
        routerChannel.invokeMethod("push", arguments: payload)
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

    nonisolated private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
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
